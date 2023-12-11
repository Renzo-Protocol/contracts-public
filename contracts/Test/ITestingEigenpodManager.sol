//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITestingEigenpodManager {  
  function recordBeaconChainETHBalanceUpdate(address podOwner, int256 sharesDelta) external;
}