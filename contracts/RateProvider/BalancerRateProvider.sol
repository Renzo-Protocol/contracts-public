// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IRateProvider.sol";
import "../Errors/Errors.sol";
import "./BalancerRateProviderStorage.sol";

contract BalancerRateProvider is Initializable, IRateProvider, BalancerRateProviderStorageV1 {
    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract with initial vars
    function initialize(
        IRestakeManager _restakeManager,
        IERC20Upgradeable _ezETHToken
    ) public initializer {
        if (address(_restakeManager) == address(0x0)) revert InvalidZeroInput();
        if (address(_ezETHToken) == address(0x0)) revert InvalidZeroInput();

        restakeManager = _restakeManager;
        ezETHToken = _ezETHToken;
    }

    /// @dev Returns the current rate of ezETH in ETH
    function getRate() external view returns (uint256) {
        // Get the total TVL priced in ETH from restakeManager
        (, , uint256 totalTVL) = restakeManager.calculateTVLs();

        // Get the total supply of the ezETH token
        uint256 totalSupply = ezETHToken.totalSupply();

        // Sanity check
        if (totalSupply == 0 || totalTVL == 0) revert InvalidZeroInput();

        // Return the rate
        return (10 ** 18 * totalTVL) / totalSupply;
    }
}
