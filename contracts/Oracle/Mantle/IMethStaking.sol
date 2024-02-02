//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMethStaking {       
  function mETHToETH(uint256 mETHAmount) external view returns (uint256);
}
