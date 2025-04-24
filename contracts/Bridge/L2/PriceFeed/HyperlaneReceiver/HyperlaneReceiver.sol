// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Router } from "@hyperlane-xyz/core/contracts/client/Router.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import "./HyperlaneReceiverStorage.sol";
import "../../../../Errors/Errors.sol";

contract HyperlaneReceiver is Router, PausableUpgradeable, HyperlaneReceiverStorageV1 {
    using TypeCasts for bytes32;

    event XRenzoDepositUpdated(address newRenzoDeposit, address oldRenzoDeposit);
    event PauserUpdated(address oldPauser, address newPauser);
    /**
     *  @dev Event emitted when a message is received from another chain
     *  @param sourceChainDomain  The chain domain id of the source chain
     *  @param sender  The address of the sender from the source chain.
     *  @param price  The price feed received on L2.
     *  @param timestamp  The timestamp when price feed was sent from source chain.
     */
    event MessageReceived(
        uint32 indexed sourceChainDomain,
        address sender,
        uint256 price,
        uint256 timestamp
    );

    /// @dev Only allows pauser and owner to change pause state
    modifier onlyOwnerOrPauser() {
        if (msg.sender != owner() && msg.sender != pauser) revert NotPauser();
        _;
    }

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _mailbox) Router(_mailbox) {
        _disableInitializers();
    }

    function initialize(
        address _hook,
        address _interchainSecurityModule,
        address _owner,
        uint32 _sourceDomain,
        bytes32 _sourceSender
    ) external initializer {
        if (
            _owner == address(0) ||
            _sourceSender.bytes32ToAddress() == address(0) ||
            _sourceDomain == 0
        ) revert InvalidZeroInput();

        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);

        // Enroll sender contract address as remote router
        _enrollRemoteRouter(_sourceDomain, _sourceSender);

        // pause the contract to config xRenzoDeposit
        _pause();
    }

    function _handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
    ) internal virtual override {
        _requireNotPaused();
        (uint256 _price, uint256 _timestamp) = abi.decode(_message, (uint256, uint256));
        xRenzoDeposit.updatePrice(_price, _timestamp);

        emit MessageReceived(_origin, _sender.bytes32ToAddress(), _price, _timestamp);
    }

    /******************************
     *  Admin/OnlyOwner functions
     *****************************/

    /**
     * @notice  Update pauser address
     * @dev     permissioned call (onlyOwner)
     * @param   _pauser  new pauser address
     */
    function setPauser(address _pauser) external onlyOwner {
        if (_pauser == address(0)) revert InvalidZeroInput();
        emit PauserUpdated(pauser, _pauser);
        pauser = _pauser;
    }

    /**
     * @notice Pause the contract
     * @dev This should be a permissioned call (onlyOwner)
     */
    function unPause() external onlyOwnerOrPauser {
        _unpause();
    }

    /**
     * @notice UnPause the contract
     * @dev This should be a permissioned call (onlyOwner)
     */
    function pause() external onlyOwnerOrPauser {
        _pause();
    }

    /**
     * @notice This function updates the xRenzoDeposit Contract address
     * @dev This should be a permissioned call (onlyOnwer)
     * @param _newXRenzoDeposit New xRenzoDeposit Contract address
     */
    function setRenzoDeposit(address _newXRenzoDeposit) external onlyOwner {
        if (_newXRenzoDeposit == address(0)) revert InvalidZeroInput();
        emit XRenzoDepositUpdated(_newXRenzoDeposit, address(xRenzoDeposit));
        xRenzoDeposit = IxRenzoDeposit(_newXRenzoDeposit);
    }
}
