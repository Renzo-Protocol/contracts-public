// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./DepositQueueStorage.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../Errors/Errors.sol";

contract DepositQueue is Initializable, ReentrancyGuardUpgradeable, DepositQueueStorageV1 {
    using SafeERC20 for IERC20;

    event RewardsDeposited(IERC20 token, uint256 amount);

    event FeeConfigUpdated(address feeAddress, uint256 feeBasisPoints);

    event RestakeManagerUpdated(IRestakeManager restakeManager);

    event ETHDepositedFromProtocol(uint256 amount);

    event ETHStakedFromQueue(
        IOperatorDelegator operatorDelegator,
        bytes pubkey,
        uint256 amountStaked,
        uint256 amountQueued
    );

    event ProtocolFeesPaid(IERC20 token, uint256 amount, address destination);

    event GasRefunded(address admin, uint256 gasRefunded);

    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyRestakeManagerAdmin() {
        if (!roleManager.isRestakeManagerAdmin(msg.sender)) revert NotRestakeManagerAdmin();
        _;
    }

    /// @dev Allows only the RestakeManager address to call functions
    modifier onlyRestakeManager() {
        if (msg.sender != address(restakeManager)) revert NotRestakeManager();
        _;
    }

    /// @dev Allows only a whitelisted address to trigger native ETH staking
    modifier onlyNativeEthRestakeAdmin() {
        if (!roleManager.isNativeEthRestakeAdmin(msg.sender)) revert NotNativeEthRestakeAdmin();
        _;
    }

    /// @dev Allows only a whitelisted address to trigger ERC20 rewards sweeping
    modifier onlyERC20RewardsAdmin() {
        if (!roleManager.isERC20RewardsAdmin(msg.sender)) revert NotERC20RewardsAdmin();
        _;
    }

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract with initial vars
    function initialize(IRoleManager _roleManager) public initializer {
        __ReentrancyGuard_init();

        if (address(_roleManager) == address(0x0)) revert InvalidZeroInput();

        roleManager = _roleManager;
    }

    /// @dev Sets the config for fees - if either value is set to 0 then fees are disabled
    function setFeeConfig(
        address _feeAddress,
        uint256 _feeBasisPoints
    ) external onlyRestakeManagerAdmin {
        // Verify address is set if basis points are non-zero
        if (_feeBasisPoints > 0) {
            if (_feeAddress == address(0x0)) revert InvalidZeroInput();
        }

        // Verify basis points are not over 100%
        if (_feeBasisPoints > 10000) revert OverMaxBasisPoints();

        feeAddress = _feeAddress;
        feeBasisPoints = _feeBasisPoints;

        emit FeeConfigUpdated(_feeAddress, _feeBasisPoints);
    }

    /// @dev Sets the address of the RestakeManager contract
    function setRestakeManager(IRestakeManager _restakeManager) external onlyRestakeManagerAdmin {
        if (address(_restakeManager) == address(0x0)) revert InvalidZeroInput();

        restakeManager = _restakeManager;

        emit RestakeManagerUpdated(_restakeManager);
    }

    /// @dev Handle ETH sent to the protocol through the RestakeManager - e.g. user deposits
    /// ETH will be stored here until used for a validator deposit
    function depositETHFromProtocol() external payable onlyRestakeManager {
        emit ETHDepositedFromProtocol(msg.value);
    }

    /// @dev Handle ETH sent to this contract from outside the protocol - e.g. rewards
    /// ETH will be stored here until used for a validator deposit
    /// This should receive ETH from scenarios like Execution Layer Rewards and MEV from native staking
    /// Users should NOT send ETH directly to this contract unless they want to donate to existing ezETH holders
    receive() external payable nonReentrant {
        uint256 feeAmount = 0;
        // Take protocol cut of rewards if enabled
        if (feeAddress != address(0x0) && feeBasisPoints > 0) {
            feeAmount = (msg.value * feeBasisPoints) / 10000;
            (bool success, ) = feeAddress.call{ value: feeAmount }("");
            if (!success) revert TransferFailed();

            emit ProtocolFeesPaid(IERC20(address(0x0)), feeAmount, feeAddress);
        }

        // Add to the total earned
        totalEarned[address(0x0)] = totalEarned[address(0x0)] + msg.value - feeAmount;

        // Emit the rewards event
        emit RewardsDeposited(IERC20(address(0x0)), msg.value - feeAmount);
    }

    /// @dev Function called by ETH Restake Admin to start the restaking process in Native ETH
    /// Only callable by a permissioned account
    function stakeEthFromQueue(
        IOperatorDelegator operatorDelegator,
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external onlyNativeEthRestakeAdmin {
        uint256 gasBefore = gasleft();
        // Send the ETH and the params through to the restake manager
        restakeManager.stakeEthInOperatorDelegator{ value: 32 ether }(
            operatorDelegator,
            pubkey,
            signature,
            depositDataRoot
        );

        emit ETHStakedFromQueue(operatorDelegator, pubkey, 32 ether, address(this).balance);

        // Refund the gas to the Admin address if enough ETH available
        _refundGas(gasBefore);
    }

    /// @dev Function called by ETH Restake Admin to start the restaking process in Native ETH
    /// Only callable by a permissioned account
    /// Can stake multiple validators with 1 tx
    function stakeEthFromQueueMulti(
        IOperatorDelegator[] calldata operatorDelegators,
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        bytes32[] calldata depositDataRoots
    ) external onlyNativeEthRestakeAdmin nonReentrant {
        uint256 gasBefore = gasleft();
        // Verify all arrays are the same length
        if (
            operatorDelegators.length != pubkeys.length ||
            operatorDelegators.length != signatures.length ||
            operatorDelegators.length != depositDataRoots.length
        ) revert MismatchedArrayLengths();

        // Iterate through the arrays and stake each one
        uint256 arrayLength = operatorDelegators.length;
        for (uint256 i = 0; i < arrayLength; ) {
            // Send the ETH and the params through to the restake manager
            restakeManager.stakeEthInOperatorDelegator{ value: 32 ether }(
                operatorDelegators[i],
                pubkeys[i],
                signatures[i],
                depositDataRoots[i]
            );

            emit ETHStakedFromQueue(
                operatorDelegators[i],
                pubkeys[i],
                32 ether,
                address(this).balance
            );

            unchecked {
                ++i;
            }
        }

        // Refund the gas to the Admin address if enough ETH available
        _refundGas(gasBefore);
    }

    /// @dev Sweeps any accumulated ERC20 tokens in this contract to the RestakeManager
    /// Only callable by a permissioned account
    function sweepERC20(IERC20 token) external onlyERC20RewardsAdmin {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            uint256 feeAmount = 0;

            // Sweep fees if configured
            if (feeAddress != address(0x0) && feeBasisPoints > 0) {
                feeAmount = (balance * feeBasisPoints) / 10000;
                IERC20(token).safeTransfer(feeAddress, feeAmount);

                emit ProtocolFeesPaid(token, feeAmount, feeAddress);
            }

            // Approve and deposit the rewards
            token.approve(address(restakeManager), balance - feeAmount);
            restakeManager.depositTokenRewardsFromProtocol(token, balance - feeAmount);

            // Add to the total earned
            totalEarned[address(token)] = totalEarned[address(token)] + balance - feeAmount;

            // Emit the rewards event
            emit RewardsDeposited(IERC20(address(token)), balance - feeAmount);
        }
    }

    /**
     * @notice Internal function used to refund gas to admin accounts if enough balance
     * @param initialGas Initial Gas available
     */
    function _refundGas(uint256 initialGas) internal {
        uint256 gasUsed = (initialGas - gasleft()) * tx.gasprice;
        uint256 gasRefund = address(this).balance >= gasUsed ? gasUsed : address(this).balance;
        (bool success, ) = payable(msg.sender).call{ value: gasRefund }("");
        if (!success) revert TransferFailed();
        emit GasRefunded(msg.sender, gasRefund);
    }
}
