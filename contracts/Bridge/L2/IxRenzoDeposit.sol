// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IxRenzoDeposit {
    function deposit(
        IERC20 _token,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _deadline
    ) external returns (uint256);
    function sweep(IERC20 _token) external payable;

    function updatePrice(uint256 price, uint256 timestamp) external;
}
