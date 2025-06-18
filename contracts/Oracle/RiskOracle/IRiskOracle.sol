// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

interface IRiskOracle {
    struct RiskParameterUpdate {
        uint256 timestamp; // Timestamp of the update
        bytes newValue; // Encoded parameters, flexible for various data types
        string referenceId; // External reference, potentially linking to a document or off-chain data
        bytes previousValue; // Previous value of the parameter for historical comparison
        string updateType; // Classification of the update for validation purposes
        uint256 updateId; // Unique identifier for this specific update
        address market; // Address for market of the parameter update
        bytes additionalData; // Additional data for the update
    }

    function updateCounter() external view returns (uint256);

    function getUpdateById(uint256 updateId) external view returns (RiskParameterUpdate memory);

    function latestUpdateIdByMarketAndType(
        address market,
        string memory updateType
    ) external view returns (uint256);
}
