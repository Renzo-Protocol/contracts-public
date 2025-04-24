// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IOPStandardBridge {
    /// @notice Sends ETH to a receiver's address on the other chain. Note that if ETH is sent to a
    ///         smart contract and the call fails, the ETH will be temporarily locked in the
    ///         StandardBridge on the other chain until the call is replayed. If the call cannot be
    ///         replayed with any amount of gas (call always reverts), then the ETH will be
    ///         permanently locked in the StandardBridge on the other chain. ETH will also
    ///         be locked if the receiver is the other bridge, because finalizeBridgeETH will revert
    ///         in that case.
    /// @param _to          Address of the receiver.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeETHTo(
        address _to,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external payable;
}
