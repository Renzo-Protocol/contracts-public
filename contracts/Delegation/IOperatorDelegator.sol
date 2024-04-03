// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../EigenLayer/interfaces/IStrategyManager.sol";
import "../EigenLayer/interfaces/IDelegationManager.sol";
import "../EigenLayer/interfaces/IEigenPod.sol";

interface IOperatorDelegator {
    function getTokenBalanceFromStrategy(IERC20 token) external view returns (uint256);

    function deposit(IERC20 _token, uint256 _tokenAmount) external returns (uint256 shares);

    function startWithdrawal(IERC20 _token, uint256 _tokenAmount) external returns (bytes32);

    function completeWithdrawal(
        IStrategyManager.QueuedWithdrawal calldata _withdrawal,
        IERC20 _token,
        uint256 _middlewareTimesIndex,
        address _sendToAddress
    ) external;

    function getStakedETHBalance() external view returns (uint256);

    function stakeEth(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable;

    function eigenPod() external view returns (IEigenPod);

    function pendingUnstakedDelayedWithdrawalAmount() external view returns (uint256);
}
