// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IRenzoOracleL2 {
    function getMintRate() external view returns (uint256, uint256);
}
