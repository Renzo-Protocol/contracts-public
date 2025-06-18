// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../IRestakeManager.sol";
import "../xERC20/interfaces/IXERC20Lockbox.sol";
import { IRateProvider } from "../../RateProvider/IRateProvider.sol";
import { IRoleManager } from "../../Permissions/IRoleManager.sol";

abstract contract xRenzoBridgeReceiverStorageV1 {
    /// @notice The xezETH token address
    IERC20 public xezETH;

    /// @notice The ezETH token address
    IERC20 public ezETH;

    /// @notice The RestakeManager contract - deposits into the protocol are restaked here
    IRestakeManager public restakeManager;

    /// @notice The wETH token address - will be sent via bridge from L2
    IERC20 public wETH;

    /// @notice The wstETH token address - will be sent via bridge from L2
    IERC20 public wstETH;

    /// @notice The stETH token address - will be received when unwrapping wstETH
    IERC20 public stETH;

    /// @notice The lockbox contract for ezETH - minted ezETH is sent here
    IXERC20Lockbox public xezETHLockbox;

    /// @notice The address of Renzo RoleManager contract
    IRoleManager public roleManager;
}
