// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IValueTransferBridge, Quotes } from "../IValueTransferBridge.sol";
import { ArbSys } from "./Interfaces/ArbSys.sol";
import "../../../../Errors/Errors.sol";

/**
 * @author  Renzo
 * @title   EthArbValueTransfer
 * @dev     Transfers ETH to mainnet via the standard bridge
 * @notice  Quotes are not supported
 */
contract EthArbValueTransfer is IValueTransferBridge {
    /// @dev Event to track bridged value
    event ValueBridged(address indexed to, address token, uint256 amount);

    /// @dev Address of the native token used in events
    address public constant ETH_NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev Address of the l2 standard bridge on the L2 used to send ETH
    ArbSys public immutable arbSys; // 0x0000000000000000000000000000000000000064 on Arb mainnet
    /// @dev Address of the xRenzo bridge on the L1 used to receive ETH
    address public immutable l1xRenzoBridge; // Destination where all ETH is bridged

    constructor(ArbSys _arbSys, address _l1xRenzoBridge) {
        // Verify addresses are not 0
        if (address(_arbSys) == address(0) || _l1xRenzoBridge == address(0))
            revert InvalidZeroInput();

        arbSys = _arbSys;
        l1xRenzoBridge = _l1xRenzoBridge;
    }

    /**
     * @notice  Quotes not supported as all tokens are transferred at 1:1
     * @dev     .
     * @return  Quotes[]  .
     */
    function quoteTransferRemote(
        uint32 /*destinationDomain*/,
        bytes32 /*recipient*/,
        uint256 /*amountOut*/
    ) external pure returns (Quotes[] memory) {
        return new Quotes[](0);
    }

    /**
     * @notice  Transfers ETH to mainnet via the standard bridge
     * @dev     .
     * @param   .
     * @param   .   should always be ETH
     * @param   .  amount to send
     * @return  transferId  always 0
     */
    function transferRemote(
        uint32 /*destinationDomain - always mainnet*/,
        address /*recipient - awlays destination contract*/,
        address /*token - awlays ETH*/,
        uint256 /*amount - always full amount*/
    ) external payable returns (bytes32 transferId) {
        if (msg.value == 0) revert UnsupportedWithdrawAsset();

        // Trigger the bridge
        arbSys.withdrawEth{ value: msg.value }(l1xRenzoBridge);

        emit ValueBridged(l1xRenzoBridge, ETH_NATIVE_TOKEN_ADDRESS, msg.value);
        return 0;
    }
}
