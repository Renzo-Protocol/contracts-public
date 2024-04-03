// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./IStakedTokenV2.sol";

abstract contract WBETHShimStorageV1 is AggregatorV3Interface {
    IStakedTokenV2 public wBETHToken;
}
