// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../Permissions/IRoleManager.sol";
import "../IRestakeManager.sol";
import "./IDepositQueue.sol";

abstract contract DepositQueueStorageV1 is IDepositQueue {
    /// @dev reference to the RoleManager contract
    IRoleManager public roleManager;

    /// @dev the address of the RestakeManager contract
    IRestakeManager public restakeManager;

    /// @dev the address where fees will be sent - must be non zero to enable fees
    address public feeAddress;

    /// @dev the basis points to charge for fees - 100 basis points = 1%
    uint256 public feeBasisPoints;

    /// @dev the total amount the protocol has earned - token address => amount
    mapping(address => uint256) public totalEarned;
}
