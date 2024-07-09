// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./PaymentSplitterStorage.sol";
import "../Errors/Errors.sol";

/**
 * @author  Renzo Protocol
 * @title   PaymentSplitter
 * @dev     Handles native ETH payments to be split among recipients.
 *          A list of payment addresses and their corresponding amount to be paid out are tracked.
 *          As ETH payments come in, they are split among the recipients until the amount to be paid is completed.
 *          After all recipients are paid, any new ETH is sent to the fallback address.
 *          ERC20 tokens are simply forwarded to the fallback address and can be triggered by any address.
 * @notice  .
 */
contract PaymentSplitter is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PaymentSplitterStorageV1
{
    using SafeERC20 for IERC20;

    event RecipientAdded(address recipient, uint256 amountOwed);
    event RecipientRemoved(address recipient, uint256 amountOwed);
    event RecipientAmountIncreased(address recipient, uint256 amountOwed, uint256 increaseAmount);
    event RecipientAmountDecreased(address recipient, uint256 amountOwed, uint256 decreaseAmount);
    event RecipientPaid(address recipient, uint256 amountPaid, bool success);

    uint256 private constant DUST_AMOUNT = 1_000_000 gwei;

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice  Initializes the contract with initial vars
     * @dev     Contract init
     * @param   _fallbackPaymentAddress  The address where all funds will be sent after recipients are fully paid
     */
    function initialize(address _fallbackPaymentAddress) public initializer {
        // Initialize inherited classes
        __Ownable_init();
        __ReentrancyGuard_init();

        fallbackPaymentAddress = _fallbackPaymentAddress;
    }

    /**
     * @notice  Recipient Length
     * @dev     view function for getting recipient length
     * @return  uint256  .
     */
    function getRecipientLength() public view returns (uint256) {
        return recipients.length;
    }

    /**
     * @notice  Forwards all ERC20 tokens to the fallback address
     * @dev     Can be called by any address
     *          If specified token balance is zero, reverts
     *          Note that this is just a convenience function to handle any ERC20 tokens accidentally sent to this address,
     *              and this is not expected to be used in normal operation
     * @param   token  IERC20 that was sent to this contract
     */
    function forwardERC20(IERC20 token) public {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) {
            revert InvalidTokenReceived();
        }

        token.safeTransfer(fallbackPaymentAddress, balance);
    }

    /**
     * @notice  Adds a recipient and amount owed to the list
     * @dev     Only callable by the owner
     *          Any new payments coming in should start to be forwarded to the new recipient after this call
     *          Cannot add the same recipient twice
     * @param   _recipient  Recipient address to add
     * @param   _initialAmountOwed  Initial amount owed to the recipient - can be set to 0
     */
    function addRecipient(address _recipient, uint256 _initialAmountOwed) public onlyOwner {
        // First iterate over the list to check to ensure the recipient is not already in the list
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == _recipient) {
                revert AlreadyAdded();
            }
        }

        // Push to the list and set the amount owed
        recipients.push(_recipient);
        amountOwed[_recipient] = _initialAmountOwed;

        // Emit the event
        emit RecipientAdded(_recipient, _initialAmountOwed);
    }

    /**
     * @notice  Removes a recipient from the list of payout addresses
     * @dev     Only callable by the owner
     *          Any new payments coming after this will not get forwarded to this recipient
     *          If the recipient is not in the list, reverts
     * @param   _recipient  Recipient address to remove
     */
    function removeRecipient(address _recipient) public onlyOwner {
        // First iterate over the list to check to ensure the recipient is in the list
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == _recipient) {
                emit RecipientRemoved(_recipient, amountOwed[_recipient]);

                // Remove the recipient from the list
                recipients[i] = recipients[recipients.length - 1];
                recipients.pop();
                delete amountOwed[_recipient];
                return;
            }
        }

        revert NotFound();
    }

    /**
     * @notice  Increases the amount owed to a recipient
     * @dev     Only callable by the owner
     *          If the recipient is not in the list, reverts
     * @param   _recipient  Recipient address to increase the amount owed
     * @param   _amount  Amount to add to outstanding balance owed
     */
    function addToRecipientAmountOwed(address _recipient, uint256 _amount) public onlyOwner {
        // Iterate over the recipient list to find the recipient
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == _recipient) {
                amountOwed[_recipient] += _amount;

                // Emit event
                emit RecipientAmountIncreased(_recipient, amountOwed[_recipient], _amount);

                return;
            }
        }

        revert NotFound();
    }

    /**
     * @notice  Decreases the amount owed to a recipient
     * @dev     Only callable by the owner
     *          If the recipient is not in the list, reverts
     *          If the amount to decrease is greater than the amount owed, sets amount owed to 0
     * @param   _recipient  Recipient address to decrease the amount owed
     * @param   _amount  Amount to subtract from the outstanding balance owed
     */
    function subtractFromRecipientAmountOwed(address _recipient, uint256 _amount) public onlyOwner {
        // Iterate over the recipient list to find the recipient
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == _recipient) {
                // Check for higher amount to decrease than amount owed
                if (_amount >= amountOwed[_recipient]) {
                    // Just set to 0 if the amount to decrease is greater than or equal to the amount owed
                    amountOwed[_recipient] = 0;
                } else {
                    // Subtract the amount from the amount owed
                    amountOwed[_recipient] -= _amount;
                }

                // Emit event
                emit RecipientAmountDecreased(_recipient, amountOwed[_recipient], _amount);

                return;
            }
        }

        revert NotFound();
    }

    /**
     * @notice  Pay out the recipients when ETH comes in
     * @dev     Any new payments coming in will be split among the recipients
     *          Allows dust to be sent to recipients, but not to fallback address
     *          Non Reentrant
     */
    receive() external payable nonReentrant {
        // Always use the balance of the address in case there was a rounding error or leftover amount from the last payout
        uint256 amountLeftToPay = address(this).balance;
        if (amountLeftToPay == 0) {
            return;
        }

        // Iterate over the recipients and pay them out
        for (uint256 i = 0; i < recipients.length; i++) {
            // First get the amount to pay this recipient based on the number of payment addresses left in the list
            uint256 amountToPay = amountLeftToPay / (recipients.length - i);

            // Check if the amount owed is less than the amount to pay
            if (amountOwed[recipients[i]] < amountToPay) {
                amountToPay = amountOwed[recipients[i]];
            }

            // Continue to the next one if the amount to pay is zero
            if (amountToPay == 0) {
                continue;
            }

            // Send the funds but ignore the return value to prevent others from not being paid
            (bool success, ) = recipients[i].call{ value: amountToPay }("");

            // If successful update the amount owed and the amount left to pay
            if (success) {
                // Subtract the amount sent to the amount owed
                amountOwed[recipients[i]] -= amountToPay;

                // Subtract the amount sent from the total amount left to pay to other addresses
                amountLeftToPay -= amountToPay;

                // Track the total paid out to this recipient
                totalAmountPaid[recipients[i]] += amountToPay;
            }

            // Emit event
            emit RecipientPaid(recipients[i], amountToPay, success);
        }

        // If there is any amount left to pay, send it to the fallback address
        // ignore dust amounts due to division rounding or small left over amounts - they will get sent the next time this function is called
        if (amountLeftToPay > DUST_AMOUNT) {
            // Send the funds but ignore the return value to prevent others from not being paid
            (bool success, ) = fallbackPaymentAddress.call{ value: amountLeftToPay }("");

            // If success, track the amount paid to the fallback
            if (success) {
                totalAmountPaid[fallbackPaymentAddress] += amountLeftToPay;
            }

            // Emit event
            emit RecipientPaid(fallbackPaymentAddress, amountLeftToPay, success);
        }
    }
}
