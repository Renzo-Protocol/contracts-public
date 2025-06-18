// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "./xRenzoDepositNativeBridgeStorage.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    IERC20MetadataUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "../../Errors/Errors.sol";
import "../xERC20/interfaces/IXERC20.sol";
import "../Connext/core/IWeth.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../../RateProvider/IRateProvider.sol";

/**
 * @author  Renzo
 * @title   xRenzoDeposit Contract
 * @dev     Tokens are sent to this contract via deposit, xezETH is minted for the user,
 *          and funds are batched and bridged down to the L1 for depositing into the Renzo Protocol.
 *          Any ezETH minted on the L1 will be locked in the lockbox for unwrapping at a later time with xezETH.
 * @notice  Allows L2 minting of xezETH tokens in exchange for deposited assets
 */

contract xRenzoDepositNativeBridge is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IRateProvider,
    xRenzoDepositNativeBridgeStorageV1
{
    using SafeERC20 for IERC20;

    /// @dev - This contract expects all tokens to have 18 decimals for pricing
    uint8 public constant EXPECTED_DECIMALS = 18;

    /// @dev - Fee basis point, 100 basis point = 1 %
    uint32 public constant FEE_BASIS = 10000;

    IERC20 public constant ETH_NATIVE_TOKEN_ADDRESS =
        IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    uint256 public constant MIN_DUST_BRIDGE = 500000 gwei;

    event PriceUpdated(uint256 price, uint256 timestamp);
    event Deposit(address indexed user, uint256 amountIn, uint256 amountOut);
    event BridgeSwept(address token, uint256 amount, address sweeper);
    event ReceiverPriceFeedUpdated(address newReceiver, address oldReceiver);
    event SweeperBridgeFeeCollected(address sweeper, address token, uint256 feeCollected);
    event BridgeFeeShareUpdated(uint256 oldBridgeFeeShare, uint256 newBridgeFeeShare);
    event SweepBatchSizeUpdated(uint256 oldSweepBatchSize, uint256 newSweepBatchSize);
    event TokenSupportUpdated(
        address token,
        bool supported,
        address oracle,
        address valueTransferBridge
    );
    event TokenTimeDiscountUpdated(address token, uint256 oldDiscount, uint256 newDiscount);

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice  Initializes the contract with initial vars
     * @dev     All tokens are expected to have 18 decimals
     * @param   _currentPrice  Initializes it with an initial price of ezETH to ETH
     * @param   _xezETH  L2 ezETH token
     * @param   _weth  WETH token for wrapping ETH - can be 0x0 if not supported
     * @param   _receiver Renzo Receiver middleware contract for price feed
     * @param   _mainnetDestinationDomain  The mainnet destination domain to receive bridge funds
     * @param   _mainnetRecipient  The contract on mainnet to receive bridge funds
     * @param   _bridgeFeeCollector  The address to collect bridge fees - is sent funds as they are collected
     */
    function initialize(
        uint256 _currentPrice,
        IERC20 _xezETH,
        IWeth _weth,
        address _receiver,
        uint32 _mainnetDestinationDomain,
        address _mainnetRecipient,
        address _bridgeFeeCollector
    ) public initializer {
        // Initialize inherited classes
        __Ownable_init();
        __ReentrancyGuard_init();

        // Verify valid non zero values
        if (
            _currentPrice == 0 ||
            address(_xezETH) == address(0) ||
            address(_weth) == address(0) ||
            address(_receiver) == address(0) ||
            _mainnetDestinationDomain == 0 ||
            _mainnetRecipient == address(0) ||
            _bridgeFeeCollector == address(0)
        ) {
            revert InvalidZeroInput();
        }

        // Verify all tokens have 18 decimals
        uint8 decimals = IERC20MetadataUpgradeable(address(_xezETH)).decimals();
        if (decimals != EXPECTED_DECIMALS) {
            revert InvalidTokenDecimals(EXPECTED_DECIMALS, decimals);
        }

        decimals = IERC20MetadataUpgradeable(address(_weth)).decimals();
        if (decimals != EXPECTED_DECIMALS) {
            revert InvalidTokenDecimals(EXPECTED_DECIMALS, decimals);
        }

        // Initialize the price and timestamp
        lastPrice = _currentPrice;
        lastPriceTimestamp = block.timestamp;

        // Set xezETH address
        xezETH = _xezETH;

        // Set WETH address
        weth = _weth;

        // Set price receiver contract address
        receiver = _receiver;

        // Set the destination domain and recipient
        mainnetDestinationDomain = _mainnetDestinationDomain;
        mainnetRecipient = _mainnetRecipient;

        // set bridge Fee Share 0.05% where 100 basis point = 1%
        bridgeFeeShare = 5;

        //set sweep batch size to 32 ETH
        sweepBatchSize = 32 ether;

        // Set the bridge fee collector
        bridgeFeeCollector = _bridgeFeeCollector;
    }

    /**
     * @notice  Accepts deposit for the user in the native asset and mints xezETH
     * @dev     This function allows anyone to call and deposit the native asset for xezETH
     *          ezETH will be immediately minted based on the current price
     * @param   _minOut  Minimum number of xezETH to accept to ensure slippage minimums
     * @param   _deadline  latest timestamp to accept this transaction
     * @return  uint256  Amount of xezETH minted to calling account
     */
    function depositETH(
        uint256 _minOut,
        uint256 _deadline
    ) external payable nonReentrant returns (uint256) {
        if (msg.value == 0) {
            revert InvalidZeroInput();
        }

        // Calculate bridgeFee for deposit amount
        uint256 bridgeFee = getBridgeFeeShare(msg.value);

        // Send the eth fee to the bridgeFeeCollector
        if (bridgeFee > 0) {
            bool success = payable(bridgeFeeCollector).send(bridgeFee);
            if (!success) revert TransferFailed();

            emit SweeperBridgeFeeCollected(
                bridgeFeeCollector,
                address(ETH_NATIVE_TOKEN_ADDRESS),
                bridgeFee
            );
        }

        // Remaining amount after bridge fee
        uint256 remainingAmount = msg.value - bridgeFee;

        // Sanity check amount
        if (remainingAmount == 0) {
            revert InvalidZeroInput();
        }

        // Deposit remaining amount to mint xezETH
        return _deposit(ETH_NATIVE_TOKEN_ADDRESS, remainingAmount, _minOut, _deadline);
    }

    /**
     * @notice  Accepts deposit for the user in depositToken and mints xezETH
     * @dev     This funcion allows anyone to call and deposit collateral for xezETH
     *          ezETH will be immediately minted based on the current price
     *          Funds will be held until sweep() is called.
     *          User calling this function should first approve the tokens to be pulled via transferFrom
     * @param   _amountIn  Amount of tokens to deposit
     * @param   _minOut  Minimum number of xezETH to accept to ensure slippage minimums
     * @param   _deadline  latest timestamp to accept this transaction
     * @return  uint256  Amount of xezETH minted to calling account
     */
    function deposit(
        IERC20 _token,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _deadline
    ) external nonReentrant returns (uint256) {
        // Verify the amount is valid
        if (_amountIn == 0) {
            revert InvalidZeroInput();
        }

        // Transfer deposit tokens from user to this contract
        _token.safeTransferFrom(msg.sender, address(this), _amountIn);

        // calculate bridgeFee for deposit amount
        uint256 bridgeFee = getBridgeFeeShare(_amountIn);

        // Send the fee to the bridgeFeeCollector
        if (bridgeFee > 0) {
            _token.safeTransfer(bridgeFeeCollector, bridgeFee);

            emit SweeperBridgeFeeCollected(bridgeFeeCollector, address(_token), bridgeFee);
        }

        // subtract from _amountIn
        _amountIn -= bridgeFee;

        // Get the ETH value of the token
        uint256 tokenEthValue = _getTokenEthValue(_token, _amountIn);
        if (tokenEthValue == 0) {
            revert InvalidZeroOutput();
        }

        // Special Case if the token is WETH... unwrap to ETH
        if (_token == IERC20(address(weth))) {
            // Unwrap WETH to ETH
            weth.withdraw(_amountIn);
        }

        return _deposit(_token, tokenEthValue, _minOut, _deadline);
    }

    /**
     * @notice  Internal function to trade deposit tokens
     * @dev     Deposit Tokens should be available in the contract before calling this function
     * @param   _token  Address of the token to be deposited
     * @param   _tokenEthValue  Amount of value priced in ETH
     * @param   _minOut  Minimum number of xezETH to accept to ensure slippage minimums
     * @param   _deadline  latest timestamp to accept this transaction
     * @return  uint256  Amount of xezETH minted to calling account
     */
    function _deposit(
        IERC20 _token,
        uint256 _tokenEthValue,
        uint256 _minOut,
        uint256 _deadline
    ) internal returns (uint256) {
        // Verify the token is supported
        if (!depositTokenSupported[_token]) {
            revert InvalidTokenReceived();
        }

        // Discount the value based on the time it takes to be sent across the bridge
        uint256 timeBasedDiscount = _getTokenTimeBasedDiscount(_token, _tokenEthValue);
        _tokenEthValue -= timeBasedDiscount;

        // Fetch price and timestamp of ezETH from the configured price feed
        (uint256 lastPrice, uint256 lastPriceTimestamp) = getMintRate();

        // Verify the price is not stale
        if (block.timestamp > lastPriceTimestamp + 1 days) {
            revert OraclePriceExpired();
        }

        // Calculate the amount of xezETH to mint - assumes 18 decimals for price and token
        uint256 xezETHAmount = (1e18 * _tokenEthValue) / lastPrice;

        // Check that the user will get the minimum amount of xezETH
        if (xezETHAmount < _minOut) {
            revert InsufficientOutputAmount();
        }

        // Verify the deadline has not passed
        if (block.timestamp > _deadline) {
            revert InvalidTimestamp(_deadline);
        }

        // Mint xezETH to the user
        IXERC20(address(xezETH)).mint(msg.sender, xezETHAmount);

        // Emit the event and return amount minted
        emit Deposit(msg.sender, _tokenEthValue, xezETHAmount);
        return xezETHAmount;
    }

    /**
     * @notice  Gets the ETH value of the deposit token
     * @dev     Assumes oracle price is in ETH and is 18 decimals
     * @return  uint256  ETH Value
     */
    function _getTokenEthValue(IERC20 _token, uint256 _amount) internal view returns (uint256) {
        AggregatorV3Interface oracle = tokenOracleLookup[_token];
        if (address(oracle) == address(0x0)) revert OracleNotFound();

        (, int256 price, , uint256 timestamp, ) = oracle.latestRoundData();
        if (block.timestamp > timestamp + 1 days) revert OraclePriceExpired();
        if (price <= 0) revert InvalidOraclePrice();

        // Calculate the value of the token in ETH - assumes both token and price are 18 decimals
        return (_amount * uint256(price)) / 1e18;
    }

    /**
     * @notice Function returns bridge fee share for deposit
     * @param _amountIn deposit amount in terms of ETH
     */
    function getBridgeFeeShare(uint256 _amountIn) public view returns (uint256) {
        // deduct bridge Fee share
        if (_amountIn < sweepBatchSize) {
            return (_amountIn * bridgeFeeShare) / FEE_BASIS;
        } else {
            return (sweepBatchSize * bridgeFeeShare) / FEE_BASIS;
        }
    }

    /**
     * @notice  Gets the time based discount for the token amount
     * @dev     If the token takes 7 days to get across the bridge, the value will not be earning yield for 7 days so it must be discounted.
     *          The discount should include any staking and restaking yields that the token would have earned.
     * @param   _token  address of the token
     * @param   _tokenEthValue  ETH value of the token
     * @return  uint256  amount to be discounted by
     */
    function _getTokenTimeBasedDiscount(
        IERC20 _token,
        uint256 _tokenEthValue
    ) internal view returns (uint256) {
        // Calculate the time based discount
        return (tokenTimeDiscountBasisPoints[_token] * _tokenEthValue) / FEE_BASIS;
    }

    /**
     * @notice Fetch the price of ezETH from configured price feeds
     */
    function getMintRate() public view returns (uint256, uint256) {
        // revert if PriceFeedNotAvailable
        if (receiver == address(0)) revert PriceFeedNotAvailable();
        return (lastPrice, lastPriceTimestamp);
    }

    /**
     * @notice  Updates the price feed
     * @dev     This function will receive the price feed and timestamp from the L1 through CCIPReceiver middleware contract.
     *          It should verify the origin of the call and only allow permissioned source to call.
     * @param   _price The price of ezETH sent via L1.
     * @param   _timestamp The timestamp at which L1 sent the price.
     */
    function updatePrice(uint256 _price, uint256 _timestamp) external override {
        if (msg.sender != receiver) revert InvalidSender(receiver, msg.sender);
        _updatePrice(_price, _timestamp);
    }

    /**
     * @notice  Updates the price feed from the Owner account
     * @dev     Sets the last price and timestamp
     * @param   price  price of ezETH to ETH - 18 decimal precision
     */
    function updatePriceByOwner(uint256 price) external onlyOwner {
        return _updatePrice(price, block.timestamp);
    }

    /**
     * @notice  Internal function to update price
     * @dev     Sanity checks input values and updates prices
     * @param   _price  Current price of ezETH to ETH - 18 decimal precision
     * @param   _timestamp  The timestamp of the price update
     */
    function _updatePrice(uint256 _price, uint256 _timestamp) internal {
        _beforeUpdatePrice(_price, _timestamp);

        // Update values and emit event
        lastPrice = _price;
        lastPriceTimestamp = _timestamp;

        emit PriceUpdated(_price, _timestamp);
    }

    function _beforeUpdatePrice(uint256 _price, uint256 _timestamp) internal view {
        // Check for 0
        if (_price == 0) {
            revert InvalidZeroInput();
        }

        // check for undercollateralized price - < 1
        if (_price < 1 ether) {
            revert InvalidOraclePrice();
        }

        // Check for price divergence - more than 1%
        if (
            (_price > lastPrice && (_price - lastPrice) > (lastPrice / 100)) ||
            (_price < lastPrice && (lastPrice - _price) > (lastPrice / 100))
        ) {
            revert InvalidOraclePrice();
        }

        // Do not allow older price timestamps
        if (_timestamp <= lastPriceTimestamp) {
            revert InvalidTimestamp(_timestamp);
        }

        // Do not allow future timestamps
        if (_timestamp > block.timestamp) {
            revert InvalidTimestamp(_timestamp);
        }
    }

    /**
     * @notice  This function will take the balance of an asset in the contract and bridge it down to the L1
     * @dev     The L1 contract will unwrap, deposit in Renzo, and lock up the ezETH in the lockbox on L1
     *          The caller will estimate and pay the gas for the bridge call
     * @param   _token  Address of token to be swept to L1
     */
    function sweep(IERC20 _token) public payable nonReentrant {
        // Verify it is a supported token
        if (!depositTokenSupported[_token]) {
            revert InvalidTokenReceived();
        }

        // Get the balance of the asset in the contract
        uint256 balance = _token.balanceOf(address(this));

        // If there is not enough to bridge balance, revert
        if (balance <= MIN_DUST_BRIDGE) {
            revert InsufficientOutputAmount();
        }

        // Approve the token and route it to mainnet
        _token.safeIncreaseAllowance(address(valueTransferBridges[_token]), balance);

        // Include the msg.value to pay any bridge fees
        valueTransferBridges[_token].transferRemote{ value: msg.value }(
            mainnetDestinationDomain,
            mainnetRecipient,
            address(_token),
            balance
        );

        // Emit the event
        emit BridgeSwept(address(_token), balance, msg.sender);
    }

    /**
     * @notice  This function will take the balance ETH in the contract and bridge it down to the L1
     * @dev     The L1 contract will deposit in Renzo, and lock up the ezETH in the lockbox on L1
     *          The caller will estimate and pay the gas for the bridge call
     */
    function sweepETH() public payable nonReentrant {
        // Verify Native ETH is supported
        if (!depositTokenSupported[ETH_NATIVE_TOKEN_ADDRESS]) {
            revert InvalidTokenReceived();
        }

        // Get the balance of ETH in the contract minus the gas value
        uint256 valueToSend = address(this).balance - msg.value;

        // If there is not enough to bridge balance, revert
        if (valueToSend <= MIN_DUST_BRIDGE) {
            revert InsufficientOutputAmount();
        }

        // Send the full ETH available but specify the amount that should be bridged
        valueTransferBridges[ETH_NATIVE_TOKEN_ADDRESS].transferRemote{
            value: address(this).balance
        }(
            mainnetDestinationDomain,
            mainnetRecipient,
            address(ETH_NATIVE_TOKEN_ADDRESS),
            valueToSend
        );

        // Emit the event
        emit BridgeSwept(address(ETH_NATIVE_TOKEN_ADDRESS), valueToSend, msg.sender);
    }

    /**
     * @notice  Exposes the price via getRate()
     * @dev     This is required for a balancer pool to get the price of ezETH
     * @return  uint256  .
     */
    function getRate() external view override returns (uint256) {
        (uint256 _lastPrice, uint256 _lastPriceTimestamp) = getMintRate();
        if (block.timestamp > _lastPriceTimestamp + 1 days) {
            revert OraclePriceExpired();
        }
        return _lastPrice;
    }

    /**
     * @notice   Allows the owner to set the support for a deposit asset
     * @dev     Checks the token for 0 anb verifies the oracle is set properly if adding support
     * @param   _token  EC20 token
     * @param   _supported  Indicates if the token is supported for a deposit asset
     * @param   _tokenOracle  If supported, the oracle for the token to get pricing in ETH
     * @param   _valueTransferBridge  Middleware contract used to transfer asset through configured bridge
     */
    function setSupportedToken(
        IERC20 _token,
        bool _supported,
        AggregatorV3Interface _tokenOracle,
        IValueTransferBridge _valueTransferBridge
    ) external onlyOwner {
        // Verify the token is not 0
        if (address(_token) == address(0)) revert InvalidZeroInput();

        // Verify the token is 18 decimals if it is not ETH
        if (
            address(_token) != address(ETH_NATIVE_TOKEN_ADDRESS) &&
            IERC20MetadataUpgradeable(address(_token)).decimals() != 18
        ) revert InvalidTokenDecimals(18, IERC20MetadataUpgradeable(address(_token)).decimals());

        // Update support value
        depositTokenSupported[_token] = _supported;

        // If support is being added, verify the oracle
        if (_supported) {
            if (address(_tokenOracle) == address(0)) revert InvalidZeroInput();

            // Verify that the pricing of the oracle is to 18 decimals - pricing calculations will be off otherwise
            if (_tokenOracle.decimals() != 18)
                revert InvalidTokenDecimals(18, _tokenOracle.decimals());

            // Set the oracle lookup
            tokenOracleLookup[_token] = _tokenOracle;

            if (address(_valueTransferBridge) == address(0)) {
                revert InvalidZeroInput();
            }

            // Set the value transfer bridge
            valueTransferBridges[_token] = _valueTransferBridge;
        } else {
            // If not supported, set the oracle to 0
            tokenOracleLookup[_token] = AggregatorV3Interface(address(0));

            // If not supported, set the value transfer bridge to 0
            valueTransferBridges[_token] = IValueTransferBridge(address(0));
        }

        // Emit the event
        emit TokenSupportUpdated(
            address(_token),
            _supported,
            address(_tokenOracle),
            address(_valueTransferBridge)
        );
    }

    /**
     * @notice  Sweeps accidental ETH value sent to the contract
     * @dev     Restricted to be called by the Owner only.
     * @param   _amount  amount of native asset
     * @param   _to  destination address
     */
    function recoverNative(uint256 _amount, address _to) external onlyOwner {
        payable(_to).transfer(_amount);
    }

    /**
     * @notice  Sweeps accidental ERC20 value sent to the contract
     * @dev     Restricted to be called by the Owner only.
     * @param   _token  address of the ERC20 token
     * @param   _amount  amount of ERC20 token
     * @param   _to  destination address
     */
    function recoverERC20(address _token, uint256 _amount, address _to) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /******************************
     *  Admin/OnlyOwner functions
     *****************************/

    /**
     * @notice This function sets/updates the Receiver Price Feed Middleware for ezETH
     * @dev This should be permissioned call (onlyOnwer), can be set to address(0) for not configured
     * @param _receiver Receiver address
     */
    function setReceiverPriceFeed(address _receiver) external onlyOwner {
        emit ReceiverPriceFeedUpdated(_receiver, receiver);
        receiver = _receiver;
    }

    /**
     * @notice This function updates the BridgeFeeShare for depositors (must be <= 1% i.e. 100 bps)
     * @dev This should be a permissioned call (onlyOnwer)
     * @param _newShare new Bridge fee share in basis points where 100 basis points = 1%
     */
    function updateBridgeFeeShare(uint256 _newShare) external onlyOwner {
        if (_newShare > 100) revert InvalidBridgeFeeShare(_newShare);
        emit BridgeFeeShareUpdated(bridgeFeeShare, _newShare);
        bridgeFeeShare = _newShare;
    }

    /**
     * @notice This function updates the Sweep Batch Size (must be >= 32 ETH)
     * @dev This should be a permissioned call (onlyOwner)
     * @param _newBatchSize new batch size for sweeping
     */
    function updateSweepBatchSize(uint256 _newBatchSize) external onlyOwner {
        if (_newBatchSize < 32 ether) revert InvalidSweepBatchSize(_newBatchSize);
        emit SweepBatchSizeUpdated(sweepBatchSize, _newBatchSize);
        sweepBatchSize = _newBatchSize;
    }

    /**
     * @notice  Updates the time based discount bps per token
     * @dev     This should be a permissioned call (onlyOwner)
     * @param   _token  address of the token
     * @param   _discount  time based discount in basis points where 100 basis points = 1%
     */
    function updateTokenTimeDiscount(IERC20 _token, uint256 _discount) external onlyOwner {
        // Verify the token is supported
        if (!depositTokenSupported[_token]) {
            revert InvalidTokenReceived();
        }

        // The discount should not be greater than 1%
        if (_discount > 100) revert OverMaxBasisPoints();

        // Get the discount currently set
        uint256 oldDiscount = tokenTimeDiscountBasisPoints[_token];

        // Update the discount and emit event
        tokenTimeDiscountBasisPoints[_token] = _discount;
        emit TokenTimeDiscountUpdated(address(_token), oldDiscount, _discount);
    }

    /**
     * @notice Fallback function to handle ETH sent to the contract from unwrapping WETH
     * @dev Warning: users should not send ETH directly to this contract!
     */
    receive() external payable {}
}
