// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

abstract contract PaymentSplitterStorageV1 {
    /// @dev the address to send funds once recipients are paid
    address public fallbackPaymentAddress;

    /// @dev tracks the total amount paid out to specific addresses
    mapping(address => uint256) public totalAmountPaid;

    /// @dev tracks the amount owed to specific addresses
    mapping(address => uint256) public amountOwed;

    /// @dev list of addresses to pay out for iteration
    address[] public recipients;
}
