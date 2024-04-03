// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IXERC20 } from "../../xERC20/interfaces/IXERC20.sol";
import { IXERC20Lockbox } from "../../xERC20/interfaces/IXERC20Lockbox.sol";

interface IXERC20Registry {
    function getXERC20(address erc20) external view returns (address xerc20);

    function getERC20(address xerc20) external view returns (address erc20);

    function getLockbox(address erc20) external view returns (address xerc20);
}

interface L1StandardBridge {
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}

/// @notice This adapter is only used for sending assets from Ethereum mainnet to Blast.
/// @dev Combines Lockbox deposit and Blast bridge's BridgeERC20 call to minimize user transactions.
contract LockboxAdapterBlast {
    address immutable blastStandardBridge;
    address immutable registry;

    // ERRORS
    error InvalidRemoteToken(address _remoteToken);
    error AmountLessThanZero();
    error InvalidAddress();

    constructor(address _blastStandardBridge, address _registry) {
        // Sanity check
        if (_blastStandardBridge == address(0) || _registry == address(0)) {
            revert InvalidAddress();
        }

        blastStandardBridge = _blastStandardBridge;
        registry = _registry;
    }

    /// @dev Combines Lockbox deposit and Blast bridge's BridgeERC20To call.
    /// @param _to The recipient or contract address on destination.
    /// @param _erc20 The address of the adopted ERC20 on the origin chain.
    /// @param _remoteToken The address of the asset to be received on the destination chain.
    /// @param _amount The amount of asset to bridge.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData Extra data to be sent with the transaction.
    function bridgeTo(
        address _to,
        address _erc20,
        address _remoteToken,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external {
        // Sanity check
        if (_amount <= 0) {
            revert AmountLessThanZero();
        }

        address xerc20 = IXERC20Registry(registry).getXERC20(_erc20);
        address lockbox = IXERC20Registry(registry).getLockbox(xerc20);

        // Sanity check
        if (xerc20 == address(0) || lockbox == address(0)) {
            revert InvalidAddress();
        }

        // If using xERC20, the assumption is that the contract should be deployed at same address
        // on both networks.
        if (xerc20 != _remoteToken) {
            revert InvalidRemoteToken(_remoteToken);
        }

        SafeERC20.safeTransferFrom(IERC20(_erc20), msg.sender, address(this), _amount);
        SafeERC20.safeApprove(IERC20(_erc20), lockbox, _amount);
        IXERC20Lockbox(lockbox).deposit(_amount);
        SafeERC20.safeApprove(IERC20(xerc20), blastStandardBridge, _amount);
        L1StandardBridge(blastStandardBridge).bridgeERC20To(
            xerc20,
            _remoteToken,
            _to,
            _amount,
            _minGasLimit,
            _extraData
        );
    }
}
