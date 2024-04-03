// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./WBETHShimStorage.sol";
import "../../Errors/Errors.sol";

/**
 * @title   WBETHShim
 * @dev     The contract hard codes the decimals to 18 decimals and returns the conversion rate of 1 mETH to ETH underlying the token in the wBETH protocol
 * @notice  This contract is a shim that implements the Chainlink AggregatorV3Interface and returns pricing from the wBETH token contract
 */

contract WBETHShim is Initializable, WBETHShimStorageV1 {
    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract with initial vars
    function initialize(IStakedTokenV2 _wBETHToken) public initializer {
        if (address(_wBETHToken) == address(0x0)) revert InvalidZeroInput();

        wBETHToken = _wBETHToken;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function description() external pure returns (string memory) {
        return "wBETH Chainlink Shim";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    /// @dev Historical data not available
    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert NotImplemented();
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return _getWBETHData();
    }

    /**
     * @notice  This function gets the price of 1 mETH in ETH from the mETH staking contract with 18 decimal precision
     * @dev     This function does not implement the full Chainlink AggregatorV3Interface
     * @return  roundId  0 - never returns valid round ID
     * @return  answer  The conversion rate of 1 mETH to ETH.
     * @return  startedAt  0 - never returns valid timestamp
     * @return  updatedAt  The current timestamp.
     * @return  answeredInRound  0 - never returns valid round ID
     */
    function _getWBETHData()
        internal
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, int256(wBETHToken.exchangeRate()), 0, block.timestamp, 0);
    }
}
