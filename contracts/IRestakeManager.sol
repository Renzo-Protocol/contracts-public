// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

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
    function calculateTVLsStETHMarketRate()
        external
        view
        returns (uint256[][] memory, uint256[] memory, uint256);

    function depositETH() external payable;
    function deposit(IERC20 _collateralToken, uint256 _amount) external;

    function getCollateralTokenIndex(IERC20 _collateralToken) external view returns (uint256);

    function getCollateralTokensLength() external view returns (uint256);

    function collateralTokens(uint256 index) external view returns (IERC20);
}
