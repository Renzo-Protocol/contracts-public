// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "../../Errors/Errors.sol";

/**
 * @title   STETHShim
 * @dev     The contract hard codes the decimals to 18 decimals and returns the conversion rate of 1 stETH to ETH underlying the token in the Lido protocol
 * @notice  This contract is a shim that implements the Chainlink AggregatorV3Interface and returns pricing as 1:1 for stETH:ETH
 */
contract STETHShim {
    constructor() {}

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function description() external pure returns (string memory) {
        return "stETH Chainlink Shim";
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
        return _getStETHData();
    }

    /**
     * @notice  This function gets the price of 1 stETH in ETH as 1 with 18 decimal precision~
     * @dev     This function does not implement the full Chainlink AggregatorV3Interface
     * @return  roundId  0 - never returns valid round ID
     * @return  answer  The conversion rate of 1 stETH to ETH.
     * @return  startedAt  0 - never returns valid timestamp
     * @return  updatedAt  The current timestamp.
     * @return  answeredInRound  0 - never returns valid round ID
     */
    function _getStETHData()
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
        return (0, int256(1e18), 0, block.timestamp, 0);
    }
}
