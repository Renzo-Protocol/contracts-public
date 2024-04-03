// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import { IXERC20Factory } from "../interfaces/IXERC20Factory.sol";
import { XERC20 } from "./XERC20.sol";
import { XERC20Lockbox } from "./XERC20Lockbox.sol";
import { CREATE3 } from "solmate/utils/CREATE3.sol";
import {
    EnumerableSetUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract XERC20Factory is Initializable, IXERC20Factory {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /**
     * @notice Address of the xerc20 maps to the address of its lockbox if it has one
     */
    mapping(address => address) internal _lockboxRegistry;

    /**
     * @notice The set of registered lockboxes
     */
    EnumerableSetUpgradeable.AddressSet internal _lockboxRegistryArray;

    /**
     * @notice The set of registered XERC20 tokens
     */
    EnumerableSetUpgradeable.AddressSet internal _xerc20RegistryArray;

    /**
     * @notice The address of the implementation contract for any new lockboxes
     */
    address public lockboxImplementation;

    /**
     * @notice The address of the implementation contract for any new xerc20s
     */
    address public xerc20Implementation;

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Constructs the initial config of the XERC20
     *
     * @param _lockboxImplementation The address of the implementation contract for any new lockboxes
     * @param _xerc20Implementation The address of the implementation contract for any new xerc20s
     */
    function initialize(
        address _lockboxImplementation,
        address _xerc20Implementation
    ) public initializer {
        lockboxImplementation = _lockboxImplementation;
        xerc20Implementation = _xerc20Implementation;
    }

    /**
     * @notice Deploys an XERC20 contract using CREATE3
     * @dev _limits and _minters must be the same length
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
     * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
     * @param _bridges The array of bridges that you are adding (optional, can be an empty array)
     * @param _proxyAdmin The address of the proxy admin - will have permission to upgrade the lockbox (should be a dedicated account or contract to manage upgrades)
     * @return _xerc20 The address of the xerc20
     */

    function deployXERC20(
        string memory _name,
        string memory _symbol,
        uint256[] memory _minterLimits,
        uint256[] memory _burnerLimits,
        address[] memory _bridges,
        address _proxyAdmin
    ) external returns (address _xerc20) {
        _xerc20 = _deployXERC20(
            _name,
            _symbol,
            _minterLimits,
            _burnerLimits,
            _bridges,
            _proxyAdmin
        );

        emit XERC20Deployed(_xerc20);
    }

    /**
     * @notice Deploys an XERC20Lockbox contract using CREATE3
     *
     * @dev When deploying a lockbox for the gas token of the chain, then, the base token needs to be address(0)
     * @param _xerc20 The address of the xerc20 that you want to deploy a lockbox for
     * @param _baseToken The address of the base token that you want to lock
     * @param _isNative Whether or not the base token is the native (gas) token of the chain. Eg: MATIC for polygon chain
     * @param _proxyAdmin The address of the proxy admin - will have permission to upgrade the lockbox (should be a dedicated account or contract to manage upgrades)
     * @return _lockbox The address of the lockbox
     */

    function deployLockbox(
        address _xerc20,
        address _baseToken,
        bool _isNative,
        address _proxyAdmin
    ) external returns (address payable _lockbox) {
        if ((_baseToken == address(0) && !_isNative) || (_isNative && _baseToken != address(0))) {
            revert IXERC20Factory_BadTokenAddress();
        }

        if (XERC20(_xerc20).owner() != msg.sender) revert IXERC20Factory_NotOwner();
        if (_lockboxRegistry[_xerc20] != address(0)) revert IXERC20Factory_LockboxAlreadyDeployed();

        _lockbox = _deployLockbox(_xerc20, _baseToken, _isNative, _proxyAdmin);

        emit LockboxDeployed(_lockbox);
    }

    /**
     * @notice Deploys an XERC20 contract using CREATE3
     * @dev _limits and _minters must be the same length
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
     * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
     * @param _bridges The array of burners that you are adding (optional, can be an empty array)
     * @param _proxyAdmin The address of the proxy admin - will have permission to upgrade the lockbox (should be a dedicated account or contract to manage upgrades)
     * @return _xerc20 The address of the xerc20
     */

    function _deployXERC20(
        string memory _name,
        string memory _symbol,
        uint256[] memory _minterLimits,
        uint256[] memory _burnerLimits,
        address[] memory _bridges,
        address _proxyAdmin
    ) internal returns (address _xerc20) {
        uint256 _bridgesLength = _bridges.length;
        if (_minterLimits.length != _bridgesLength || _burnerLimits.length != _bridgesLength) {
            revert IXERC20Factory_InvalidLength();
        }
        bytes32 _salt = keccak256(abi.encodePacked(_name, _symbol, msg.sender));

        // Initialize function - sent as 3rd argument to the proxy constructor
        bytes memory initializeBytecode = abi.encodeCall(
            XERC20.initialize,
            (_name, _symbol, address(this))
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
            XERC20(_xerc20).setLimits(_bridges[_i], _minterLimits[_i], _burnerLimits[_i]);
        }

        XERC20(_xerc20).transferOwnership(msg.sender);
    }

    /**
     * @notice Deploys an XERC20Lockbox contract using CREATE3
     *
     * @dev When deploying a lockbox for the gas token of the chain, then, the base token needs to be address(0)
     * @param _xerc20 The address of the xerc20 that you want to deploy a lockbox for
     * @param _baseToken The address of the base token that you want to lock
     * @param _isNative Whether or not the base token is the native (gas) token of the chain. Eg: MATIC for polygon chain
     * @param _proxyAdmin The address of the proxy admin - will have permission to upgrade the lockbox (should be a dedicated account or contract to manage upgrades)
     * @return _lockbox The address of the lockbox
     */
    function _deployLockbox(
        address _xerc20,
        address _baseToken,
        bool _isNative,
        address _proxyAdmin
    ) internal returns (address payable _lockbox) {
        bytes32 _salt = keccak256(abi.encodePacked(_xerc20, _baseToken, msg.sender));

        // Initialize function - sent as 3rd argument to the proxy constructor
        bytes memory initializeBytecode = abi.encodeCall(
            XERC20Lockbox.initialize,
            (_xerc20, _baseToken, _isNative)
        );

        bytes memory _creation = type(TransparentUpgradeableProxy).creationCode;

        // Constructor in Proxy takes (logic, admin, data)
        bytes memory _bytecode = abi.encodePacked(
            _creation,
            abi.encode(lockboxImplementation, _proxyAdmin, initializeBytecode)
        );

        _lockbox = payable(CREATE3.deploy(_salt, _bytecode, 0));

        XERC20(_xerc20).setLockbox(address(_lockbox));
        EnumerableSetUpgradeable.add(_lockboxRegistryArray, _lockbox);
        _lockboxRegistry[_xerc20] = _lockbox;
    }
}
