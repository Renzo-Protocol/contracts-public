// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./IRenzoOracleL2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

abstract contract RenzoOracleL2StorageV1 is IRenzoOracleL2 {
    AggregatorV3Interface public oracle;
}
