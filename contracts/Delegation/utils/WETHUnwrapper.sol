// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../../Bridge/Connext/core/IWeth.sol";
import "../../Permissions/IRoleManager.sol";
import "../../Errors/Errors.sol";

// Note: Deprecated, not using anymore after PEPE upgrade
contract WETHUnwrapper is Initializable {
    using SafeERC20 for IERC20;

    IWeth constant WETH = IWeth(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    constructor() {
        _disableInitializers();
    }

    function unwrapWETH(uint256 amount) external {
        // transfer WETH from caller to this contract
        IERC20(address(WETH)).safeTransferFrom(msg.sender, address(this), amount);

        // unwrap WETH to ETH
        WETH.withdraw(amount);

        // transfer unwrapped WETH to caller
        (bool success, ) = msg.sender.call{ value: amount }("");
        if (!success) revert TransferFailed();
    }

    receive() external payable {
        // only accept ETH from WETH
        if (msg.sender != address(WETH)) revert UnAuthorisedCall();
    }
}
