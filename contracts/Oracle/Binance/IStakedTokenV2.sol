// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/// @dev Interface to get exchange rate on wBETH
interface IStakedTokenV2 {
    function exchangeRate() external view returns (uint256 _exchangeRate);
}
