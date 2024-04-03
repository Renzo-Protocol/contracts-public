// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../IRestakeManager.sol";

abstract contract BalancerRateProviderStorageV1 {
    /// @dev reference to the RestakeManager contract
    IRestakeManager public restakeManager;

    /// @dev reference to the ezETH token contract
    IERC20Upgradeable public ezETHToken;
}
