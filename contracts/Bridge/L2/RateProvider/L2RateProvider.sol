// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "../../../RateProvider/IRateProvider.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../../../Errors/Errors.sol";

contract L2RateProvider is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IRateProvider
{
    IRateProvider public immutable newRenzoDeposit;

    constructor(IRateProvider _newRenzoDeposit) {
        if (address(_newRenzoDeposit) == address(0)) revert InvalidZeroInput();
        newRenzoDeposit = _newRenzoDeposit;
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }
    function getRate() external view override returns (uint256) {
        return newRenzoDeposit.getRate();
    }
}
