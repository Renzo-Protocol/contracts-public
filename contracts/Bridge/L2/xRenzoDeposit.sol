// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./xRenzoDepositStorage.sol";
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

contract xRenzoDeposit is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IRateProvider,
    xRenzoDepositStorageV3
{
    using SafeERC20 for IERC20;

    /// @dev - This contract expects all tokens to have 18 decimals for pricing
    uint8 public constant EXPECTED_DECIMALS = 18;

    /// @dev - Fee basis point, 100 basis point = 1 %
    uint32 public constant FEE_BASIS = 10000;

    event PriceUpdated(uint256 price, uint256 timestamp);
    event Deposit(address indexed user, uint256 amountIn, uint256 amountOut);
    event BridgeSweeperAddressUpdated(address sweeper, bool allowed);
    event BridgeSwept(
        uint32 destinationDomain,
        address destinationTarget,
        address delegate,
        uint256 amount
    );
    event OraclePriceFeedUpdated(address newOracle, address oldOracle);
    event ReceiverPriceFeedUpdated(address newReceiver, address oldReceiver);
    event SweeperBridgeFeeCollected(address sweeper, uint256 feeCollected);
    event BridgeFeeShareUpdated(uint256 oldBridgeFeeShare, uint256 newBridgeFeeShare);
    event SweepBatchSizeUpdated(uint256 oldSweepBatchSize, uint256 newSweepBatchSize);

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
     * @param   _depositToken  WETH on L2
     * @param   _collateralToken  nextWETH on L2
     * @param   _connext  Connext contract
     * @param   _swapKey  Swap key for the connext contract swap from WETH to nextWETH
     * @param   _receiver Renzo Receiver middleware contract for price feed
     * @param   _oracle Price feed oracle for ezETH
     */
    function initialize(
        uint256 _currentPrice,
        IERC20 _xezETH,
        IERC20 _depositToken,
        IERC20 _collateralToken,
        IConnext _connext,
        bytes32 _swapKey,
        address _receiver,
        uint32 _bridgeDestinationDomain,
        address _bridgeTargetAddress,
        IRenzoOracleL2 _oracle
    ) public initializer {
        // Initialize inherited classes
        __Ownable_init();

        // Verify valid non zero values
        if (
            _currentPrice == 0 ||
            address(_xezETH) == address(0) ||
            address(_depositToken) == address(0) ||
            address(_collateralToken) == address(0) ||
            address(_connext) == address(0) ||
            _swapKey == 0 ||
            _bridgeDestinationDomain == 0 ||
            _bridgeTargetAddress == address(0)
        ) {
            revert InvalidZeroInput();
        }

        // Verify all tokens have 18 decimals
        uint8 decimals = IERC20MetadataUpgradeable(address(_depositToken)).decimals();
        if (decimals != EXPECTED_DECIMALS) {
            revert InvalidTokenDecimals(EXPECTED_DECIMALS, decimals);
        }
        decimals = IERC20MetadataUpgradeable(address(_collateralToken)).decimals();
        if (decimals != EXPECTED_DECIMALS) {
            revert InvalidTokenDecimals(EXPECTED_DECIMALS, decimals);
        }
        decimals = IERC20MetadataUpgradeable(address(_xezETH)).decimals();
        if (decimals != EXPECTED_DECIMALS) {
            revert InvalidTokenDecimals(EXPECTED_DECIMALS, decimals);
        }

        // Initialize the price and timestamp
        lastPrice = _currentPrice;
        lastPriceTimestamp = block.timestamp;

        // Set xezETH address
        xezETH = _xezETH;

        // Set the depoist token
        depositToken = _depositToken;

        // Set the collateral token
        collateralToken = _collateralToken;

        // Set the connext contract
        connext = _connext;

        // Set the swap key
        swapKey = _swapKey;

        // Set receiver contract address
        receiver = _receiver;
        // Connext router fee is 5 basis points
        bridgeRouterFeeBps = 5;

        // Set the bridge destination domain
        bridgeDestinationDomain = _bridgeDestinationDomain;

        // Set the bridge target address
        bridgeTargetAddress = _bridgeTargetAddress;

        // set oracle Price Feed struct
        oracle = _oracle;

        // set bridge Fee Share 0.05% where 100 basis point = 1%
        bridgeFeeShare = 5;

        //set sweep batch size to 32 ETH
        sweepBatchSize = 32 ether;
    }

    /**
     * @notice  Accepts deposit for the user in the native asset and mints xezETH
     * @dev     This funcion allows anyone to call and deposit the native asset for xezETH
     *          The native asset will be wrapped to WETH (if it is supported)
     *          ezETH will be immediately minted based on the current price
     *          Funds will be held until sweep() is called.
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

        // Get the deposit token balance before
        uint256 depositBalanceBefore = depositToken.balanceOf(address(this));

        // Wrap the deposit ETH to WETH
        IWeth(address(depositToken)).deposit{ value: msg.value }();

        // Get the amount of tokens that were wrapped
        uint256 wrappedAmount = depositToken.balanceOf(address(this)) - depositBalanceBefore;

        // Sanity check for 0
        if (wrappedAmount == 0) {
            revert InvalidZeroOutput();
        }

        return _deposit(wrappedAmount, _minOut, _deadline);
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
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _deadline
    ) external nonReentrant returns (uint256) {
        if (_amountIn == 0) {
            revert InvalidZeroInput();
        }

        // Transfer deposit tokens from user to this contract
        depositToken.safeTransferFrom(msg.sender, address(this), _amountIn);

        return _deposit(_amountIn, _minOut, _deadline);
    }

    /**
     * @notice  Internal function to trade deposit tokens for nextWETH and mint xezETH
     * @dev     Deposit Tokens should be available in the contract before calling this function
     * @param   _amountIn  Amount of tokens deposited
     * @param   _minOut  Minimum number of xezETH to accept to ensure slippage minimums
     * @param   _deadline  latest timestamp to accept this transaction
     * @return  uint256  Amount of xezETH minted to calling account
     */
    function _deposit(
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _deadline
    ) internal returns (uint256) {
        // calculate bridgeFee for deposit amount
        uint256 bridgeFee = getBridgeFeeShare(_amountIn);
        // subtract from _amountIn and add to bridgeFeeCollected
        _amountIn -= bridgeFee;
        bridgeFeeCollected += bridgeFee;

        // Trade deposit tokens for nextWETH
        uint256 amountOut = _trade(_amountIn, _deadline);
        if (amountOut == 0) {
            revert InvalidZeroOutput();
        }

        // Fetch price and timestamp of ezETH from the configured price feed
        (uint256 _lastPrice, uint256 _lastPriceTimestamp) = getMintRate();

        // Verify the price is not stale
        if (block.timestamp > _lastPriceTimestamp + 1 days) {
            revert OraclePriceExpired();
        }

        // Calculate the amount of xezETH to mint - assumes 18 decimals for price and token
        uint256 xezETHAmount = (1e18 * amountOut) / _lastPrice;

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
        emit Deposit(msg.sender, _amountIn, xezETHAmount);
        return xezETHAmount;
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
     * @notice Fetch the price of ezETH from configured price feeds
     */
    function getMintRate() public view returns (uint256, uint256) {
        // revert if PriceFeedNotAvailable
        if (receiver == address(0) && address(oracle) == address(0)) revert PriceFeedNotAvailable();
        if (address(oracle) != address(0)) {
            (uint256 oraclePrice, uint256 oracleTimestamp) = oracle.getMintRate();
            return
                oracleTimestamp > lastPriceTimestamp
                    ? (oraclePrice, oracleTimestamp)
                    : (lastPrice, lastPriceTimestamp);
        } else {
            return (lastPrice, lastPriceTimestamp);
        }
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
        // Check for 0
        if (_price == 0) {
            revert InvalidZeroInput();
        }

        // Check for price divergence - more than 10%
        if (
            (_price > lastPrice && (_price - lastPrice) > (lastPrice / 10)) ||
            (_price < lastPrice && (lastPrice - _price) > (lastPrice / 10))
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

        // Update values and emit event
        lastPrice = _price;
        lastPriceTimestamp = _timestamp;

        emit PriceUpdated(_price, _timestamp);
    }

    /**
     * @notice  Trades deposit asset for nextWETH
     * @dev     Note that min out is not enforced here since the asset will be priced to ezETH by the calling function
     * @param   _amountIn  Amount of deposit tokens to trade for collateral asset
     * @return  _deadline Deadline for the trade to prevent stale requests
     */
    function _trade(uint256 _amountIn, uint256 _deadline) internal returns (uint256) {
        // Approve the deposit asset to the connext contract
        depositToken.safeApprove(address(connext), _amountIn);

        // We will accept any amount of tokens out here... The caller of this function should verify the amount meets minimums
        uint256 minOut = 0;

        // Swap the tokens
        uint256 amountNextWETH = connext.swapExact(
            swapKey,
            _amountIn,
            address(depositToken),
            address(collateralToken),
            minOut,
            _deadline
        );

        // Subtract the bridge router fee
        if (bridgeRouterFeeBps > 0) {
            uint256 fee = (amountNextWETH * bridgeRouterFeeBps) / 10_000;
            amountNextWETH -= fee;
        }

        return amountNextWETH;
    }

    /**
     * @notice This function transfer the bridge fee to sweeper address
     */
    function _recoverBridgeFee() internal {
        uint256 feeCollected = bridgeFeeCollected;
        bridgeFeeCollected = 0;
        // transfer collected fee to bridgeSweeper
        uint256 balanceBefore = address(this).balance;
        IWeth(address(depositToken)).withdraw(feeCollected);
        feeCollected = address(this).balance - balanceBefore;
        (bool success, ) = payable(msg.sender).call{ value: feeCollected }("");
        if (!success) revert TransferFailed();
        emit SweeperBridgeFeeCollected(msg.sender, feeCollected);
    }

    /**
     * @notice  This function will take the balance of nextWETH in the contract and bridge it down to the L1
     * @dev     The L1 contract will unwrap, deposit in Renzo, and lock up the ezETH in the lockbox on L1
     *          This function should only be callable by permissioned accounts
     *          The caller will estimate and pay the gas for the bridge call
     */
    function sweep() public payable nonReentrant {
        // Verify the caller is whitelisted
        if (!allowedBridgeSweepers[msg.sender]) {
            revert UnauthorizedBridgeSweeper();
        }

        // Get the balance of nextWETH in the contract
        uint256 balance = collateralToken.balanceOf(address(this));

        // If there is no balance, return
        if (balance == 0) {
            revert InvalidZeroOutput();
        }

        // Approve it to the connext contract
        collateralToken.safeApprove(address(connext), balance);

        // Need to send some calldata so it triggers xReceive on the target
        bytes memory bridgeCallData = abi.encode(balance);

        connext.xcall{ value: msg.value }(
            bridgeDestinationDomain,
            bridgeTargetAddress,
            address(collateralToken),
            msg.sender,
            balance,
            0, // Asset is already nextWETH, so no slippage will be incurred
            bridgeCallData
        );

        // send collected bridge fee to sweeper
        _recoverBridgeFee();

        // Emit the event
        emit BridgeSwept(bridgeDestinationDomain, bridgeTargetAddress, msg.sender, balance);
    }

    /**
     * @notice  Exposes the price via getRate()
     * @dev     This is required for a balancer pool to get the price of ezETH
     * @return  uint256  .
     */
    function getRate() external view override returns (uint256) {
        return lastPrice;
    }

    /**
     * @notice  Allows the owner to set addresses that are allowed to call the bridge() function
     * @dev     .
     * @param   _sweeper  Address of the proposed sweeping account
     * @param   _allowed  bool to allow or disallow the address
     */
    function setAllowedBridgeSweeper(address _sweeper, bool _allowed) external onlyOwner {
        allowedBridgeSweepers[_sweeper] = _allowed;

        emit BridgeSweeperAddressUpdated(_sweeper, _allowed);
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
     * @notice This function sets/updates the Oracle price Feed middleware for ezETH
     * @dev This should be permissioned call (onlyOwner), can be set to address(0) for not configured
     * @param _oracle Oracle address
     */
    function setOraclePriceFeed(IRenzoOracleL2 _oracle) external onlyOwner {
        emit OraclePriceFeedUpdated(address(_oracle), address(oracle));
        oracle = _oracle;
    }

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
     * @notice Fallback function to handle ETH sent to the contract from unwrapping WETH
     * @dev Warning: users should not send ETH directly to this contract!
     */
    receive() external payable {}
}
