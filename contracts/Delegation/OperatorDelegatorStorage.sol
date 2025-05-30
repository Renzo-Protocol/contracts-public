// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;
import "../Permissions/IRoleManager.sol";
import "../EigenLayer/interfaces/IStrategy.sol";
import "../EigenLayer/interfaces/IStrategyManager.sol";
import "../EigenLayer/interfaces/IDelegationManager.sol";
import "../EigenLayer/interfaces/IEigenPod.sol";
import "../EigenLayer/interfaces/IRewardsCoordinator.sol";
import "./IOperatorDelegator.sol";
import "../IRestakeManager.sol";
import "./utils/WETHUnwrapper.sol";

/// @title OperatorDelegatorStorage
/// @dev This contract will hold all local variables for the  Contract
/// When upgrading the protocol, inherit from this contract on the V2 version and change the
/// StorageManager to inherit from the later version.  This ensures there are no storage layout
/// corruptions when upgrading.
abstract contract OperatorDelegatorStorageV1 is IOperatorDelegator {
    /// @dev reference to the RoleManager contract
    IRoleManager public roleManager;

    /// @dev The main strategy manager contract in EigenLayer
    IStrategyManager public strategyManager;

    /// @dev the restake manager contract
    IRestakeManager public restakeManager;

    /// @dev The mapping of supported token addresses to their respective strategy addresses
    /// This will control which tokens are supported by the protocol
    mapping(IERC20 => IStrategy) public tokenStrategyMapping;

    /// @dev The address to delegate tokens to in EigenLayer
    address public delegateAddress;

    /// @dev the delegation manager contract
    IDelegationManager public delegationManager;

    /// @dev the EigenLayer EigenPodManager contract
    IEigenPodManager public eigenPodManager;

    /// @dev The EigenPod owned by this contract
    IEigenPod public eigenPod;

    /// @dev Tracks the balance that was staked to validators but hasn't been restaked to EL yet
    uint256 public stakedButNotVerifiedEth;
}

abstract contract OperatorDelegatorStorageV2 is OperatorDelegatorStorageV1 {
    /// @dev - DEPRECATED - This variable is no longer used
    uint256 public pendingUnstakedDelayedWithdrawalAmount;
}

abstract contract OperatorDelegatorStorageV3 is OperatorDelegatorStorageV2 {
    /// @dev A base tx gas amount for a transaction to be added for redemption later - in gas units
    uint256 public baseGasAmountSpent;

    /// @dev A mapping to track how much gas was spent by an address
    mapping(address => uint256) public adminGasSpentInWei;
}

abstract contract OperatorDelegatorStorageV4 is OperatorDelegatorStorageV3 {
    /// @dev mapping of token shares in withdraw queue of EigenLayer
    mapping(address => uint256) public queuedShares;

    /// @dev bool mapping to track if withdrawal is already queued by withdrawalRoot
    mapping(bytes32 => bool) public queuedWithdrawal;

    /// @dev mapping of validatorStakedButNotVerifiedEth with the key as validatorPubkeyHash
    mapping(bytes32 => uint256) public validatorStakedButNotVerifiedEth;
}

abstract contract OperatorDelegatorStorageV5 is OperatorDelegatorStorageV4 {
    /// @dev EigenLayer Rewards Coordinator
    IRewardsCoordinator public rewardsCoordinator;

    /// @dev EigenLayer Rewards Destination
    address public rewardsDestination;
}

abstract contract OperatorDelegatorStorageV6 is OperatorDelegatorStorageV5 {
    /// @dev Tracks total amount of BeaconChain Eth exited
    uint256 public totalBeaconChainExitBalance;

    /// @dev Tracks currently verifying checkpoint timestamp
    uint64 public currentCheckpointTimestamp;
}

abstract contract OperatorDelegatorStorageV7 is OperatorDelegatorStorageV6 {
    /// @notice Deprecated, not using anymore
    /// @dev WETHunwrapper to unwrape WETH received by EigenLayerRewards
    WETHUnwrapper public wethUnwrapper;
}

abstract contract OperatorDelegatorStorageV8 is OperatorDelegatorStorageV7 {
    /// @dev Tracks all the recorded checkpoints
    mapping(uint64 => bool) public recordedCheckpoints;
}

abstract contract OperatorDelegatorStorageV9 is OperatorDelegatorStorageV8 {
    /// @dev Tracks the last finalized checkpoint timestamp
    uint64 public lastCheckpointTimestamp;
}

abstract contract OperatorDelegatorStorageV10 is OperatorDelegatorStorageV9 {
    address public gasRefundAddress;
}

abstract contract OperatorDelegatorStorageV11 is OperatorDelegatorStorageV10 {
    /// @dev Tracks slashed delta for queuedWithdrawal
    mapping(bytes32 => mapping(address => QueuedWithdrawal)) public queuedWithdrawalTokenInfo;

    /// @dev Tracks total slashed delta for collateral asset
    mapping(address => uint256) public totalTokenQueuedSharesSlashedDelta;

    /// @dev Track the beaconChainETH AVS slashing amount
    uint256 public beaconChainEthAvsSlashingAmount;
}

/// On the next version of the protocol, if new variables are added, put them in the below
/// contract and use this as the inheritance chain.
// abstract contract OperatorDelegatorStorageV8 is OperatorDelegatorStorageV7 {
// }
