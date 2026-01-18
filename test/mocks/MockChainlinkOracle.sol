// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockChainlinkOracle
 * @notice A mock Chainlink oracle for testing purposes
 * @dev Implements AggregatorV3Interface to simulate price feeds
 */
contract MockChainlinkOracle is AggregatorV3Interface {
    uint8 private _decimals;
    int256 private _price;
    uint256 private _updatedAt;
    bool private _isStale;
    uint80 private _roundId;
    string private constant DESCRIPTION = "Mock Chainlink Oracle";

    constructor(uint8 decimals_, int256 initialPrice_) {
        _decimals = decimals_;
        _price = initialPrice_;
        _updatedAt = block.timestamp;
        _roundId = 1;
        _isStale = false;
    }

    /**
     * @notice Returns the number of decimals for the price feed
     */
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Returns the description of the price feed
     */
    function description() external pure override returns (string memory) {
        return DESCRIPTION;
    }

    /**
     * @notice Returns the version of the aggregator
     */
    function version() external pure override returns (uint256) {
        return 1;
    }

    /**
     * @notice Get data for a specific round
     * @dev For mock purposes, returns current data regardless of roundId
     */
    function getRoundData(
        uint80 /* _roundId */
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _updatedAt, _getUpdatedAt(), _roundId);
    }

    /**
     * @notice Get the latest round data
     * @return roundId The round ID
     * @return answer The price answer
     * @return startedAt When the round started
     * @return updatedAt When the round was updated
     * @return answeredInRound The round in which the answer was computed
     */
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _updatedAt, _getUpdatedAt(), _roundId);
    }

    /**
     * @notice Set the price for testing
     * @param newPrice The new price to set
     */
    function setPrice(int256 newPrice) external {
        _price = newPrice;
        _updatedAt = block.timestamp;
        _roundId++;
    }

    /**
     * @notice Set whether the oracle should return stale data
     * @param isStale Whether to simulate stale data
     */
    function setStale(bool isStale) external {
        _isStale = isStale;
    }

    /**
     * @notice Set the decimals for testing
     * @param newDecimals The new decimals value
     */
    function setDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
    }

    /**
     * @notice Get the updatedAt timestamp (stale if configured)
     */
    function _getUpdatedAt() internal view returns (uint256) {
        if (_isStale) {
            // Return a very old timestamp to simulate stale data
            return block.timestamp - 365 days;
        }
        return _updatedAt;
    }

    /**
     * @notice Get the current price (for testing convenience)
     */
    function getPrice() external view returns (int256) {
        return _price;
    }
}
