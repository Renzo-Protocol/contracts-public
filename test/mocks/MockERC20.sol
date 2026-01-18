// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @notice A mock ERC20 token for testing purposes
 * @dev Includes mint and burn functions for test flexibility
 */
contract MockERC20 is ERC20, Ownable {
    uint8 private _customDecimals;

    /**
     * @notice Constructor
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param decimals_ Number of decimals
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _customDecimals = decimals_;
    }

    /**
     * @notice Returns the number of decimals
     */
    function decimals() public view virtual override returns (uint8) {
        return _customDecimals;
    }

    /**
     * @notice Mint tokens to an address
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from an address
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    /**
     * @notice Set custom decimals (for testing edge cases)
     * @param newDecimals New decimals value
     */
    function setDecimals(uint8 newDecimals) external onlyOwner {
        _customDecimals = newDecimals;
    }
}
