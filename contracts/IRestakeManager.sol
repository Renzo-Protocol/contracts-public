//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./Delegation/IOperatorDelegator.sol";
import "./Deposits/IDepositQueue.sol";

interface IRestakeManager {
  function stakeEthInOperatorDelegator(IOperatorDelegator operatorDelegator, bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;
  function depositTokenRewardsFromProtocol(
        IERC20 _token,
        uint256 _amount
    ) external;
  function depositQueue() external view returns (IDepositQueue);
}
