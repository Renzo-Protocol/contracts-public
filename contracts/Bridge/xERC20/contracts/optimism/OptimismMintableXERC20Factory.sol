// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import { OptimismMintableXERC20 } from "./OptimismMintableXERC20.sol";
import { XERC20Factory } from "../XERC20Factory.sol";
import { XERC20Lockbox } from "../XERC20Lockbox.sol";
import { CREATE3 } from "solmate/utils/CREATE3.sol";
import {
    EnumerableSetUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract OptimismMintableXERC20Factory is Initializable, XERC20Factory {
    error OptimismMintableXERC20Factory_NoBridges();

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Deploys an OptimismMintableXERC20 contract using CREATE3
     * @dev _limits and _minters must be the same length
     * @dev By convention, _minters[0] is the optimism bridge.
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
     * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
     * @param _bridges The array of bridges that you are adding (optional, can be an empty array)
     * @param _proxyAdmin The address of the proxy admin - will have permission to upgrade the lockbox (should be a dedicated account or contract to manage upgrades)
     * @param _l1Token The address of the l1 token
     * @return _xerc20 The address of the xerc20
     */

    function deployOptimismMintableXERC20(
        string memory _name,
        string memory _symbol,
        uint256[] memory _minterLimits,
        uint256[] memory _burnerLimits,
        address[] memory _bridges,
        address _proxyAdmin,
        address _l1Token
    ) public returns (address _xerc20) {
        _xerc20 = _deployOptimismMintableXERC20(
            _name,
            _symbol,
            _minterLimits,
            _burnerLimits,
            _bridges,
            _proxyAdmin,
            _l1Token
        );

        emit XERC20Deployed(_xerc20);
    }

    /**
     * @notice Deploys an OptimismMintableXERC20 contract using CREATE3
     * @dev _limits and _minters must be the same length.
     * @dev By convention, _minters[0] is the optimism bridge.
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     * @param _minterLimits The array of limits that you are adding (required, must at least include optimism bridge)
     * @param _burnerLimits The array of limits that you are adding (required, must at least include optimism bridge)
     * @param _bridges The array of burners that you are adding (required, must at least include optimism bridge)
     * @param _proxyAdmin The address of the proxy admin - will have permission to upgrade the lockbox (should be a dedicated account or contract to manage upgrades)
     * @param _l1Token The address of the l1 token
     * @return _xerc20 The address of the xerc20
     */

    function _deployOptimismMintableXERC20(
        string memory _name,
        string memory _symbol,
        uint256[] memory _minterLimits,
        uint256[] memory _burnerLimits,
        address[] memory _bridges,
        address _proxyAdmin,
        address _l1Token
    ) internal returns (address _xerc20) {
        uint256 _bridgesLength = _bridges.length;
        if (_minterLimits.length != _bridgesLength || _burnerLimits.length != _bridgesLength) {
            revert IXERC20Factory_InvalidLength();
        }
        if (_bridgesLength < 1) {
            revert OptimismMintableXERC20Factory_NoBridges();
        }
        bytes32 _salt = keccak256(abi.encodePacked(_name, _symbol, msg.sender));

        // Initialize function - sent as 3rd argument to the proxy constructor
        bytes memory initializeBytecode = abi.encodeCall(
            OptimismMintableXERC20.initialize,
            (_name, _symbol, address(this), _l1Token, _bridges[0])
        );

        bytes memory _creation = type(TransparentUpgradeableProxy).creationCode;

        // Constructor in Proxy takes (logic, admin, data)
        bytes memory _bytecode = abi.encodePacked(
            _creation,
            abi.encode(xerc20Implementation, _proxyAdmin, initializeBytecode)
        );

        _xerc20 = CREATE3.deploy(_salt, _bytecode, 0);

        EnumerableSetUpgradeable.add(_xerc20RegistryArray, _xerc20);

        for (uint256 _i; _i < _bridgesLength; ++_i) {
            OptimismMintableXERC20(_xerc20).setLimits(
                _bridges[_i],
                _minterLimits[_i],
                _burnerLimits[_i]
            );
        }

        OptimismMintableXERC20(_xerc20).transferOwnership(msg.sender);
    }
}
