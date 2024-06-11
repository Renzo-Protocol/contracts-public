// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../Permissions/IRoleManager.sol";
import "./OperatorDelegatorStorage.sol";
import "../EigenLayer/interfaces/IDelegationManager.sol";
import "../EigenLayer/interfaces/ISignatureUtils.sol";
import "../EigenLayer/libraries/BeaconChainProofs.sol";
import "../Errors/Errors.sol";

/// @dev This contract will be responsible for interacting with Eigenlayer
/// Each of these contracts deployed will be delegated to one specific operator
/// This contract can handle multiple ERC20 tokens, all of which will be delegated to the same operator
/// Each supported ERC20 token will be pointed at a single Strategy contract in EL
/// Only the RestakeManager should be interacting with this contract for EL interactions.
contract OperatorDelegator is
    Initializable,
    ReentrancyGuardUpgradeable,
    OperatorDelegatorStorageV4
{
    using SafeERC20 for IERC20;
    using BeaconChainProofs for *;

    uint256 internal constant GWEI_TO_WEI = 1e9;

    address public constant IS_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev Max stakedButNotVerifiedEth amount cap per validator
    uint256 public constant MAX_STAKE_BUT_NOT_VERIFIED_AMOUNT = 32 ether;

    /// @dev Nominal base gas spent value by admin
    uint256 internal constant NOMINAL_BASE_GAS_SPENT = 50_000;

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

    modifier onlyEmergencyWithdrawTrackingAdmin() {
        if (!roleManager.isEmergencyWithdrawTrackingAdmin(msg.sender))
            revert NotEmergencyWithdrawTrackingAdmin();
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
        eigenPod = IEigenPod(eigenPodManager.createPod());
    }

    /// @dev Migrates the M1 pods to M2 pods by calling activateRestaking on eigenPod
    /// @dev Should be a permissioned call by onlyNativeEthRestakeAdmin
    function activateRestaking() external nonReentrant onlyNativeEthRestakeAdmin {
        eigenPod.activateRestaking();
    }

    /// @dev Sets the strategy for a given token - setting strategy to 0x0 removes the ability to deposit and withdraw token
    function setTokenStrategy(
        IERC20 _token,
        IStrategy _strategy
    ) external nonReentrant onlyOperatorDelegatorAdmin {
        if (address(_token) == address(0x0)) revert InvalidZeroInput();

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
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external nonReentrant onlyOperatorDelegatorAdmin {
        if (address(_delegateAddress) == address(0x0)) revert InvalidZeroInput();
        if (address(delegateAddress) != address(0x0)) revert DelegateAddressAlreadySet();

        delegateAddress = _delegateAddress;

        delegationManager.delegateTo(delegateAddress, approverSignatureAndExpiry, approverSalt);

        emit DelegationAddressUpdated(_delegateAddress);
    }

    function setBaseGasAmountSpent(
        uint256 _baseGasAmountSpent
    ) external nonReentrant onlyOperatorDelegatorAdmin {
        if (_baseGasAmountSpent == 0) revert InvalidZeroInput();
        emit BaseGasAmountSpentUpdated(baseGasAmountSpent, _baseGasAmountSpent);
        baseGasAmountSpent = _baseGasAmountSpent;
    }

    /// @dev Deposit tokens into the EigenLayer.  This call assumes any balance of tokens in this contract will be delegated
    /// so do not directly send tokens here or they will be delegated and attributed to the next caller.
    /// @return shares The amount of new shares in the `strategy` created as part of the action.
    function deposit(
        IERC20 token,
        uint256 tokenAmount
    ) external nonReentrant onlyRestakeManager returns (uint256 shares) {
        if (address(tokenStrategyMapping[token]) == address(0x0) || tokenAmount == 0)
            revert InvalidZeroInput();

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
        // verify array lengths
        if (tokens.length != withdrawals.length) revert MismatchedArrayLengths();
        for (uint256 i = 0; i < withdrawals.length; ) {
            if (address(tokens[i]) == address(0)) revert InvalidZeroInput();
            // calculate withdrawalRoot
            bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawals[i]);

            // verify withdrawal is not tracked
            if (queuedWithdrawal[withdrawalRoot]) revert WithdrawalAlreadyTracked();

            // verify withdrawal is pending and protocol not double counting
            if (!delegationManager.pendingWithdrawals(withdrawalRoot))
                revert WithdrawalAlreadyCompleted();

            // verify LST token is not provided if beaconChainETHStrategy in Withdraw Request
            if (
                address(tokens[i]) != IS_NATIVE &&
                withdrawals[i].strategies[0] == delegationManager.beaconChainETHStrategy()
            ) revert IncorrectStrategy();

            // track queued shares for the token
            queuedShares[address(tokens[i])] += withdrawals[i].shares[0];

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice  Starts a withdrawal from specified tokens strategies for given amounts
     * @dev     permissioned call (onlyNativeEthRestakeAdmin)
     * @param   tokens  list of tokens to withdraw from. For ETH -> 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
     * @param   tokenAmounts  list of token amounts i'th index token in tokens
     * @return  bytes32  withdrawal root
     */
    function queueWithdrawals(
        IERC20[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external nonReentrant onlyNativeEthRestakeAdmin returns (bytes32) {
        // record gas spent
        uint256 gasBefore = gasleft();
        if (tokens.length != tokenAmounts.length) revert MismatchedArrayLengths();
        IDelegationManager.QueuedWithdrawalParams[]
            memory queuedWithdrawalParams = new IDelegationManager.QueuedWithdrawalParams[](1);

        // set strategies legth for 0th index only
        queuedWithdrawalParams[0].strategies = new IStrategy[](tokens.length);
        queuedWithdrawalParams[0].shares = new uint256[](tokens.length);

        // Save the nonce before starting the withdrawal
        uint96 nonce = uint96(delegationManager.cumulativeWithdrawalsQueued(address(this)));

        for (uint256 i; i < tokens.length; ) {
            if (address(tokens[i]) == IS_NATIVE) {
                // set beaconChainEthStrategy for ETH
                queuedWithdrawalParams[0].strategies[i] = eigenPodManager.beaconChainETHStrategy();

                // set shares for ETH
                queuedWithdrawalParams[0].shares[i] = tokenAmounts[i];
            } else {
                if (address(tokenStrategyMapping[tokens[i]]) == address(0))
                    revert InvalidZeroInput();

                // set the strategy of the token
                queuedWithdrawalParams[0].strategies[i] = tokenStrategyMapping[tokens[i]];

                // set the equivalent shares for tokenAmount
                queuedWithdrawalParams[0].shares[i] = tokenStrategyMapping[tokens[i]]
                    .underlyingToSharesView(tokenAmounts[i]);
            }

            // set withdrawer as this contract address
            queuedWithdrawalParams[0].withdrawer = address(this);

            // track shares of tokens withdraw for TVL
            queuedShares[address(tokens[i])] += queuedWithdrawalParams[0].shares[i];
            unchecked {
                ++i;
            }
        }

        // queue withdrawal in EigenLayer
        bytes32 withdrawalRoot = delegationManager.queueWithdrawals(queuedWithdrawalParams)[0];

        // track protocol queued withdrawals
        queuedWithdrawal[withdrawalRoot] = true;

        // Emit the withdrawal started event
        emit WithdrawStarted(
            withdrawalRoot,
            address(this),
            delegateAddress,
            address(this),
            nonce,
            block.number,
            queuedWithdrawalParams[0].strategies,
            queuedWithdrawalParams[0].shares
        );

        // update the gas spent for RestakeAdmin
        _recordGas(gasBefore, NOMINAL_BASE_GAS_SPENT);

        return withdrawalRoot;
    }

    /**
     * @notice  Complete the specified withdrawal,
     * @dev     permissioned call (onlyNativeEthRestakeAdmin)
     * @param   withdrawal  Withdrawal struct
     * @param   tokens  list of tokens to withdraw
     * @param   middlewareTimesIndex  is the index in the operator that the staker who triggered the withdrawal was delegated to's middleware times array
     */
    function completeQueuedWithdrawal(
        IDelegationManager.Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex
    ) external nonReentrant onlyNativeEthRestakeAdmin {
        uint256 gasBefore = gasleft();
        if (tokens.length != withdrawal.strategies.length) revert MismatchedArrayLengths();

        // complete the queued withdrawal from EigenLayer with receiveAsToken set to true
        delegationManager.completeQueuedWithdrawal(withdrawal, tokens, middlewareTimesIndex, true);

        IWithdrawQueue withdrawQueue = restakeManager.depositQueue().withdrawQueue();
        for (uint256 i; i < tokens.length; ) {
            if (address(tokens[i]) == address(0)) revert InvalidZeroInput();
            if (
                address(tokens[i]) != IS_NATIVE &&
                withdrawal.strategies[i] == delegationManager.beaconChainETHStrategy()
            ) revert IncorrectStrategy();
            // deduct queued shares for tracking TVL
            queuedShares[address(tokens[i])] -= withdrawal.shares[i];

            // check if token is not Native ETH
            if (address(tokens[i]) != IS_NATIVE) {
                // Check the withdraw buffer and fill if below buffer target
                uint256 bufferToFill = withdrawQueue.getBufferDeficit(address(tokens[i]));

                // get balance of this contract
                uint256 balanceOfToken = tokens[i].balanceOf(address(this));
                if (bufferToFill > 0) {
                    bufferToFill = (balanceOfToken <= bufferToFill) ? balanceOfToken : bufferToFill;

                    // update amount to send to the operator Delegator
                    balanceOfToken -= bufferToFill;

                    // safe Approve for depositQueue
                    tokens[i].safeIncreaseAllowance(
                        address(restakeManager.depositQueue()),
                        bufferToFill
                    );

                    // fill Withdraw Buffer via depositQueue
                    restakeManager.depositQueue().fillERC20withdrawBuffer(
                        address(tokens[i]),
                        bufferToFill
                    );
                }

                // Deposit remaining tokens back to eigenLayer
                if (balanceOfToken > 0) {
                    _deposit(tokens[i], balanceOfToken);
                }
            }
            unchecked {
                ++i;
            }
        }

        // emits the Withdraw Completed event with withdrawalRoot
        emit WithdrawCompleted(
            delegationManager.calculateWithdrawalRoot(withdrawal),
            withdrawal.strategies,
            withdrawal.shares
        );
        // record current spent gas
        _recordGas(gasBefore, NOMINAL_BASE_GAS_SPENT);
    }

    /// @dev Gets the underlying token amount from the amount of shares + queued withdrawal shares
    function getTokenBalanceFromStrategy(IERC20 token) external view returns (uint256) {
        return
            queuedShares[address(token)] == 0
                ? tokenStrategyMapping[token].userUnderlyingView(address(this))
                : tokenStrategyMapping[token].userUnderlyingView(address(this)) +
                    tokenStrategyMapping[token].sharesToUnderlyingView(
                        queuedShares[address(token)]
                    );
    }

    /// @dev Gets the amount of ETH staked in the EigenLayer
    function getStakedETHBalance() external view returns (uint256) {
        // accounts for current podOwner shares + stakedButNotVerified ETH + queued withdraw shares
        int256 podOwnerShares = eigenPodManager.podOwnerShares(address(this));
        return
            podOwnerShares < 0
                ? queuedShares[IS_NATIVE] + stakedButNotVerifiedEth - uint256(-podOwnerShares)
                : queuedShares[IS_NATIVE] + stakedButNotVerifiedEth + uint256(podOwnerShares);
    }

    /// @dev Stake ETH in the EigenLayer
    /// Only the Restake Manager should call this function
    function stakeEth(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable onlyRestakeManager {
        // if validator withdraw credentials is verified
        if (eigenPod.validatorStatus(pubkey) == IEigenPod.VALIDATOR_STATUS.INACTIVE) {
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

        eigenPod.verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndices,
            withdrawalCredentialProofs,
            validatorFields
        );

        // Decrement the staked but not verified ETH
        for (uint256 i = 0; i < validatorFields.length; ) {
            bytes32 validatorPubkeyHash = validatorFields[i].getPubkeyHash();
            // decrement total stakedButNotVerifiedEth by validatorStakedButNotVerifiedEth
            if (validatorStakedButNotVerifiedEth[validatorPubkeyHash] != 0) {
                stakedButNotVerifiedEth -= validatorStakedButNotVerifiedEth[validatorPubkeyHash];
            } else {
                // fallback to decrement total stakedButNotVerifiedEth by MAX_STAKE_BUT_NOT_VERIFIED_AMOUNT
                stakedButNotVerifiedEth -= MAX_STAKE_BUT_NOT_VERIFIED_AMOUNT;
            }

            // set validatorStakedButNotVerifiedEth value to 0
            validatorStakedButNotVerifiedEth[validatorPubkeyHash] = 0;

            unchecked {
                ++i;
            }
        }
        // update the gas spent for RestakeAdmin
        _recordGas(gasBefore, baseGasAmountSpent);
    }

    /**
     * @notice  Verify many Withdrawals and process them in the EigenPod
     * @dev     For each withdrawal (partial or full), verify it in the EigenPod
     *          Only callable by admin.
     * @param   oracleTimestamp  .
     * @param   stateRootProof  .
     * @param   withdrawalProofs  .
     * @param   validatorFieldsProofs  .
     * @param   validatorFields  .
     * @param   withdrawalFields  .
     */
    function verifyAndProcessWithdrawals(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        BeaconChainProofs.WithdrawalProof[] calldata withdrawalProofs,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields,
        bytes32[][] calldata withdrawalFields
    ) external onlyNativeEthRestakeAdmin {
        uint256 gasBefore = gasleft();
        eigenPod.verifyAndProcessWithdrawals(
            oracleTimestamp,
            stateRootProof,
            withdrawalProofs,
            validatorFieldsProofs,
            validatorFields,
            withdrawalFields
        );
        // update the gas spent for RestakeAdmin
        _recordGas(gasBefore, baseGasAmountSpent);
    }

    /**
     * @notice  Pull out any ETH in the EigenPod that is not from the beacon chain
     * @dev     Only callable by admin
     * @param   recipient  Where to send the ETH
     * @param   amountToWithdraw  Amount to pull out
     */
    function withdrawNonBeaconChainETHBalanceWei(
        address recipient,
        uint256 amountToWithdraw
    ) external onlyNativeEthRestakeAdmin {
        eigenPod.withdrawNonBeaconChainETHBalanceWei(recipient, amountToWithdraw);
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

    /**
     * @notice  Starts a delayed withdraw of the ETH from the EigenPodManager
     * @dev     Before the eigenpod is verified, we can sweep out any accumulated ETH from the Consensus layer validator rewards
     *         We also want to track the amount in the delayed withdrawal router so we can track the TVL and reward amount accurately
     */
    function startDelayedWithdrawUnstakedETH() external onlyNativeEthRestakeAdmin {
        // Call the start delayed withdraw function in the EigenPodManager
        // This will queue up a delayed withdrawal that will be sent back to this address after the timeout
        eigenPod.withdrawBeforeRestaking();
    }

    /**
     * @notice  Adds the amount of gas spent for an account
     * @dev     Tracks for later redemption from rewards coming from the DWR
     * @param   initialGas  .
     */
    function _recordGas(uint256 initialGas, uint256 baseGasAmount) internal {
        uint256 gasSpent = (initialGas - gasleft() + baseGasAmount) * block.basefee;
        adminGasSpentInWei[msg.sender] += gasSpent;
        emit GasSpent(msg.sender, gasSpent);
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

    /**
     * @notice Users should NOT send ETH directly to this contract unless they want to donate to existing ezETH holders.
     *        This is an internal protocol function.
     * @dev Handle ETH sent to this contract - will get forwarded to the deposit queue for restaking as a protocol reward
     * @dev If msg.sender is eigenPod then forward ETH to deposit queue without taking cut (i.e. full withdrawal from beacon chain)
     */
    receive() external payable {
        // check if sender contract is EigenPod. forward full withdrawal eth received
        if (msg.sender == address(eigenPod)) {
            restakeManager.depositQueue().forwardFullWithdrawalETH{ value: msg.value }();
        } else {
            // considered as protocol reward
            uint256 gasRefunded = 0;
            uint256 remainingAmount = address(this).balance;
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
    }
}
