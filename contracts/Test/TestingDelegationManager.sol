//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "../EigenLayer/interfaces/IStrategy.sol";
import "../EigenLayer/interfaces/IStrategyManager.sol";
import "./TestingStrategy.sol";
import "../EigenLayer/interfaces/IDelegationManager.sol";

/// @dev this is just a contract to use in unit testing - allows setting return values and mimics minimal logic
contract TestingDelegationManager {
    function calculateWithdrawalRoot(
        IStrategyManager.QueuedWithdrawal memory withdrawal
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(withdrawal));
    }

    uint256 constant withdrawBlockWait = 100;
    mapping(bytes32 => bool) public pendingWithdrawals;
    mapping(address => uint256) public cumulativeWithdrawalsQueued;

    function delegateTo(
        address operator
    ) external {
        // go through the internal delegation flow, checking the `approverSignatureAndExpiry` if applicable
        // shhh
    }

}
