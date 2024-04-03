// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./Delegation/IOperatorDelegator.sol";
import "./Deposits/IDepositQueue.sol";

interface IRestakeManager {
    function stakeEthInOperatorDelegator(
        IOperatorDelegator operatorDelegator,
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable;
    function depositTokenRewardsFromProtocol(IERC20 _token, uint256 _amount) external;
    function depositQueue() external view returns (IDepositQueue);

    function calculateTVLs() external view returns (uint256[][] memory, uint256[] memory, uint256);

    function depositETH() external payable;
}
