// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "../Withdraw/IWithdrawQueue.sol";

interface IDepositQueue {
    function depositETHFromProtocol() external payable;
    function totalEarned(address tokenAddress) external view returns (uint256);
    function forwardFullWithdrawalETH() external payable;
    function withdrawQueue() external view returns (IWithdrawQueue);
    function fillERC20withdrawBuffer(address _asset, uint256 _amount) external;
}
