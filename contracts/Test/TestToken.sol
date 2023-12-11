//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title TestErc20
/// @dev This contract implements the ERC20 standard and is used for unit testing purposes only
/// Anyone can mint tokens
contract TestErc20 is ERC20Upgradeable {
    uint8 private internalDecimals;

    /// @dev initializer to call after deployment, can only be called once
    function initialize(string memory name_, string memory symbol_)
        public
        initializer
    {
        __ERC20_init(name_, symbol_);
        internalDecimals = 18;
    }

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return internalDecimals;
    }

    function setDecimals(uint8 _decimalsToSet) public {
        internalDecimals = _decimalsToSet;
    }
}
