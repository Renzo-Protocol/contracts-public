// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../Permissions/IRoleManager.sol";

abstract contract RewardHandlerStorageV1 {
    /// @dev reference to the RoleManager contract
    IRoleManager public roleManager;

    /// @dev the address of the depositQueue contract
    address public rewardDestination;
}
