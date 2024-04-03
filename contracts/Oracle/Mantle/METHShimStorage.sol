// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./IMethStaking.sol";

abstract contract METHShimStorageV1 is AggregatorV3Interface {
    IMethStaking public methStaking;
}
