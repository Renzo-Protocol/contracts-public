// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

struct Quotes {
    address token; // address(0) for the native token
    uint256 amount;
}

interface IValueTransferBridge {
    function quoteTransferRemote(
        uint32 destinationDomain,
        bytes32 recipient,
        uint256 amountOut
    ) external returns (Quotes[] memory);

    function transferRemote(
        uint32 destinationDomain,
        address recipient,
        address token,
        uint256 amount
    ) external payable returns (bytes32 transferId);
}
