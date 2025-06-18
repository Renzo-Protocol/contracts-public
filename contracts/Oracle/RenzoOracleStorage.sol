// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "../Permissions/IRoleManager.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract RenzoOracleStorageV1 {
    /// @dev reference to the RoleManager contract
    IRoleManager public roleManager;

    /// @dev The mapping of supported token addresses to their respective Chainlink oracle address
    mapping(IERC20 => AggregatorV3Interface) public tokenOracleLookup;
}

abstract contract RenzoOracleStorageV2 is RenzoOracleStorageV1 {
    /// @dev Deprecated - not using anymore as secondary rate withdrawal/claims migration is complete
    AggregatorV3Interface public stETHSecondaryOracle;
}
