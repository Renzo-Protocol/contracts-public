// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

/// @title RoleManagerStorage
/// @dev This contract will hold all local variables for the RoleManager Contract
/// When upgrading the protocol, inherit from this contract on the V2 version and change the
/// StorageManager to inherit from the later version.  This ensures there are no storage layout
/// corruptions when upgrading.
contract RoleManagerStorageV1 {
    /// @dev role for granting capability to mint/burn ezETH
    bytes32 public constant RX_ETH_MINTER_BURNER = keccak256("RX_ETH_MINTER_BURNER");

    /// @dev role for granting capability to update config on the OperatorDelgator Contracts
    bytes32 public constant OPERATOR_DELEGATOR_ADMIN = keccak256("OPERATOR_DELEGATOR_ADMIN");

    /// @dev role for granting capability to update config on the Oracle Contract
    bytes32 public constant ORACLE_ADMIN = keccak256("ORACLE_ADMIN");

    /// @dev role for granting capability to update config on the Restake Manager
    bytes32 public constant RESTAKE_MANAGER_ADMIN = keccak256("RESTAKE_MANAGER_ADMIN");

    /// @dev role for granting capability to update config on the Token Contract
    bytes32 public constant TOKEN_ADMIN = keccak256("TOKEN_ADMIN");

    /// @dev role for granting capability to restake native ETH
    bytes32 public constant NATIVE_ETH_RESTAKE_ADMIN = keccak256("NATIVE_ETH_RESTAKE_ADMIN");

    /// @dev role for sweeping ERC20 Rewards
    bytes32 public constant ERC20_REWARD_ADMIN = keccak256("ERC20_REWARD_ADMIN");

    /// @dev role for pausing deposits and withdraws on RestakeManager
    bytes32 public constant DEPOSIT_WITHDRAW_PAUSER = keccak256("DEPOSIT_WITHDRAW_PAUSER");
}

/// On the next version of the protocol, if new variables are added, put them in the below
/// contract and use this as the inheritance chain.
contract RoleManagerStorageV2 is RoleManagerStorageV1 {
    /// @dev role for granting capability to update whitelisted origin in xRenzoBridge
    bytes32 public constant BRIDGE_ADMIN = keccak256("BRIDGE_ADMIN");

    /// @dev role to granting capability to send price feed of ezETH to L2
    bytes32 public constant PRICE_FEED_SENDER = keccak256("PRICE_FEED_SENDER");
}

contract RoleManagerStorageV3 is RoleManagerStorageV2 {
    /// @dev role for granting capability to update withdraw queue buffer and cooldown period
    bytes32 public constant WITHDRAW_QUEUE_ADMIN = keccak256("WITHDRAW_QUEUE_ADMIN");

    /// @dev role for granting capability to track pending queued withdrawal shares caused by Operator undelegation
    bytes32 public constant EMERGENCY_WITHDRAW_TRACKING_ADMIN =
        keccak256("EMERGENCY_WITHDRAW_TRACKING_ADMIN");
}

contract RoleManagerStorageV4 is RoleManagerStorageV3 {
    /// @dev role for granting capability to process and claim EigenLayer rewards
    bytes32 public constant EIGEN_LAYER_REWARDS_ADMIN = keccak256("EIGEN_LAYER_REWARDS_ADMIN");
}

contract RoleManagerStorageV5 is RoleManagerStorageV4 {
    /// @dev role for granting capability to track and record exit balance for missed checkpoints
    bytes32 public constant EMERGENCY_CHECKPOINT_TRACKING_ADMIN =
        keccak256("EMERGENCY_CHECKPOINT_TRACKING_ADMIN");
}

contract RoleManagerStorageV6 is RoleManagerStorageV5 {
    /// @dev role for granting capability to update the gas amount spent by admin
    bytes32 public constant EMERGENCY_AVS_ETH_SLASH_TRACKING_ADMIN =
        keccak256("EMERGENCY_AVS_ETH_SLASH_TRACKING_ADMIN");
}
