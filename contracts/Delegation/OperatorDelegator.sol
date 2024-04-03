// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../Permissions/IRoleManager.sol";
import "./OperatorDelegatorStorage.sol";
import "../EigenLayer/interfaces/IDelegationManager.sol";
import "../Errors/Errors.sol";

/// @dev This contract will be responsible for interacting with Eigenlayer
/// Each of these contracts deployed will be delegated to one specific operator
/// This contract can handle multiple ERC20 tokens, all of which will be delegated to the same operator
/// Each supported ERC20 token will be pointed at a single Strategy contract in EL
/// Only the RestakeManager should be interacting with this contract for EL interactions.
contract OperatorDelegator is
    Initializable,
    ReentrancyGuardUpgradeable,
    OperatorDelegatorStorageV2
{
    using SafeERC20 for IERC20;

    uint256 internal constant GWEI_TO_WEI = 1e9;

    event TokenStrategyUpdated(IERC20 token, IStrategy strategy);
    event DelegationAddressUpdated(address delegateAddress);
    event RewardsForwarded(address rewardDestination, uint256 amount);

    event WithdrawStarted(
        bytes32 withdrawRoot,
        address staker,
        address delegatedTo,
        address withdrawer,
        uint nonce,
        uint startBlock,
        IStrategy[] strategies,
        uint256[] shares
    );

    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyOperatorDelegatorAdmin() {
        if (!roleManager.isOperatorDelegatorAdmin(msg.sender)) revert NotOperatorDelegatorAdmin();
        _;
    }

    /// @dev Allows only the RestakeManager address to call functions
    modifier onlyRestakeManager() {
        if (msg.sender != address(restakeManager)) revert NotRestakeManager();
        _;
    }

    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyNativeEthRestakeAdmin() {
        if (!roleManager.isNativeEthRestakeAdmin(msg.sender)) revert NotNativeEthRestakeAdmin();
        _;
    }

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract with initial vars
    function initialize(
        IRoleManager _roleManager,
        IStrategyManager _strategyManager,
        IRestakeManager _restakeManager,
        IDelegationManager _delegationManager,
        IEigenPodManager _eigenPodManager
    ) external initializer {
        if (address(_roleManager) == address(0x0)) revert InvalidZeroInput();
        if (address(_strategyManager) == address(0x0)) revert InvalidZeroInput();
        if (address(_restakeManager) == address(0x0)) revert InvalidZeroInput();
        if (address(_delegationManager) == address(0x0)) revert InvalidZeroInput();
        if (address(_eigenPodManager) == address(0x0)) revert InvalidZeroInput();

        __ReentrancyGuard_init();

        roleManager = _roleManager;
        strategyManager = _strategyManager;
        restakeManager = _restakeManager;
        delegationManager = _delegationManager;
        eigenPodManager = _eigenPodManager;

        // Deploy new EigenPod
        eigenPodManager.createPod();

        // Save off the EigenPod address
        eigenPod = IEigenPod(eigenPodManager.ownerToPod(address(this)));
    }

    /// @dev Sets the strategy for a given token - setting strategy to 0x0 removes the ability to deposit and withdraw token
    function setTokenStrategy(
        IERC20 _token,
        IStrategy _strategy
    ) external nonReentrant onlyOperatorDelegatorAdmin {
        if (address(_token) == address(0x0)) revert InvalidZeroInput();

        tokenStrategyMapping[_token] = _strategy;
        emit TokenStrategyUpdated(_token, _strategy);
    }

    /// @dev Sets the address to delegate tokens to in EigenLayer -- THIS CAN ONLY BE SET ONCE
    function setDelegateAddress(
        address _delegateAddress
    ) external nonReentrant onlyOperatorDelegatorAdmin {
        if (address(_delegateAddress) == address(0x0)) revert InvalidZeroInput();
        if (address(delegateAddress) != address(0x0)) revert DelegateAddressAlreadySet();

        delegateAddress = _delegateAddress;

        delegationManager.delegateTo(delegateAddress);

        emit DelegationAddressUpdated(_delegateAddress);
    }

    /// @dev Deposit tokens into the EigenLayer.  This call assumes any balance of tokens in this contract will be delegated
    /// so do not directly send tokens here or they will be delegated and attributed to the next caller.
    /// @return shares The amount of new shares in the `strategy` created as part of the action.
    function deposit(
        IERC20 _token,
        uint256 _tokenAmount
    ) external nonReentrant onlyRestakeManager returns (uint256 shares) {
        if (address(tokenStrategyMapping[_token]) == address(0x0)) revert InvalidZeroInput();
        if (_tokenAmount == 0) revert InvalidZeroInput();

        // Move the tokens into this contract
        _token.safeTransferFrom(msg.sender, address(this), _tokenAmount);

        // Approve the strategy manager to spend the tokens
        _token.safeApprove(address(strategyManager), _tokenAmount);

        // Deposit the tokens via the strategy manager
        return
            strategyManager.depositIntoStrategy(tokenStrategyMapping[_token], _token, _tokenAmount);
    }

    /// @dev Gets the index of the specific strategy in EigenLayer in the staker's strategy list
    function getStrategyIndex(IStrategy _strategy) public view returns (uint256) {
        // Get the length of the strategy list for this contract
        uint256 strategyLength = strategyManager.stakerStrategyListLength(address(this));

        for (uint256 i = 0; i < strategyLength; i++) {
            if (strategyManager.stakerStrategyList(address(this), i) == _strategy) {
                return i;
            }
        }

        // Not found
        revert NotFound();
    }

    /// @dev Starts a withdrawal of a specific token from the EigenLayer.
    /// @param _token The token to withdraw from the EigenLayer.
    /// @param _tokenAmount The amount of tokens to withdraw.
    function startWithdrawal(
        IERC20 _token,
        uint256 _tokenAmount
    ) external nonReentrant onlyRestakeManager returns (bytes32) {
        if (address(tokenStrategyMapping[_token]) == address(0x0)) revert InvalidZeroInput();

        // Save the nonce before starting the withdrawal
        uint96 nonce = uint96(strategyManager.numWithdrawalsQueued(address(this)));

        // Need to get the index for the strategy - this is not ideal since docs say only to put into list ones that we are withdrawing 100% from
        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = getStrategyIndex(tokenStrategyMapping[_token]);

        // Convert the number of tokens to shares - TODO: Understand if the view function is the proper one to call
        uint256 sharesToWithdraw = tokenStrategyMapping[_token].underlyingToSharesView(
            _tokenAmount
        );

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = tokenStrategyMapping[_token];

        uint256[] memory amountsToWithdraw = new uint256[](1);
        amountsToWithdraw[0] = sharesToWithdraw;

        bytes32 withdrawalRoot = strategyManager.queueWithdrawal(
            strategyIndexes,
            strategiesToWithdraw,
            amountsToWithdraw,
            address(this), // Only allow this contract to complete the withdraw
            false // Do not undeledgate if the balance goes to 0
        );

        // Emit the withdrawal started event
        emit WithdrawStarted(
            withdrawalRoot,
            address(this),
            delegateAddress,
            address(this),
            nonce,
            block.number,
            strategiesToWithdraw,
            amountsToWithdraw
        );

        return withdrawalRoot;
    }

    /// @dev Completes a withdrawal of a specific token from the EigenLayer.
    /// The tokens withdrawn will be sent directly to the specified address
    function completeWithdrawal(
        IStrategyManager.QueuedWithdrawal calldata _withdrawal,
        IERC20 _token,
        uint256 _middlewareTimesIndex,
        address _sendToAddress
    ) external nonReentrant onlyRestakeManager {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = _token;

        strategyManager.completeQueuedWithdrawal(
            _withdrawal,
            tokens,
            _middlewareTimesIndex,
            true // Always get tokens and not share transfers
        );

        // Send tokens to the specified address
        // TODO: do not user balance of
        _token.safeTransfer(_sendToAddress, _token.balanceOf(address(this)));
    }

    /// @dev Gets the underlying token amount from the amount of shares
    function getTokenBalanceFromStrategy(IERC20 token) external view returns (uint256) {
        return tokenStrategyMapping[token].userUnderlyingView(address(this));
    }

    /// @dev Gets the amount of ETH staked in the EigenLayer
    function getStakedETHBalance() external view returns (uint256) {
        // TODO: Once withdrawals are enabled, allow this to handle pending withdraws and a potential negative share balance in the EigenPodManager ownershares
        // TODO: Once upgraded to M2, add back in staked verified ETH, e.g. + uint256(strategyManager.stakerStrategyShares(address(this), strategyManager.beaconChainETHStrategy()))
        // TODO: once M2 is released, there is a possibility someone could call Verify() to try and mess up the TVL calcs (we would double count the stakedButNotVerifiedEth + actual verified ETH in the EigenPod)
        //       - we should track the validator node's verified status to ensure this doesn't happen
        return
            stakedButNotVerifiedEth +
            address(eigenPod).balance +
            pendingUnstakedDelayedWithdrawalAmount;
    }

    /// @dev Stake ETH in the EigenLayer
    /// Only the Restake Manager should call this function
    function stakeEth(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable onlyRestakeManager {
        // Call the stake function in the EigenPodManager
        eigenPodManager.stake{ value: msg.value }(pubkey, signature, depositDataRoot);

        // Increment the staked but not verified ETH
        stakedButNotVerifiedEth += msg.value;
    }

    /// @dev Verifies the withdrawal credentials for a withdrawal
    /// This will allow the EigenPodManager to verify the withdrawal credentials and credit the OD with shares
    /// Only the native eth restake admin should call this function
    function verifyWithdrawalCredentials(
        uint64 oracleBlockNumber,
        uint40 validatorIndex,
        BeaconChainProofs.ValidatorFieldsAndBalanceProofs memory proofs,
        bytes32[] calldata validatorFields
    ) external onlyNativeEthRestakeAdmin {
        eigenPod.verifyWithdrawalCredentialsAndBalance(
            oracleBlockNumber,
            validatorIndex,
            proofs,
            validatorFields
        );

        // Decrement the staked but not verified ETH
        uint64 validatorCurrentBalanceGwei = BeaconChainProofs.getBalanceFromBalanceRoot(
            validatorIndex,
            proofs.balanceRoot
        );
        stakedButNotVerifiedEth -= (validatorCurrentBalanceGwei * GWEI_TO_WEI);
    }

    /**
     * @notice  Starts a delayed withdraw of the ETH from the EigenPodManager
     * @dev     Before the eigenpod is verified, we can sweep out any accumulated ETH from the Consensus layer validator rewards
     *         We also want to track the amount in the delayed withdrawal router so we can track the TVL and reward amount accurately
     */
    function startDelayedWithdrawUnstakedETH() external onlyNativeEthRestakeAdmin {
        // Get the current balance of the EigenPod
        uint256 beforeEigenPodBalance = address(eigenPod).balance;

        // Call the start delayed withdraw function in the EigenPodManager
        // This will queue up a delayed withdrawal that will be sent back to this address after the timeout
        eigenPod.withdrawBeforeRestaking();

        // Add to the total amount of pending rewards for this delayed withdrawal to the total we are tracking
        pendingUnstakedDelayedWithdrawalAmount += (beforeEigenPodBalance -
            address(eigenPod).balance);
    }

    /**
     * @notice Users should NOT send ETH directly to this contract unless they want to donate to existing ezETH holders.
     *        This is an internal protocol function.
     * @dev Handle ETH sent to this contract - will get forwarded to the deposit queue for restaking as a protocol reward
     */
    receive() external payable nonReentrant {
        // If a payment comes in from the delayed withdrawal router, assume it is from the pending unstaked withdrawal
        // and subtract that amount from the pending amount
        if (msg.sender == address(eigenPod.delayedWithdrawalRouter())) {
            if (msg.value <= pendingUnstakedDelayedWithdrawalAmount) {
                // If it is less than we are tracking, subtract it
                pendingUnstakedDelayedWithdrawalAmount -= msg.value;
            } else {
                // If it is more than we are tracking, set it to 0
                pendingUnstakedDelayedWithdrawalAmount = 0;
            }
        }

        address destination = address(restakeManager.depositQueue());
        (bool success, ) = destination.call{ value: msg.value }("");
        if (!success) revert TransferFailed();

        emit RewardsForwarded(destination, msg.value);
    }
}
