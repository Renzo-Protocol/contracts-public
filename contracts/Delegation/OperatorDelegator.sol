// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../Permissions/IRoleManager.sol";
import "./OperatorDelegatorStorage.sol";
import "../EigenLayer/interfaces/IDelegationManager.sol";
import "../EigenLayer/interfaces/ISignatureUtilsMixin.sol";
import "../EigenLayer/libraries/BeaconChainProofs.sol";
import "../EigenLayer/interfaces/IRewardsCoordinator.sol";
import "../Bridge/Connext/core/IWeth.sol";
import "../Errors/Errors.sol";

import "./utils/OperatorDelegatorLib.sol";

/// @dev This contract will be responsible for interacting with Eigenlayer
/// Each of these contracts deployed will be delegated to one specific operator
/// This contract can handle multiple ERC20 tokens, all of which will be delegated to the same operator
/// Each supported ERC20 token will be pointed at a single Strategy contract in EL
/// Only the RestakeManager should be interacting with this contract for EL interactions.
contract OperatorDelegator is
    Initializable,
    ReentrancyGuardUpgradeable,
    OperatorDelegatorStorageV11
{
    using SafeERC20 for IERC20;
    using BeaconChainProofs for *;

    uint256 internal constant GWEI_TO_WEI = 1e9;

    address public constant IS_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @dev Max stakedButNotVerifiedEth amount cap per validator
    uint256 public constant MAX_STAKE_BUT_NOT_VERIFIED_AMOUNT = 32 ether;

    /// @dev Nominal base gas spent value by admin
    uint256 internal constant NOMINAL_BASE_GAS_SPENT = 50_000;

    /// @dev min redeposit amount in WEI
    uint256 public constant MIN_REDEPOSIT_AMOUNT = 10_000;

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

    event WithdrawCompleted(bytes32 withdrawalRoot, IStrategy[] strategies, uint256[] shares);

    event GasSpent(address admin, uint256 gasSpent);
    event GasRefunded(address admin, uint256 gasRefunded);
    event BaseGasAmountSpentUpdated(uint256 oldBaseGasAmountSpent, uint256 newBaseGasAmountSpent);
    event RewardsCoordinatorUpdated(address oldRewardsCoordinator, address newRewardsCoordinator);
    event RewardsDestinationUpdated(address oldRewardsDestination, address newRewardsDestination);
    event WETHUnwrapperUpdated(address oldUnwrapper, address newUnwrapper);
    event GasRefundAddressUpdated(address oldGasRefundAddress, address newGasRefundAddress);

    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyOperatorDelegatorAdmin() {
        _onlyOperatorDelegatorAdmin();
        _;
    }

    /// @dev Allows only the RestakeManager address to call functions
    modifier onlyRestakeManager() {
        _onlyRestakeManager();
        _;
    }

    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyNativeEthRestakeAdmin() {
        _onlyNativeEthRestakeAdmin();
        _;
    }

    /// @dev Allows only EmergencyWithdrawTrackingAdmin to call functions
    modifier onlyEmergencyWithdrawTrackingAdmin() {
        if (!roleManager.isEmergencyWithdrawTrackingAdmin(msg.sender))
            revert NotEmergencyWithdrawTrackingAdmin();
        _;
    }

    /// @dev Allows only Rewards admin to process Rewards
    modifier onlyEigenLayerRewardsAdmin() {
        if (!roleManager.isEigenLayerRewardsAdmin(msg.sender)) revert NotEigenLayerRewardsAdmin();
        _;
    }

    modifier onlyEmergencyCheckpointTrackingAdmin() {
        if (!roleManager.isEmergencyCheckpointTrackingAdmin(msg.sender))
            revert NotEmergencyCheckpointTrackingAdmin();
        _;
    }

    modifier onlyEmergencyTrackAVSEthSlashingAdmin() {
        if (!roleManager.isEmergencyTrackAVSEthSlashingAdmin(msg.sender))
            revert NotEmergencyTrackAVSEthSlashingAdmin();
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
        _checkZeroAddress(address(_roleManager));
        _checkZeroAddress(address(_strategyManager));
        _checkZeroAddress(address(_restakeManager));
        _checkZeroAddress(address(_delegationManager));
        _checkZeroAddress(address(_eigenPodManager));

        __ReentrancyGuard_init();

        roleManager = _roleManager;
        strategyManager = _strategyManager;
        restakeManager = _restakeManager;
        delegationManager = _delegationManager;
        eigenPodManager = _eigenPodManager;

        // Deploy new EigenPod
        eigenPod = IEigenPod(eigenPodManager.createPod());
    }

    // /**
    //  * @notice  reinitializing the OperatorDelegator to track pre Slashing Upgrade queued shares, reinitialize with version 3
    //  * @dev     permissioned call (onlyOperatorDelegatorAdmin), can only reinitialize once
    //  * @param   _ethQueuedSharesDelta the shares delta for completed ETH withdrawals
    //  * @param   preSlashingQueuedShares the shares for pre slashing queued withdrawals
    //  * @param   preSlashingQueuedSharesToken the token address for pre slashing queued withdrawals
    //  * @param   preSlashingWithdrawalRoots the withdrawal roots for pre slashing queued withdrawals
    //  */
    // function reinitialize(
    //     uint256 _ethQueuedSharesDelta,
    //     uint256[] calldata preSlashingQueuedShares,
    //     address[] calldata preSlashingQueuedSharesToken,
    //     bytes32[] calldata preSlashingWithdrawalRoots
    // ) external onlyOperatorDelegatorAdmin reinitializer(3) {
    //     // reset queued shares delta for completed withdrawals
    //     queuedShares[IS_NATIVE] -= _ethQueuedSharesDelta;

    //     // set initial withdrawable shares for pending queued shares
    //     if (
    //         preSlashingQueuedShares.length != preSlashingQueuedSharesToken.length ||
    //         preSlashingQueuedShares.length != preSlashingWithdrawalRoots.length
    //     ) revert MismatchedArrayLengths();

    //     for (uint256 i = 0; i < preSlashingQueuedShares.length; ) {
    //         queuedWithdrawalTokenInfo[preSlashingWithdrawalRoots[i]][
    //             preSlashingQueuedSharesToken[i]
    //         ].initialWithdrawableShares = preSlashingQueuedShares[i];
    //         unchecked {
    //             ++i;
    //         }
    //     }
    // }

    /// @dev Sets the strategy for a given token - setting strategy to 0x0 removes the ability to deposit and withdraw token
    function setTokenStrategy(
        IERC20 _token,
        IStrategy _strategy
    ) external nonReentrant onlyOperatorDelegatorAdmin {
        _checkZeroAddress(address(_token));

        // check revert if strategy underlying does not match
        if (
            address(_strategy) != address(0x0) &&
            ((_strategy.underlyingToken() != _token) ||
                !strategyManager.strategyIsWhitelistedForDeposit(_strategy))
        ) revert InvalidStrategy();

        // check revert if strategy already set and shares greater than 0
        if (
            address(tokenStrategyMapping[_token]) != address(0x0) &&
            tokenStrategyMapping[_token].userUnderlyingView(address(this)) > 0
        ) revert NonZeroUnderlyingStrategyExist();

        tokenStrategyMapping[_token] = _strategy;
        emit TokenStrategyUpdated(_token, _strategy);
    }

    /// @dev Sets the address to delegate tokens to in EigenLayer -- THIS CAN ONLY BE SET ONCE
    function setDelegateAddress(
        address _delegateAddress,
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external nonReentrant onlyOperatorDelegatorAdmin {
        _checkZeroAddress(address(_delegateAddress));
        if (delegationManager.delegatedTo(address(this)) != address(0))
            revert DelegateAddressAlreadySet();

        delegateAddress = _delegateAddress;

        delegationManager.delegateTo(delegateAddress, approverSignatureAndExpiry, approverSalt);

        emit DelegationAddressUpdated(_delegateAddress);
    }

    /// @dev updates the baseGasAmountSpent
    function setBaseGasAmountSpent(
        uint256 _baseGasAmountSpent
    ) external nonReentrant onlyOperatorDelegatorAdmin {
        if (_baseGasAmountSpent == 0) revert InvalidZeroInput();
        emit BaseGasAmountSpentUpdated(baseGasAmountSpent, _baseGasAmountSpent);
        baseGasAmountSpent = _baseGasAmountSpent;
    }

    /// @dev sets the EigenLayer RewardsCoordinator address
    function setRewardsCoordinator(
        IRewardsCoordinator _rewardsCoordinator
    ) external nonReentrant onlyOperatorDelegatorAdmin {
        _checkZeroAddress(address(_rewardsCoordinator));
        emit RewardsCoordinatorUpdated(address(rewardsCoordinator), address(_rewardsCoordinator));
        rewardsCoordinator = _rewardsCoordinator;
    }

    /// @dev sets the Rewards Destination address
    function setRewardsDestination(
        address _rewardsDestination
    ) external nonReentrant onlyOperatorDelegatorAdmin {
        _checkZeroAddress(_rewardsDestination);
        emit RewardsDestinationUpdated(rewardsDestination, _rewardsDestination);
        rewardsDestination = _rewardsDestination;
    }

    function setGasRefundAddress(
        address _gasRefundAddress
    ) external nonReentrant onlyOperatorDelegatorAdmin {
        _checkZeroAddress(_gasRefundAddress);
        emit GasRefundAddressUpdated(gasRefundAddress, _gasRefundAddress);
        gasRefundAddress = _gasRefundAddress;
    }

    /// @dev Deposit tokens into the EigenLayer.  This call assumes any balance of tokens in this contract will be delegated
    /// so do not directly send tokens here or they will be delegated and attributed to the next caller.
    /// @return shares The amount of new shares in the `strategy` created as part of the action.
    function deposit(
        IERC20 token,
        uint256 tokenAmount
    ) external nonReentrant onlyRestakeManager returns (uint256 shares) {
        _checkZeroAddress(address(tokenStrategyMapping[token]));
        if (tokenAmount == 0) revert InvalidZeroInput();

        // Move the tokens into this contract
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);

        return _deposit(token, tokenAmount);
    }

    /**
     * @notice  Perform necessary checks on input data and deposits into EigenLayer
     * @param   _token  token interface to deposit
     * @param   _tokenAmount  amount of given token to deposit
     * @return  shares  shares for deposited amount
     */
    function _deposit(IERC20 _token, uint256 _tokenAmount) internal returns (uint256 shares) {
        // Approve the strategy manager to spend the tokens
        _token.safeIncreaseAllowance(address(strategyManager), _tokenAmount);

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

    /**
     * @notice  Tracks the pending queued withdrawal shares cause by Operator force undelegating the OperatorDelegator
     * @dev     permissioned call (onlyEmergencyWithdrawTrackingAdmin),
     *          each withdrawal will contain single strategy and respective shares in case of 'ForceUndelegation'.
     *          EigenLayer link - https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/src/contracts/core/DelegationManager.sol#L242
     * @param   withdrawals  Withdrawals struct list needs to be tracked
     * @param   tokens  list of Tokens undelegated by Operator
     */
    function emergencyTrackQueuedWithdrawals(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[] calldata tokens
    ) external nonReentrant onlyEmergencyWithdrawTrackingAdmin {
        OperatorDelegatorLib.trackQueuedWithdrawals(
            withdrawals,
            tokens,
            delegationManager,
            queuedWithdrawal,
            queuedShares,
            queuedWithdrawalTokenInfo
        );
    }

    /**
     * @notice  Starts a withdrawal from specified tokens strategies for given amounts
     * @dev     permissioned call (onlyNativeEthRestakeAdmin)
     * @param   tokens  list of tokens to withdraw from. For ETH -> 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
     * @param   tokenAmounts  list of token amounts i'th index token in tokens
     * @return  withdrawalRoots bytes32[]  withdrawal root for each queued withdrawal
     */
    function queueWithdrawals(
        IERC20[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external nonReentrant onlyNativeEthRestakeAdmin returns (bytes32[] memory withdrawalRoots) {
        // record gas spent
        uint256 gasBefore = gasleft();

        // check if tokens and tokenAmounts length are same
        if (tokens.length != tokenAmounts.length) revert MismatchedArrayLengths();

        uint96 nonce;

        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParam;
        withdrawalRoots = new bytes32[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ) {
            (withdrawalRoots[i], nonce, queuedWithdrawalParam) = OperatorDelegatorLib
                .queueWithdrawal(
                    tokens[i],
                    tokenAmounts[i],
                    delegationManager,
                    eigenPodManager,
                    tokenStrategyMapping,
                    queuedShares,
                    queuedWithdrawal,
                    queuedWithdrawalTokenInfo
                );

            // Emit the withdrawal started event
            emit WithdrawStarted(
                withdrawalRoots[i],
                address(this),
                delegateAddress,
                address(this),
                nonce,
                block.number,
                queuedWithdrawalParam[0].strategies,
                queuedWithdrawalParam[0].depositShares
            );

            unchecked {
                ++i;
            }
        }

        // update the gas spent for RestakeAdmin
        _recordGas(gasBefore, NOMINAL_BASE_GAS_SPENT);

        return withdrawalRoots;
    }

    /**
     * @notice  Complete the specified withdrawal,
     * @dev     permissioned call (onlyNativeEthRestakeAdmin)
     * @param   withdrawal  Withdrawal struct
     * @param   tokens  list of tokens to withdraw
     */
    function completeQueuedWithdrawal(
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] calldata tokens
    ) external nonReentrant onlyNativeEthRestakeAdmin {
        uint256 gasBefore = gasleft();
        if (tokens.length != withdrawal.strategies.length) revert MismatchedArrayLengths();

        // complete the queued withdrawal from EigenLayer with receiveAsToken set to true
        OperatorDelegatorLib.completeQueuedWithdrawal(withdrawal, tokens, delegationManager);

        _reduceQueuedShares(withdrawal, tokens);

        _fillBufferAndReDeposit();

        // emits the Withdraw Completed event with withdrawalRoot
        emit WithdrawCompleted(
            delegationManager.calculateWithdrawalRoot(withdrawal),
            withdrawal.strategies,
            withdrawal.scaledShares
        );
        // record current spent gas
        _recordGas(gasBefore, NOMINAL_BASE_GAS_SPENT);
    }

    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bool[] calldata receiveAsTokens
    ) external nonReentrant onlyNativeEthRestakeAdmin {
        uint256 gasBefore = gasleft();
        if (withdrawals.length != tokens.length || withdrawals.length != receiveAsTokens.length)
            revert MismatchedArrayLengths();

        // complete queued withdrawals
        OperatorDelegatorLib.completeQueuedWithdrawals(
            withdrawals,
            tokens,
            receiveAsTokens,
            delegationManager
        );

        // track queued shares and fill buffer
        for (uint256 i = 0; i < withdrawals.length; ) {
            if (tokens[i].length != withdrawals[i].strategies.length)
                revert MismatchedArrayLengths();

            // revert if receiveAsToken is false
            if (!receiveAsTokens[i]) revert OnlyReceiveAsTokenAllowed();

            // reduce queued shares for every withdrawal
            _reduceQueuedShares(withdrawals[i], tokens[i]);

            // emits the Withdraw Completed event with withdrawalRoot
            emit WithdrawCompleted(
                delegationManager.calculateWithdrawalRoot(withdrawals[i]),
                withdrawals[i].strategies,
                withdrawals[i].scaledShares
            );
            unchecked {
                ++i;
            }
        }

        // fill buffer and redeposit remaining
        _fillBufferAndReDeposit();

        // record current spent gas
        _recordGas(gasBefore, NOMINAL_BASE_GAS_SPENT);
    }

    /// @dev Gets the underlying token amount from the amount of shares + queued withdrawal shares
    function getTokenBalanceFromStrategy(IERC20 token) external view returns (uint256) {
        return
            OperatorDelegatorLib.getTokenBalanceFromStrategy(
                _getQueuedSharesWithSlashing(address(token)),
                delegationManager,
                tokenStrategyMapping[token]
            );
    }

    /// @dev Gets the amount of ETH staked in the EigenLayer
    function getStakedETHBalance() external view returns (uint256) {
        // check if completed checkpoint in not synced with OperatorDelegator
        _checkCheckpointSync();

        return
            OperatorDelegatorLib.getStakedETHBalance(
                _getQueuedSharesWithSlashing(IS_NATIVE),
                stakedButNotVerifiedEth,
                _getPartialWithdrawalsPodDelta(),
                eigenPodManager,
                delegationManager
            );
    }

    /// @dev Stake ETH in the EigenLayer
    /// Only the Restake Manager should call this function
    function stakeEth(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable onlyRestakeManager {
        // if validator withdraw credentials is verified
        if (eigenPod.validatorStatus(pubkey) == IEigenPodTypes.VALIDATOR_STATUS.INACTIVE) {
            bytes32 validatorPubKeyHash = _calculateValidatorPubkeyHash(pubkey);
            uint256 validatorCurrentStakedButNotVerifiedEth = validatorStakedButNotVerifiedEth[
                validatorPubKeyHash
            ];
            uint256 _stakedButNotVerifiedEth = msg.value;
            uint256 _validatorStakedButNotVerifiedEth = validatorCurrentStakedButNotVerifiedEth +
                msg.value;
            // check if new value addition is greater than MAX_STAKE_BUT_NOT_VERIFIED_AMOUNT
            if (
                validatorCurrentStakedButNotVerifiedEth + msg.value >
                MAX_STAKE_BUT_NOT_VERIFIED_AMOUNT
            ) {
                // stakedButNotVerifiedETH per validator max capped to MAX_STAKE_BUT_NOT_VERIFIED_AMOUNT
                _stakedButNotVerifiedEth =
                    MAX_STAKE_BUT_NOT_VERIFIED_AMOUNT -
                    validatorCurrentStakedButNotVerifiedEth;

                // validatorStakedButNotVerifiedEth max cap to MAX_STAKE_BUT_NOT_VERIFIED_AMOUNT per validator
                _validatorStakedButNotVerifiedEth = MAX_STAKE_BUT_NOT_VERIFIED_AMOUNT;
            }
            validatorStakedButNotVerifiedEth[
                validatorPubKeyHash
            ] = _validatorStakedButNotVerifiedEth;
            // Increment the staked but not verified ETH
            stakedButNotVerifiedEth += _stakedButNotVerifiedEth;
        }

        // Call the stake function in the EigenPodManager
        eigenPodManager.stake{ value: msg.value }(pubkey, signature, depositDataRoot);
    }

    /// @dev Verifies the withdrawal credentials for a withdrawal
    /// This will allow the EigenPodManager to verify the withdrawal credentials and credit the OD with shares
    /// Only the native eth restake admin should call this function
    function verifyWithdrawalCredentials(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata withdrawalCredentialProofs,
        bytes32[][] calldata validatorFields
    ) external onlyNativeEthRestakeAdmin {
        uint256 gasBefore = gasleft();

        uint256 totalStakedAndVerifiedETH = OperatorDelegatorLib.verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndices,
            withdrawalCredentialProofs,
            validatorFields,
            eigenPod,
            validatorStakedButNotVerifiedEth
        );

        // decrement stakedButNotVerifiedEth by totalStakedAndVerifiedETH
        stakedButNotVerifiedEth -= totalStakedAndVerifiedETH;

        // update the gas spent for RestakeAdmin
        _recordGas(gasBefore, baseGasAmountSpent);
    }

    /**
     * @notice  Tracks the Exit Balance for checkpoints started outside OperatorDelegator. i.e. Through verifyStaleBalance.
     * @dev     Permissioned call by only
     * @param   missedCheckpoints  .
     */
    function emergencyTrackMissedCheckpoint(
        uint64[] memory missedCheckpoints
    ) external onlyEmergencyCheckpointTrackingAdmin {
        (uint256 _totalBeaconChainExitBalance, uint64 latestCheckpoint) = OperatorDelegatorLib
            .trackMissedCheckpoint(missedCheckpoints, recordedCheckpoints, eigenPod);

        // record total beacon chain exit balance
        totalBeaconChainExitBalance += _totalBeaconChainExitBalance;

        // record the latestCheckpoint as lastCheckpointTimestamp
        lastCheckpointTimestamp = latestCheckpoint;
    }

    /**
     * @notice  Tracks Slashing delta of queuedWithdrawal
     * @param   withdrawalRoots  EigenLayer withdrawal roots to track slashing delta for
     */
    function emergencyTrackSlashedQueuedWithdrawalDelta(
        bytes32[] calldata withdrawalRoots
    ) external {
        OperatorDelegatorLib.trackSlashedQueuedWithdrawalDelta(
            withdrawalRoots,
            queuedWithdrawal,
            queuedWithdrawalTokenInfo,
            totalTokenQueuedSharesSlashedDelta,
            delegationManager
        );
    }

    /**
     * @notice  Starts a checkpoint on the eigenPod
     * @dev     permissioned call by NativeEthRestakeAdmin
     */
    function startCheckpoint() external onlyNativeEthRestakeAdmin {
        uint256 gasBefore = gasleft();
        // check if any active checkpoint
        if (currentCheckpointTimestamp != 0) revert CheckpointAlreadyActive();

        // check for checkpoint sync
        _checkCheckpointSync();

        // start checkpoint
        eigenPod.startCheckpoint(true);
        // track the current checkpoint timestamp
        currentCheckpointTimestamp = eigenPod.currentCheckpointTimestamp();
        // record the checkpoint
        recordedCheckpoints[currentCheckpointTimestamp] = true;

        // update the gas spent for RestakeAdmin
        _recordGas(gasBefore, NOMINAL_BASE_GAS_SPENT);
    }

    /**
     * @notice  Verify Checkpoint Proofs on EigenPod for currently active checkpoint and tracks exited validator balance
     * @dev     permissioned call by NativeEthRestakeAdmin
     * @param   balanceContainerProof  proves the beacon's current balance container root against a checkpoint's `beaconBlockRoot`
     * @param   proofs  Proofs for one or more validator current balances against the `balanceContainerRoot`
     */
    function verifyCheckpointProofs(
        BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof,
        BeaconChainProofs.BalanceProof[] calldata proofs
    ) external onlyNativeEthRestakeAdmin {
        uint256 gasBefore = gasleft();

        // Note: try catch is used to prevent revert condition as checkpoints can be verified externally
        try eigenPod.verifyCheckpointProofs(balanceContainerProof, proofs) {} catch {}

        // if checkpoint completed. i.e eigenPod.lastCheckpointTimestamp() == currentCheckpointTimestamp
        if (eigenPod.lastCheckpointTimestamp() == currentCheckpointTimestamp) {
            // add the last completed checkpoint Exited balance in WEI
            uint256 totalBeaconChainExitBalanceGwei = eigenPod.checkpointBalanceExitedGwei(
                currentCheckpointTimestamp
            );
            totalBeaconChainExitBalance += (totalBeaconChainExitBalanceGwei * GWEI_TO_WEI);

            // track completed checkpoint as last completed checkpoint
            lastCheckpointTimestamp = currentCheckpointTimestamp;

            // reset current checkpoint
            delete currentCheckpointTimestamp;
        }

        // update the gas spent for RestakeAdmin
        _recordGas(gasBefore, baseGasAmountSpent);
    }

    /**
     * @notice  Claim ERC20 rewards from EigenLayer
     * @dev     Permissioned call only by EigenLayerRewardsAdmin
     * @param   claim  RewardsMerkleClaim object to process claim
     */
    function claimRewards(
        IRewardsCoordinatorTypes.RewardsMerkleClaim calldata claim
    ) external onlyEigenLayerRewardsAdmin {
        // check revert if reward destination not set
        if (rewardsDestination == address(0)) revert RewardsDestinationNotConfigured();

        uint256 gasBefore = gasleft();
        rewardsCoordinator.processClaim(claim, address(this));

        // process claimed rewards. i.e. If supported collateral asset then restake otherwise forward to rewards Destination
        for (uint256 i = 0; i < claim.tokenLeaves.length; ) {
            if (address(claim.tokenLeaves[i].token) == WETH) {
                uint256 amount = IERC20(WETH).balanceOf(address(this));
                // withdraw WETH to ETH
                IWeth(WETH).withdraw(amount);
                // process ETH
                _processETH();
                // (bool success, ) = address(this).call{ value: amount }("");
                // if (!success) revert TransferFailed();
            } else if (address(tokenStrategyMapping[claim.tokenLeaves[i].token]) != address(0)) {
                // if token supported as collateral then restake
                _deposit(
                    claim.tokenLeaves[i].token,
                    claim.tokenLeaves[i].token.balanceOf(address(this))
                );
            } else {
                // if token not supported then send to rewardsDestination
                claim.tokenLeaves[i].token.safeTransfer(
                    rewardsDestination,
                    claim.tokenLeaves[i].token.balanceOf(address(this))
                );
            }

            unchecked {
                ++i;
            }
        }

        // update the gas spent for RewardsAdmin
        _recordGas(gasBefore, baseGasAmountSpent);
    }

    /**
     * @notice  Emergency function to track AVS slashing amount for beacon chain ETH strategy
     * @dev     permissioned call (onlyEmergencyTrackAVSEthSlashingAdmin)
     * @param   slashedAmount  amount of ETH slashed through AVS slashing
     */
    function emergencyTrackAVSEthSlashedAmount(
        uint256 slashedAmount
    ) external onlyEmergencyTrackAVSEthSlashingAdmin {
        beaconChainEthAvsSlashingAmount = slashedAmount;
    }

    /**
     * @notice  Recover tokens accidentally sent to EigenPod
     * @dev     Only callable by admin
     * @param   tokenList  .
     * @param   amountsToWithdraw  .
     * @param   recipient  .
     */
    function recoverTokens(
        IERC20[] memory tokenList,
        uint256[] memory amountsToWithdraw,
        address recipient
    ) external onlyNativeEthRestakeAdmin {
        eigenPod.recoverTokens(tokenList, amountsToWithdraw, recipient);
    }

    function _getPartialWithdrawalsPodDelta() internal view returns (uint256 podDelta) {
        // amount of ETH in partial withdrawals. i.e. Rewards.
        // Note: rewards will be part of TVL once claimed and restaked
        podDelta = ((uint256(eigenPod.withdrawableRestakedExecutionLayerGwei()) * GWEI_TO_WEI) -
            beaconChainEthAvsSlashingAmount >
            totalBeaconChainExitBalance)
            ? ((uint256(eigenPod.withdrawableRestakedExecutionLayerGwei()) * GWEI_TO_WEI) -
                beaconChainEthAvsSlashingAmount) - totalBeaconChainExitBalance
            : 0;
    }

    function _getQueuedSharesWithSlashing(address _underlying) internal view returns (uint256) {
        return queuedShares[_underlying] - totalTokenQueuedSharesSlashedDelta[_underlying];
    }

    /**
     * @notice  Adds the amount of gas spent for an account
     * @dev     Tracks for later redemption from rewards coming from the DWR
     * @param   initialGas  .
     */
    function _recordGas(uint256 initialGas, uint256 baseGasAmount) internal {
        uint256 gasSpent = (initialGas - gasleft() + baseGasAmount) * block.basefee;

        // get the gas refund address if configured
        address _gasRefundAddress = gasRefundAddress == address(0) ? msg.sender : gasRefundAddress;

        adminGasSpentInWei[_gasRefundAddress] += gasSpent;
        emit GasSpent(_gasRefundAddress, gasSpent);
    }

    ///@notice Calculates the pubkey hash of a validator's pubkey as per SSZ spec
    /// @dev using same calculation as EigenPod _calculateValidatorPubkeyHash
    function _calculateValidatorPubkeyHash(
        bytes memory validatorPubkey
    ) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(validatorPubkey, bytes16(0)));
    }

    /**
     * @notice  Send owed refunds to the admin
     * @dev     .
     * @return  uint256  .
     */
    function _refundGas() internal returns (uint256) {
        uint256 gasRefund = address(this).balance >= adminGasSpentInWei[tx.origin]
            ? adminGasSpentInWei[tx.origin]
            : address(this).balance;

        bool success = payable(tx.origin).send(gasRefund);
        if (!success) revert TransferFailed();

        // reset gas spent by admin
        adminGasSpentInWei[tx.origin] -= gasRefund;

        emit GasRefunded(tx.origin, gasRefund);
        return gasRefund;
    }

    function _checkZeroAddress(address _potentialAddress) internal pure {
        if (_potentialAddress == address(0)) revert InvalidZeroInput();
    }

    /// @dev Allows only a whitelisted address to configure the contract
    function _onlyOperatorDelegatorAdmin() internal view {
        if (!roleManager.isOperatorDelegatorAdmin(msg.sender)) revert NotOperatorDelegatorAdmin();
    }

    /// @dev Allows only a whitelisted address to configure the contract
    function _onlyNativeEthRestakeAdmin() internal view {
        if (!roleManager.isNativeEthRestakeAdmin(msg.sender)) revert NotNativeEthRestakeAdmin();
    }

    /// @dev Allows only the RestakeManager address to call functions
    function _onlyRestakeManager() internal view {
        if (msg.sender != address(restakeManager)) revert NotRestakeManager();
    }

    /**
     * @notice revert if lastCheckpointTimestamp is not recorded
     * 1. To prevent deposits when checkpoint was started through verifyStaleBalance
     * and then completed but not recorded by OperatorDelegator through emergencytrackCheckpoint.
     * 2. Can also prevent deposits when checkpoint was started through OperatorDelegator
     * but not completed through OD i.e. not recorded in OperatorDelegator.
     * 3. Prevents starting new checkpoint through operatorDelegator if lastcheckpoint timestamps are not synced
     *
     * @dev Checks if the lastCheckpointTimestamp of OD is synced with EigenPod
     * reverts if any completed checkpoint is not synced in OD
     */
    function _checkCheckpointSync() internal view {
        uint64 eigenPodLastCheckpointTimestamp = eigenPod.lastCheckpointTimestamp();
        if (
            eigenPodLastCheckpointTimestamp != 0 &&
            lastCheckpointTimestamp != 0 &&
            eigenPodLastCheckpointTimestamp > lastCheckpointTimestamp
        ) revert CheckpointNotRecorded();
    }

    /**
     * @notice  Reduces queued shares for collateral asset in withdrawal request
     * @dev     checks for any Invalid collateral asset provided in withdrawal request
     * @param   withdrawal  Withdrawal request struct on EigenLayer
     * @param   tokens  list of tokens in withdrawal request
     */
    function _reduceQueuedShares(
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] memory tokens
    ) internal {
        for (uint256 i; i < tokens.length; ) {
            _checkZeroAddress(address(tokens[i]));
            if (
                address(tokens[i]) != IS_NATIVE &&
                withdrawal.strategies[i] == delegationManager.beaconChainETHStrategy()
            ) revert IncorrectStrategy();

            // Calculate withdrawal root for the given withdrawal
            bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);

            // deduct queued shares with the initial withdrawable shares queued for tracking TVL
            queuedShares[address(tokens[i])] -= queuedWithdrawalTokenInfo[withdrawalRoot][
                address(tokens[i])
            ].initialWithdrawableShares;
            if (
                queuedWithdrawalTokenInfo[withdrawalRoot][address(tokens[i])].sharesSlashedDelta > 0
            ) {
                // reduce total slashed delta with queuedWithdrawalTokenInfo.sharesSharedDelta
                totalTokenQueuedSharesSlashedDelta[address(tokens[i])] -= queuedWithdrawalTokenInfo[
                    withdrawalRoot
                ][address(tokens[i])].sharesSlashedDelta;

                // delete queuedWithdrawalTokenInfo for the withdrawal root
                delete queuedWithdrawalTokenInfo[withdrawalRoot][address(tokens[i])];
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice  Fill withdraw buffer for all ERC20 collateral asset and reDeposit remaining asset
     */
    function _fillBufferAndReDeposit() internal {
        IWithdrawQueue withdrawQueue = restakeManager.depositQueue().withdrawQueue();
        for (uint256 i = 0; i < restakeManager.getCollateralTokensLength(); ) {
            IERC20 token = restakeManager.collateralTokens(i);
            // Check the withdraw buffer and fill if below buffer target
            uint256 bufferToFill = withdrawQueue.getWithdrawDeficit(address(token));

            // get balance of this contract
            uint256 balanceOfToken = token.balanceOf(address(this));

            if (bufferToFill > 0 && balanceOfToken > 0) {
                bufferToFill = (balanceOfToken <= bufferToFill) ? balanceOfToken : bufferToFill;

                // update amount to send to the operator Delegator
                balanceOfToken -= bufferToFill;

                // safe Approve for depositQueue
                token.safeIncreaseAllowance(address(restakeManager.depositQueue()), bufferToFill);

                // fill Withdraw Buffer via depositQueue
                restakeManager.depositQueue().fillERC20withdrawBuffer(address(token), bufferToFill);
            }

            // Deposit remaining token back to eigenLayer
            if (balanceOfToken > MIN_REDEPOSIT_AMOUNT) {
                _deposit(token, balanceOfToken);
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice  process ETH received by contract
     */
    function _processETH() internal {
        uint256 remainingAmount = address(this).balance;
        // check if any pending Exit Balance
        if (totalBeaconChainExitBalance > 0) {
            uint256 exitedBalanceToForward = address(this).balance > totalBeaconChainExitBalance
                ? totalBeaconChainExitBalance
                : address(this).balance;

            // forward exited balance as fullWithdrawal
            restakeManager.depositQueue().forwardFullWithdrawalETH{
                value: exitedBalanceToForward
            }();

            // reduce totalBeaconChainExitBalance
            totalBeaconChainExitBalance -= exitedBalanceToForward;

            // update remaining amount
            remainingAmount -= exitedBalanceToForward;

            // check and return if remaining amount is 0
            if (remainingAmount == 0) {
                return;
            }
        }

        // considered the remaining amount as protocol rewards
        uint256 gasRefunded = 0;
        if (adminGasSpentInWei[tx.origin] > 0) {
            gasRefunded = _refundGas();
            // update the remaining amount
            remainingAmount -= gasRefunded;
            // If no funds left, return
            if (remainingAmount == 0) {
                return;
            }
        }

        // Forward remaining balance to the deposit queue
        address destination = address(restakeManager.depositQueue());
        (bool success, ) = destination.call{ value: remainingAmount }("");
        if (!success) revert TransferFailed();

        emit RewardsForwarded(destination, remainingAmount);
    }

    /**
     * @notice Users should NOT send ETH directly to this contract unless they want to donate to existing ezETH holders.
     *        This is an internal protocol function.
     * @dev Handle ETH sent to this contract - will get forwarded to the deposit queue for restaking as a protocol reward
     * @dev If msg.sender is eigenPod then forward ETH to deposit queue without taking cut (i.e. full withdrawal from beacon chain)
     */
    receive() external payable {
        // if ETH coming from WETH then return
        if (msg.sender == WETH) {
            return;
        }
        // process ETH
        _processETH();
    }
}
