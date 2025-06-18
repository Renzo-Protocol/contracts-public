// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

interface IRiskOracleMiddleware {
    function depositPaused() external view returns (bool);
    function withdrawRequestPaused() external view returns (bool);
    function withdrawClaimPaused() external view returns (bool);
    function instantWithdrawPaused() external view returns (bool);
    function withdrawCooldownPeriod() external view returns (uint256);
}
