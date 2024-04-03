// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IxRenzoDeposit {
    function deposit(
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _deadline
    ) external returns (uint256);
    function sweep() external payable;

    function updatePrice(uint256 price, uint256 timestamp) external;
}
