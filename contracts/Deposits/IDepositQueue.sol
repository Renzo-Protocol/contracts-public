//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDepositQueue {
  function depositETHFromProtocol() external payable;
  function totalEarned(address tokenAddress) external view returns(uint256);
}
