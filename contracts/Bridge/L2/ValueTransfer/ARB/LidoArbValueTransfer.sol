// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IValueTransferBridge, Quotes } from "../IValueTransferBridge.sol";
import { ITokenGateway } from "./Interfaces/ITokenGateway.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../../Errors/Errors.sol";

/**
 * @author  Renzo
 * @title   LidoOPValueTransfer
 * @dev     Transfers wstETH tokens to mainnet via the standard Lido bridge
 * @notice  Quotes are not supported
 */
contract LidoArbValueTransfer is IValueTransferBridge {
    using SafeERC20 for IERC20;

    /// @dev Event to track bridged value
    event ValueBridged(address indexed to, address token, uint256 amount);

    ITokenGateway public immutable gateWayRouter; // 0x5288c571Fd7aD117beA99bF60FE0846C4E84F933 on Arb
    IERC20 public immutable wstETH; // 0x5979D7b546E38E414F7E9822514be443A4800529 on Arb
    address public immutable l1wstETH; // 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0 on mainnet
    address public immutable l1xRenzoBridge; // Destination for all tokens bridged

    constructor(
        ITokenGateway _gateWayRouter,
        IERC20 _wstETH,
        address _l1xRenzoBridge,
        address _l1wstETH
    ) {
        // Verify addresses are not 0
        if (
            address(_gateWayRouter) == address(0) ||
            address(_wstETH) == address(0) ||
            _l1xRenzoBridge == address(0) ||
            _l1wstETH == address(0)
        ) revert InvalidZeroInput();

        gateWayRouter = _gateWayRouter;
        wstETH = _wstETH;
        l1xRenzoBridge = _l1xRenzoBridge;
        l1wstETH = _l1wstETH;
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
     * @notice  Transfers wstETH tokens to mainnet via the standard Lido bridge
     * @dev     .
     * @param   .
     * @param   token   should always be wsteth
     * @param   amount  amount to send
     * @return  transferId  always 0
     */
    function transferRemote(
        uint32 /*destinationDomain - always mainnet*/,
        address /*recipient - awlays destination contract*/,
        address token,
        uint256 amount
    ) external payable returns (bytes32 transferId) {
        // Do not allow ETH
        if (msg.value != 0) revert UnsupportedWithdrawAsset();

        // Verify the token is wstETH
        if (token != address(wstETH)) revert InvalidTokenReceived();

        // Pull the token in
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        bytes memory extraData;
        gateWayRouter.outboundTransfer(l1wstETH, l1xRenzoBridge, amount, 0, 0, extraData);

        emit ValueBridged(l1xRenzoBridge, token, amount);

        return 0;
    }
}
