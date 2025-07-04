// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

interface IRoleManager {
    /// @dev Determines if the specified address has permissions to manage RoleManager
    /// @param potentialAddress Address to check
    function isRoleManagerAdmin(address potentialAddress) external view returns (bool);

    /// @dev Determines if the specified address has permission to mint or burn ezETH tokens
    /// @param potentialAddress Address to check
    function isEzETHMinterBurner(address potentialAddress) external view returns (bool);

    /// @dev Determines if the specified address has permission to update config on the OperatorDelgator Contracts
    /// @param potentialAddress Address to check
    function isOperatorDelegatorAdmin(address potentialAddress) external view returns (bool);

    /// @dev Determines if the specified address has permission to update config on the Oracle Contract config
    /// @param potentialAddress Address to check
    function isOracleAdmin(address potentialAddress) external view returns (bool);

    /// @dev Determines if the specified address has permission to update config on the Restake Manager
    /// @param potentialAddress Address to check
    function isRestakeManagerAdmin(address potentialAddress) external view returns (bool);

    /// @dev Determines if the specified address has permission to update config on the Token Contract
    /// @param potentialAddress Address to check
    function isTokenAdmin(address potentialAddress) external view returns (bool);

    /// @dev Determines if the specified address has permission to trigger restaking of native ETH
    /// @param potentialAddress Address to check
    function isNativeEthRestakeAdmin(address potentialAddress) external view returns (bool);

    /// @dev Determines if the specified address has permission to sweep and deposit ERC20 Rewards
    /// @param potentialAddress Address to check
    function isERC20RewardsAdmin(address potentialAddress) external view returns (bool);

    /// @dev Determines if the specified address has permission to pause deposits and withdraws
    /// @param potentialAddress Address to check
    function isDepositWithdrawPauser(address potentialAddress) external view returns (bool);

    /// @dev Determines if the specified address has permission to set whitelisted origin in xRenzoBridge
    /// @param potentialAddress Address to check
    function isBridgeAdmin(address potentialAddress) external view returns (bool);

    /// @dev Determined if the specified address has permission to send price feed of ezETH to L2
    /// @param potentialAddress Address to check
    function isPriceFeedSender(address potentialAddress) external view returns (bool);

    /// @dev Determine if the specified address haas permission to update Withdraw Queue params
    /// @param potentialAddress Address to check
    function isWithdrawQueueAdmin(address potentialAddress) external view returns (bool);

    /// @dev Determine if the specified address has permission to track emergency pending queued withdrawals
    /// @param potentialAddress Address to check
    function isEmergencyWithdrawTrackingAdmin(
        address potentialAddress
    ) external view returns (bool);

    /// @dev Determine if the specified address has permission to process EigenLayer rewards
    /// @param potentialAddress Address to check
    function isEigenLayerRewardsAdmin(address potentialAddress) external view returns (bool);

    /// @dev Determine if the specified address has permission to track missed Checkpoints Exit Balance
    /// @param potentialAddress Address to check
    function isEmergencyCheckpointTrackingAdmin(
        address potentialAddress
    ) external view returns (bool);

    /// @dev Determine if the specified address has permission to track AVS ETH slashing amount
    /// @param potentialAddress Address to check
    function isEmergencyTrackAVSEthSlashingAdmin(
        address potentialAddress
    ) external view returns (bool);

    /// @dev Determine if the specified address has permission to rebalance the withdraw queue
    /// @param potentialAddress Address to check
    function isWithdrawQueueRebalanceAdmin(address potentialAddress) external view returns (bool);
}
