// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./xRenzoBridgeStorage.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../../Errors/Errors.sol";
import {
    IERC20MetadataUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "../Connext/core/IXReceiver.sol";
import "../Connext/core/IWeth.sol";
import "../xERC20/interfaces/IXERC20.sol";
import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract xRenzoBridge is
    IXReceiver,
    Initializable,
    ReentrancyGuardUpgradeable,
    xRenzoBridgeStorageV1
{
    using SafeERC20 for IERC20;

    /// @dev Event emitted when bridge triggers ezETH mint
    event EzETHMinted(
        bytes32 transferId,
        uint256 amountDeposited,
        uint32 origin,
        address originSender,
        uint256 ezETHMinted
    );

    /// @dev Event emitted when a message is sent to another chain.
    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        uint256 exchangeRate, // The exchange rate sent.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the CCIP message.
    );

    event ConnextMessageSent(
        uint32 indexed destinationChainDomain, // The chain domain Id of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        uint256 exchangeRate, // The exchange rate sent.
        uint256 fees // The fees paid for sending the Connext message.
    );

    modifier onlyBridgeAdmin() {
        if (!roleManager.isBridgeAdmin(msg.sender)) revert NotBridgeAdmin();
        _;
    }

    modifier onlyPriceFeedSender() {
        if (!roleManager.isPriceFeedSender(msg.sender)) revert NotPriceFeedSender();
        _;
    }

    /// @dev - This contract expects all tokens to have 18 decimals for pricing
    uint8 public constant EXPECTED_DECIMALS = 18;

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract with initial vars
    function initialize(
        IERC20 _ezETH,
        IERC20 _xezETH,
        IRestakeManager _restakeManager,
        IERC20 _wETH,
        IXERC20Lockbox _xezETHLockbox,
        IConnext _connext,
        IRouterClient _linkRouterClient,
        IRateProvider _rateProvider,
        LinkTokenInterface _linkToken,
        IRoleManager _roleManager
    ) public initializer {
        // Verify non-zero addresses on inputs
        if (
            address(_ezETH) == address(0) ||
            address(_xezETH) == address(0) ||
            address(_restakeManager) == address(0) ||
            address(_wETH) == address(0) ||
            address(_xezETHLockbox) == address(0) ||
            address(_connext) == address(0) ||
            address(_linkRouterClient) == address(0) ||
            address(_rateProvider) == address(0) ||
            address(_linkToken) == address(0) ||
            address(_roleManager) == address(0)
        ) {
            revert InvalidZeroInput();
        }

        // Verify all tokens have 18 decimals
        uint8 decimals = IERC20MetadataUpgradeable(address(_ezETH)).decimals();
        if (decimals != EXPECTED_DECIMALS) {
            revert InvalidTokenDecimals(EXPECTED_DECIMALS, decimals);
        }
        decimals = IERC20MetadataUpgradeable(address(_xezETH)).decimals();
        if (decimals != EXPECTED_DECIMALS) {
            revert InvalidTokenDecimals(EXPECTED_DECIMALS, decimals);
        }
        decimals = IERC20MetadataUpgradeable(address(_wETH)).decimals();
        if (decimals != EXPECTED_DECIMALS) {
            revert InvalidTokenDecimals(EXPECTED_DECIMALS, decimals);
        }
        decimals = IERC20MetadataUpgradeable(address(_linkToken)).decimals();
        if (decimals != EXPECTED_DECIMALS) {
            revert InvalidTokenDecimals(EXPECTED_DECIMALS, decimals);
        }

        // Save off inputs
        ezETH = _ezETH;
        xezETH = _xezETH;
        restakeManager = _restakeManager;
        wETH = _wETH;
        xezETHLockbox = _xezETHLockbox;
        connext = _connext;
        linkRouterClient = _linkRouterClient;
        rateProvider = _rateProvider;
        linkToken = _linkToken;
        roleManager = _roleManager;
    }

    /**
     * @notice  Accepts collateral from the bridge
     * @dev     This function will take all collateral and deposit it into Renzo
     *          The ezETH from the deposit will be sent to the lockbox to be wrapped into xezETH
     *          The xezETH will be burned so that the xezETH on the L2 can be unwrapped for ezETH later
     * @notice  WARNING: This function does NOT whitelist who can send funds from the L2 via Connext.  Users should NOT
     *          send funds directly to this contract.  A user who sends funds directly to this contract will cause
     *          the tokens on the L2 to become over collateralized and will be a "donation" to protocol.  Only use
     *          the deposit contracts on the L2 to send funds to this contract.
     */
    function xReceive(
        bytes32 _transferId,
        uint256 _amount,
        address _asset,
        address _originSender,
        uint32 _origin,
        bytes memory
    ) external nonReentrant returns (bytes memory) {
        // Only allow incoming messages from the Connext contract
        if (msg.sender != address(connext)) {
            revert InvalidSender(address(connext), msg.sender);
        }

        // Check that the token received is wETH
        if (_asset != address(wETH)) {
            revert InvalidTokenReceived();
        }

        // Check that the amount sent is greater than 0
        if (_amount == 0) {
            revert InvalidZeroInput();
        }

        // Get the balance of ETH before the withdraw
        uint256 ethBalanceBeforeWithdraw = address(this).balance;

        // Unwrap the WETH
        IWeth(address(wETH)).withdraw(_amount);

        // Get the amount of ETH
        uint256 ethAmount = address(this).balance - ethBalanceBeforeWithdraw;

        // Get the amonut of ezETH before the deposit
        uint256 ezETHBalanceBeforeDeposit = ezETH.balanceOf(address(this));

        // Deposit it into Renzo RestakeManager
        restakeManager.depositETH{ value: ethAmount }();

        // Get the amount of ezETH that was minted
        uint256 ezETHAmount = ezETH.balanceOf(address(this)) - ezETHBalanceBeforeDeposit;

        // Approve the lockbox to spend the ezETH
        ezETH.safeApprove(address(xezETHLockbox), ezETHAmount);

        // Get the xezETH balance before the deposit
        uint256 xezETHBalanceBeforeDeposit = xezETH.balanceOf(address(this));

        // Send to the lockbox to be wrapped into xezETH
        xezETHLockbox.deposit(ezETHAmount);

        // Get the amount of xezETH that was minted
        uint256 xezETHAmount = xezETH.balanceOf(address(this)) - xezETHBalanceBeforeDeposit;

        // Burn it - it was already minted on the L2
        IXERC20(address(xezETH)).burn(address(this), xezETHAmount);

        // Emit the event
        emit EzETHMinted(_transferId, _amount, _origin, _originSender, ezETHAmount);

        // Return 0 for success
        bytes memory returnData = new bytes(0);
        return returnData;
    }

    /**
     * @notice  Send the price feed to the L1
     * @dev     Calls the getRate() function to get the current ezETH to ETH price and sends to the L2.
     *          This should be a permissioned call for only PRICE_FEED_SENDER role
     * @param _destinationParam array of CCIP destination chain param
     * @param _connextDestinationParam array of connext destination chain param
     */
    function sendPrice(
        CCIPDestinationParam[] calldata _destinationParam,
        ConnextDestinationParam[] calldata _connextDestinationParam
    ) external payable onlyPriceFeedSender nonReentrant {
        // call getRate() to get the current price of ezETH
        uint256 exchangeRate = rateProvider.getRate();
        bytes memory _callData = abi.encode(exchangeRate, block.timestamp);
        // send price feed to renzo CCIP receivers
        for (uint256 i = 0; i < _destinationParam.length; ) {
            Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
                receiver: abi.encode(_destinationParam[i]._renzoReceiver), // ABI-encoded xRenzoDepsot contract address
                data: _callData, // ABI-encoded ezETH exchange rate with Timestamp
                tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
                extraArgs: Client._argsToBytes(
                    // Additional arguments, setting gas limit
                    Client.EVMExtraArgsV1({ gasLimit: 200_000 })
                ),
                // Set the feeToken  address, indicating LINK will be used for fees
                feeToken: address(linkToken)
            });

            // Get the fee required to send the message
            uint256 fees = linkRouterClient.getFee(
                _destinationParam[i].destinationChainSelector,
                evm2AnyMessage
            );

            if (fees > linkToken.balanceOf(address(this)))
                revert NotEnoughBalance(linkToken.balanceOf(address(this)), fees);

            // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
            linkToken.approve(address(linkRouterClient), fees);

            // Send the message through the router and store the returned message ID
            bytes32 messageId = linkRouterClient.ccipSend(
                _destinationParam[i].destinationChainSelector,
                evm2AnyMessage
            );

            // Emit an event with message details
            emit MessageSent(
                messageId,
                _destinationParam[i].destinationChainSelector,
                _destinationParam[i]._renzoReceiver,
                exchangeRate,
                address(linkToken),
                fees
            );
            unchecked {
                ++i;
            }
        }

        // send price feed to renzo connext receiver
        for (uint256 i = 0; i < _connextDestinationParam.length; ) {
            connext.xcall{ value: _connextDestinationParam[i].relayerFee }(
                _connextDestinationParam[i].destinationDomainId,
                _connextDestinationParam[i]._renzoReceiver,
                address(0),
                msg.sender,
                0,
                0,
                _callData
            );

            emit ConnextMessageSent(
                _connextDestinationParam[i].destinationDomainId,
                _connextDestinationParam[i]._renzoReceiver,
                exchangeRate,
                _connextDestinationParam[i].relayerFee
            );

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice  Sweeps accidental ETH value sent to the contract
     * @dev     Restricted to be called by the bridge admin only.
     * @param   _amount  amount of native asset
     * @param   _to  destination address
     */
    function recoverNative(uint256 _amount, address _to) external onlyBridgeAdmin {
        payable(_to).transfer(_amount);
    }

    /**
     * @notice  Sweeps accidental ERC20 value sent to the contract
     * @dev     Restricted to be called by the bridge admin only.
     * @param   _token  address of the ERC20 token
     * @param   _amount  amount of ERC20 token
     * @param   _to  destination address
     */
    function recoverERC20(address _token, uint256 _amount, address _to) external onlyBridgeAdmin {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /**
     * @notice Fallback function to handle ETH sent to the contract from unwrapping WETH
     * @dev Warning: users should not send ETH directly to this contract!
     */
    receive() external payable {}
}
