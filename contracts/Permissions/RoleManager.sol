// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./IRoleManager.sol";
import "./RoleManagerStorage.sol";
import "../Errors/Errors.sol";

/// @title RoleManager
/// @dev This contract will track the roles and permissions in the protocol
/// Note: This contract is protected via a permissioned account set via the initializer.  Caution should
/// be used as the owner could renounce the role leaving all future actions disabled.  Additionally,
/// if a malicious account was able to obtain the role, they could use it to grant permissions to malicious accounts.
contract RoleManager is IRoleManager, AccessControlUpgradeable, RoleManagerStorageV2 {
    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev initializer to call after deployment, can only be called once
    function initialize(address roleManagerAdmin) public initializer {
        if (address(roleManagerAdmin) == address(0x0)) revert InvalidZeroInput();

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, roleManagerAdmin);
    }

    /// @dev Determines if the specified address has permissions to manage RoleManager
    /// @param potentialAddress Address to check
    function isRoleManagerAdmin(address potentialAddress) external view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to mint or burn ezETH tokens
    /// @param potentialAddress Address to check
    function isEzETHMinterBurner(address potentialAddress) external view returns (bool) {
        return hasRole(RX_ETH_MINTER_BURNER, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to update config on the OperatorDelgator Contracts
    /// @param potentialAddress Address to check
    function isOperatorDelegatorAdmin(address potentialAddress) external view returns (bool) {
        return hasRole(OPERATOR_DELEGATOR_ADMIN, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to update config on the Oracle Contract config
    /// @param potentialAddress Address to check
    function isOracleAdmin(address potentialAddress) external view returns (bool) {
        return hasRole(ORACLE_ADMIN, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to update config on the RestakeManager Contract config
    /// @param potentialAddress Address to check
    function isRestakeManagerAdmin(address potentialAddress) external view returns (bool) {
        return hasRole(RESTAKE_MANAGER_ADMIN, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to update config on the Token Contract
    /// @param potentialAddress Address to check
    function isTokenAdmin(address potentialAddress) external view returns (bool) {
        return hasRole(TOKEN_ADMIN, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to trigger restaking of native ETH
    /// @param potentialAddress Address to check
    function isNativeEthRestakeAdmin(address potentialAddress) external view returns (bool) {
        return hasRole(NATIVE_ETH_RESTAKE_ADMIN, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to sweep and deposit ERC20 Rewards
    /// @param potentialAddress Address to check
    function isERC20RewardsAdmin(address potentialAddress) external view returns (bool) {
        return hasRole(ERC20_REWARD_ADMIN, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to pause deposits and withdraws
    /// @param potentialAddress Address to check
    function isDepositWithdrawPauser(address potentialAddress) external view returns (bool) {
        return hasRole(DEPOSIT_WITHDRAW_PAUSER, potentialAddress);
    }

    /// @dev Determines if the specified address has permission to set whitelisted origin in xRenzoBridge
    /// @param potentialAddress Address to check
    function isBridgeAdmin(address potentialAddress) external view returns (bool) {
        return hasRole(BRIDGE_ADMIN, potentialAddress);
    }

    /// @dev Determined if the specified address has permission to send price feed of ezETH to L2
    /// @param potentialAddress Address to check
    function isPriceFeedSender(address potentialAddress) external view returns (bool) {
        return hasRole(PRICE_FEED_SENDER, potentialAddress);
    }
}
