// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./RewardHandlerStorage.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../Errors/Errors.sol";

/**
 * @author  Renzo Protocol
 * @title   RewardHandler
 * @dev     Handles native ETH rewards deposited on the execution layer from validator nodes.  Forwards them
 * to the DepositQueue contract for restaking.
 * @notice  .
 */
contract RewardHandler is Initializable, ReentrancyGuardUpgradeable, RewardHandlerStorageV1 {
    /// @dev Allows only a whitelisted address to trigger native ETH staking
    modifier onlyNativeEthRestakeAdmin() {
        if (!roleManager.isNativeEthRestakeAdmin(msg.sender)) revert NotNativeEthRestakeAdmin();
        _;
    }

    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyRestakeManagerAdmin() {
        if (!roleManager.isRestakeManagerAdmin(msg.sender)) revert NotRestakeManagerAdmin();
        _;
    }

    event RewardDestinationUpdated(address rewardDestination);

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract with initial vars
    function initialize(IRoleManager _roleManager, address _rewardDestination) public initializer {
        __ReentrancyGuard_init();

        if (address(_roleManager) == address(0x0)) revert InvalidZeroInput();
        if (address(_rewardDestination) == address(0x0)) revert InvalidZeroInput();

        roleManager = _roleManager;
        rewardDestination = _rewardDestination;

        emit RewardDestinationUpdated(_rewardDestination);
    }

    /// @dev Forwards all native ETH rewards to the DepositQueue contract
    /// Handle ETH sent to this contract from outside the protocol that trigger contract execution - e.g. rewards
    receive() external payable nonReentrant {
        _forwardETH();
    }

    /// @dev Forwards all native ETH rewards to the DepositQueue contract
    /// Handle ETH sent to this contract from validator nodes that do not trigger contract execution - e.g. rewards
    function forwardRewards() external nonReentrant onlyNativeEthRestakeAdmin {
        _forwardETH();
    }

    function _forwardETH() internal {
        uint256 balance = address(this).balance;
        if (balance == 0) {
            return;
        }

        (bool success, ) = rewardDestination.call{ value: balance }("");
        if (!success) revert TransferFailed();
    }

    function setRewardDestination(
        address _rewardDestination
    ) external nonReentrant onlyRestakeManagerAdmin {
        if (address(_rewardDestination) == address(0x0)) revert InvalidZeroInput();

        rewardDestination = _rewardDestination;

        emit RewardDestinationUpdated(_rewardDestination);
    }
}
