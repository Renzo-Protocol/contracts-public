// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IWithdrawQueue {
    /// @dev To get available value to withdraw from buffer
    /// @param _asset address of token
    function getAvailableToWithdraw(address _asset) external view returns (uint256);

    /// @dev To get the withdraw buffer target of given asset
    /// @param _asset address of token
    function withdrawalBufferTarget(address _asset) external view returns (uint256);

    /// @dev To get the current Target Buffer Deficit
    /// @param _asset address of token
    function getBufferDeficit(address _asset) external view returns (uint256);

    /// @dev Fill ERC20 Withdraw Buffer
    /// @param _asset the token address to fill the respective buffer
    /// @param _amount  amount of token to fill with
    function fillERC20WithdrawBuffer(address _asset, uint256 _amount) external;

    /// @dev to get the withdrawRequests for particular user
    /// @param _user address of the user
    function withdrawRequests(address _user) external view returns (uint256[] memory);

    /// @dev Fill ETH Withdraw buffer
    function fillEthWithdrawBuffer() external payable;
}
