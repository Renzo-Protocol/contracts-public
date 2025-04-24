// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {
    InstantWithdrawerStorageV1,
    IRestakeManager,
    IWithdrawQueue
} from "./InstantWithdrawerStorage.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../Errors/Errors.sol";

/**
 * @author  Renzo
 * @title   InstantWithdrawer
 * @dev     Allows a user to instantly withdraw from the withdraw queue by paying a fee.
 * @notice  Fees are collected and sent to feeDestination.  Fees increase through a range, the lower the withdraw queue buffer gets.
 */

contract InstantWithdrawer is
    Initializable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    InstantWithdrawerStorageV1
{
    using SafeERC20 for IERC20;

    event WithdrawCompleted(
        address user,
        uint256 ezEthAmount,
        address redeemToken,
        uint256 redeemAmount,
        uint256 feeAmount
    );

    IWithdrawQueue public immutable withdrawalQueue;
    IERC20 public immutable ezETH;

    /// @notice Equivalent to 100%, but in basis points.
    uint16 internal constant ONE_HUNDRED_IN_BIPS = 10_000;

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IWithdrawQueue _withdrawalQueue, IERC20 _ezETH) {
        _disableInitializers();

        if (_withdrawalQueue == IWithdrawQueue(address(0)) || _ezETH == IERC20(address(0))) {
            revert InvalidZeroInput();
        }

        withdrawalQueue = _withdrawalQueue;
        ezETH = _ezETH;
    }

    /**
     * @notice  Initializer for InstantWithdrawer
     * @dev     .
     * @param   _allowedBufferDrawdownBps  Max allowed level this contract can reduce the buffer to.  Can not be zero.
     * @param   _feeDestination  Where fees are sent.  Can not be zero.
     * @param   _minFeeBps  Min amount of fees to collect. Can be zero.
     * @param   _maxFeeBps  Max amount of fees to collect. Must be >= min.
     */
    function initialize(
        uint256 _allowedBufferDrawdownBps,
        address _feeDestination,
        uint256 _minFeeBps,
        uint256 _maxFeeBps
    ) public initializer {
        // Initialize inherited classes
        __Ownable_init();
        __ReentrancyGuard_init();

        if (_allowedBufferDrawdownBps == 0 || _feeDestination == address(0)) {
            revert InvalidZeroInput();
        }

        if (
            _allowedBufferDrawdownBps > ONE_HUNDRED_IN_BIPS ||
            _minFeeBps > ONE_HUNDRED_IN_BIPS ||
            _maxFeeBps > ONE_HUNDRED_IN_BIPS
        ) {
            revert OverMaxBasisPoints();
        }

        if (_maxFeeBps < _minFeeBps) {
            revert OverMaxBasisPoints();
        }

        allowedBufferDrawdownBps = _allowedBufferDrawdownBps;
        feeDestination = _feeDestination;
        minFeeBps = _minFeeBps;
        maxFeeBps = _maxFeeBps;
    }

    /**
     * @notice  Allows a user to withdraw their ezETH from the protocol instantly
     * @dev     If the buffer doesn't have sufficient capital, this call will fail.
     *          Fees are collected and sent to feeDestination from withdrawn value.
     * @param   _ezEthAmount  Amount of ezETH to redeem
     * @param   _redeemToken  Asset to withdraw from the protocol.  Use IS_NATIVE address to redeem native ETH.
     * @param   _minOut  Minimum amount of _redeemToken to receive - protects against front running from fees
     */
    function withdraw(
        uint256 _ezEthAmount,
        address _redeemToken,
        uint256 _minOut
    ) external nonReentrant {
        if (_ezEthAmount == 0 || _redeemToken == address(0)) {
            revert InvalidZeroInput();
        }

        // Transfer in the ezETH
        ezETH.safeTransferFrom(msg.sender, address(this), _ezEthAmount);

        // Get buffer details
        (uint256 bufferCapacity, uint256 bufferAvailable, uint256 drawDownLimit) = getBufferDetails(
            _redeemToken
        );

        // Explicitly revert if buffer capacity is 0 - not supported
        if (bufferCapacity == 0) revert UnsupportedWithdrawAsset();

        // Calculate how much would be redeemed
        (, uint256 redeemAmount) = withdrawalQueue.calculateAmountToRedeem(
            _ezEthAmount,
            _redeemToken
        );

        // Check the buffer capacity has enough to instantly redeem
        if (redeemAmount > bufferAvailable) {
            revert NotEnoughWithdrawBuffer();
        }

        // Check the buffer capacity is not below the draw down limit
        uint256 bufferAfterWithdraw = bufferAvailable - redeemAmount;
        if (bufferAfterWithdraw < drawDownLimit) {
            revert BelowAllowedLimit();
        }

        // Calculate fee percentage - between min and max depending on where the queue would end up
        uint256 feeBps = getFeeBasisPoints(bufferCapacity, drawDownLimit, bufferAfterWithdraw);

        // Start the Withdraw
        ezETH.safeIncreaseAllowance(address(withdrawalQueue), _ezEthAmount);
        withdrawalQueue.withdraw(_ezEthAmount, _redeemToken);

        // Track the balance before claiming
        uint256 balanceBefore;
        if (_redeemToken == IS_NATIVE) {
            // Track ETH balance
            balanceBefore = address(this).balance;
        } else {
            // Track token balance
            balanceBefore = IERC20(_redeemToken).balanceOf(address(this));
        }

        // Claim the withdraw - assumes the latest withdraw in the list is from this last request - subtract one to get index
        uint256 withdrawIndex = withdrawalQueue.getOutstandingWithdrawRequests(address(this)) - 1;
        withdrawalQueue.claim(withdrawIndex, address(this));

        // Calculate how much was received
        uint256 amountReceived;
        if (_redeemToken == IS_NATIVE) {
            // Get the amount of ETH received
            amountReceived = address(this).balance - balanceBefore;
        } else {
            // Get the amount of tokens received
            amountReceived = IERC20(_redeemToken).balanceOf(address(this)) - balanceBefore;
        }

        // Calculate the fee amount
        uint256 feeAmount = (amountReceived * feeBps) / ONE_HUNDRED_IN_BIPS;

        // Ensure minout is received
        if (amountReceived - feeAmount < _minOut) {
            revert InsufficientOutputAmount();
        }

        // Send funds out
        if (_redeemToken == IS_NATIVE) {
            // Send the fee to the fee destination
            (bool success, ) = feeDestination.call{ value: feeAmount }("");
            if (!success) {
                revert TransferFailed();
            }

            // Send the rest to the user
            (success, ) = msg.sender.call{ value: amountReceived - feeAmount }("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            // Send the fee to the fee destination
            IERC20(_redeemToken).safeTransfer(feeDestination, feeAmount);

            // Send the rest to the user
            IERC20(_redeemToken).safeTransfer(msg.sender, amountReceived - feeAmount);
        }

        // Emit event
        emit WithdrawCompleted(msg.sender, _ezEthAmount, _redeemToken, redeemAmount, feeAmount);
    }

    /**
     * @notice  Gets info about the buffer state
     * @dev     .
     * @param   _redeemToken  .
     * @return  bufferCapacity  Total target size of the buffer
     * @return  bufferAvailable  Amount currently available in the buffer that can be withdrawn
     * @return  drawDownLimit  Min level the buffer can be reduced to, enforced with allowedBufferDrawdownBps
     */
    function getBufferDetails(
        address _redeemToken
    ) public view returns (uint256 bufferCapacity, uint256 bufferAvailable, uint256 drawDownLimit) {
        bufferCapacity = withdrawalQueue.withdrawalBufferTarget(_redeemToken);
        bufferAvailable = withdrawalQueue.getAvailableToWithdraw(_redeemToken);
        drawDownLimit = (bufferCapacity * allowedBufferDrawdownBps) / ONE_HUNDRED_IN_BIPS;
    }

    /**
     * @notice  Gets the fee basis points for a withdrawal.  Fees are scaled from min to max fee depending on the percentage
     *             of the buffer capacity that would be left after the withdrawal.
     * @dev     .
     * @param   bufferCapacity  Total target size of the buffer
     * @param   drawDownLimit  Min level the buffer can be reduced to, enforced with allowedBufferDrawdownBps
     * @param   bufferAfterWithdraw  Amount available in the buffer after the withdrawal would be completed
     * @return  feeBps  Fee percentage in basis points
     */
    function getFeeBasisPoints(
        uint256 bufferCapacity,
        uint256 drawDownLimit,
        uint256 bufferAfterWithdraw
    ) public view returns (uint256 feeBps) {
        // Calculate the percent of the remaining buffer capacity after the withdrawal
        uint256 remainingCapacityBps = (ONE_HUNDRED_IN_BIPS *
            (bufferAfterWithdraw - drawDownLimit)) / (bufferCapacity - drawDownLimit);

        // Fee is the min plus percentage between the two limits
        if (remainingCapacityBps > ONE_HUNDRED_IN_BIPS) {
            // Note: If remaining buffer is overfilled - return min fee
            return minFeeBps;
        } else {
            return
                minFeeBps +
                ((maxFeeBps - minFeeBps) * (ONE_HUNDRED_IN_BIPS - remainingCapacityBps)) /
                ONE_HUNDRED_IN_BIPS;
        }
    }

    /**
     * @notice  Setter for _allowedBufferDrawdownBps
     * @dev     Only Owner can call this function
     * @param   _allowedBufferDrawdownBps  Max allowed level this contract can reduce the buffer to.  Can not be zero.
     */
    function setAllowedBufferDrawdownBps(uint256 _allowedBufferDrawdownBps) external onlyOwner {
        if (_allowedBufferDrawdownBps == 0) {
            revert InvalidZeroInput();
        }

        if (_allowedBufferDrawdownBps > ONE_HUNDRED_IN_BIPS) {
            revert OverMaxBasisPoints();
        }

        allowedBufferDrawdownBps = _allowedBufferDrawdownBps;
    }

    /**
     * @notice  Setter for fee info
     * @dev     Only Owner can call this function
     * @param   _feeDestination  Where fees are sent.  Can not be zero.
     * @param   _minFeeBps  Min amount of fees to collect. Can be zero.
     * @param   _maxFeeBps  Max amount of fees to collect. Must be >= min.
     */
    function setFeeInfo(
        address _feeDestination,
        uint256 _minFeeBps,
        uint256 _maxFeeBps
    ) external onlyOwner {
        if (_feeDestination == address(0)) {
            revert InvalidZeroInput();
        }

        if (_minFeeBps > ONE_HUNDRED_IN_BIPS || _maxFeeBps > ONE_HUNDRED_IN_BIPS) {
            revert OverMaxBasisPoints();
        }

        if (_maxFeeBps < _minFeeBps) {
            revert OverMaxBasisPoints();
        }

        feeDestination = _feeDestination;
        minFeeBps = _minFeeBps;
        maxFeeBps = _maxFeeBps;
    }

    /// @dev Fallback to receive ETH from withdraw queue - users should never send ETH here
    receive() external payable {}
}
