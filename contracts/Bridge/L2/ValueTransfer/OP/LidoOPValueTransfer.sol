// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IValueTransferBridge, Quotes } from "../IValueTransferBridge.sol";
import { IL2ERC20Bridge } from "./Interfaces/IL2ERC20Bridge.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../../Errors/Errors.sol";

/**
 * @author  Renzo
 * @title   LidoOPValueTransfer
 * @dev     Transfers wstETH tokens to mainnet via the standard Lido bridge
 * @notice  Quotes are not supported
 */
contract LidoOPValueTransfer is IValueTransferBridge {
    using SafeERC20 for IERC20;

    /// @dev Event to track bridged value
    event ValueBridged(address indexed to, address token, uint256 amount);

    IL2ERC20Bridge public immutable lidoBridge; // 0xac9D11cD4D7eF6e54F14643a393F68Ca014287AB Base
    IERC20 public immutable wstETH; // 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452 Base
    address public immutable l1xRenzoBridge; // Destination for all tokens bridged

    constructor(IL2ERC20Bridge _lidoBridge, IERC20 _wstETH, address _l1xRenzoBridge) {
        // Verify addresses are not 0
        if (
            address(_lidoBridge) == address(0) ||
            address(_wstETH) == address(0) ||
            _l1xRenzoBridge == address(0)
        ) revert InvalidZeroInput();

        lidoBridge = _lidoBridge;
        wstETH = _wstETH;
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

        // Pull the token in and then give the allowance
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).safeIncreaseAllowance(address(lidoBridge), amount);

        // TODO: Determine if we need to add extra data to track this tx
        bytes memory extraData;
        lidoBridge.withdrawTo(token, l1xRenzoBridge, amount, 100000, extraData);

        emit ValueBridged(l1xRenzoBridge, token, amount);

        return 0;
    }
}
