//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title RoleManagerStorage
/// @dev This contract will hold all local variables for the RoleManager Contract
/// When upgrading the protocol, inherit from this contract on the V2 version and change the
/// StorageManager to inherit from the later version.  This ensures there are no storage layout
/// corruptions when upgrading.
contract RoleManagerStorageV1 {
    /// @dev role for granting capability to mint/burn ezETH
    bytes32 public constant RX_ETH_MINTER_BURNER =
        keccak256("RX_ETH_MINTER_BURNER");

    /// @dev role for granting capability to update config on the OperatorDelgator Contracts
    bytes32 public constant OPERATOR_DELEGATOR_ADMIN =
        keccak256("OPERATOR_DELEGATOR_ADMIN");

    /// @dev role for granting capability to update config on the Oracle Contract
    bytes32 public constant ORACLE_ADMIN =
        keccak256("ORACLE_ADMIN");

    /// @dev role for granting capability to update config on the Restake Manager
    bytes32 public constant RESTAKE_MANAGER_ADMIN =
        keccak256("RESTAKE_MANAGER_ADMIN");

    /// @dev role for granting capability to update config on the Token Contract
    bytes32 public constant TOKEN_ADMIN =
        keccak256("TOKEN_ADMIN");

    /// @dev role for granting capability to restake native ETH
    bytes32 public constant NATIVE_ETH_RESTAKE_ADMIN =
        keccak256("NATIVE_ETH_RESTAKE_ADMIN");

    /// @dev role for sweeping ERC20 Rewards
    bytes32 public constant ERC20_REWARD_ADMIN =
        keccak256("ERC20_REWARD_ADMIN");

    /// @dev role for pausing deposits and withdraws on RestakeManager
    bytes32 public constant DEPOSIT_WITHDRAW_PAUSER =
        keccak256("DEPOSIT_WITHDRAW_PAUSER");
}

/// On the next version of the protocol, if new variables are added, put them in the below
/// contract and use this as the inheritance chain.
/**
contract RoleManagerStorageV2 is RoleManagerStorageV1 {
  address newVariable;
}
 */
