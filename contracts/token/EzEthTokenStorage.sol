// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;
import "../Permissions/IRoleManager.sol";

/// @title EzEthTokenStorage
/// @dev This contract will hold all local variables for the  Contract
/// When upgrading the protocol, inherit from this contract on the V2 version and change the
/// StorageManager to inherit from the later version.  This ensures there are no storage layout
/// corruptions when upgrading.
contract EzEthTokenStorageV1 {
    /// @dev reference to the RoleManager contract
    IRoleManager public roleManager;

    /// @dev flag to control whether transfers are paused
    bool public paused;
}

/// On the next version of the protocol, if new variables are added, put them in the below
/// contract and use this as the inheritance chain.
/**
contract EzEthTokenStorageV2 is EzEthTokenStorageV1 {
  address newVariable;
}
 */
