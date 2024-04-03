// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {
    CCIPReceiver
} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { IxRenzoDeposit } from "../IxRenzoDeposit.sol";
import "../../../Errors/Errors.sol";

/// @title CCIPReceiver - Base contract for CCIP applications that can receive messages.
contract Receiver is CCIPReceiver, Ownable, Pausable {
    /// @notice The Address of xRenzoBridge contract on L1
    address public xRenzoBridgeL1;

    /// @notice The chainlink source chain selector id for Ethereum
    uint64 public ccipEthChainSelector;

    /// @notice xRenzoDeposit Contract on L2
    IxRenzoDeposit public xRenzoDeposit;

    event XRenzoBridgeL1Updated(address newBridgeAddress, address oldBridgeAddress);
    event CCIPEthChainSelectorUpdated(uint64 newSourceChainSelector, uint64 oldSourceChainSelector);
    event XRenzoDepositUpdated(address newRenzoDeposit, address oldRenzoDeposit);
    /**
     *  @dev Event emitted when a message is received from another chain
     *  @param messageId  The unique ID of the message
     *  @param sourceChainSelector  The chain selector of the source chain
     *  @param sender  The address of the sender from the source chain.
     *  @param price  The price feed received on L2.
     *  @param timestamp  The timestamp when price feed was sent from L1.
     */
    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        uint256 price,
        uint256 timestamp
    );

    constructor(
        address _router,
        address _xRenzoBridgeL1,
        uint64 _ccipEthChainSelector
    ) CCIPReceiver(_router) {
        if (_xRenzoBridgeL1 == address(0) || _ccipEthChainSelector == 0) revert InvalidZeroInput();

        // Set xRenzoBridge L1 contract address
        xRenzoBridgeL1 = _xRenzoBridgeL1;

        // Set ccip source chain selector for Ethereum L1
        ccipEthChainSelector = _ccipEthChainSelector;

        // Pause The contract to setup xRenzoDeposit
        _pause();
    }

    /**
     * @notice  Updates the price feed
     * @dev     This function will receive the price feed from the L1.
     *          It should verify the origin of the call and only allow permissioned source to call.
     * @param   any2EvmMessage ccip Message received from L1 -> L2
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override whenNotPaused {
        address _ccipSender = abi.decode(any2EvmMessage.sender, (address));
        uint64 _ccipSourceChainSelector = any2EvmMessage.sourceChainSelector;
        // Verify origin on the price feed
        if (_ccipSender != xRenzoBridgeL1) revert InvalidSender(xRenzoBridgeL1, _ccipSender);
        // Verify Source chain of the message
        if (_ccipSourceChainSelector != ccipEthChainSelector)
            revert InvalidSourceChain(ccipEthChainSelector, _ccipSourceChainSelector);
        (uint256 _price, uint256 _timestamp) = abi.decode(any2EvmMessage.data, (uint256, uint256));
        xRenzoDeposit.updatePrice(_price, _timestamp);
        emit MessageReceived(
            any2EvmMessage.messageId,
            _ccipSourceChainSelector,
            _ccipSender,
            _price,
            _timestamp
        );
    }

    /******************************
     *  Admin/OnlyOwner functions
     *****************************/

    /**
     * @notice This function updates the xRenzoBridge Contract address deployed on Ethereum L1
     * @dev This should be a permissioned call (onlyOnwer)
     * @param _newXRenzoBridgeL1 New address of xRenzoBridge Contract
     */
    function updateXRenzoBridgeL1(address _newXRenzoBridgeL1) external onlyOwner {
        if (_newXRenzoBridgeL1 == address(0)) revert InvalidZeroInput();
        emit XRenzoBridgeL1Updated(_newXRenzoBridgeL1, xRenzoBridgeL1);
        xRenzoBridgeL1 = _newXRenzoBridgeL1;
    }

    /**
     * @notice This function updates the allowed chainlink CCIP source chain selector
     * @dev This should be a permissioned call (onlyOnwer)
     * @param _newChainSelector New source chain selector
     */
    function updateCCIPEthChainSelector(uint64 _newChainSelector) external onlyOwner {
        if (_newChainSelector == 0) revert InvalidZeroInput();
        emit CCIPEthChainSelectorUpdated(_newChainSelector, ccipEthChainSelector);
        ccipEthChainSelector = _newChainSelector;
    }

    /**
     * @notice Pause the contract
     * @dev This should be a permissioned call (onlyOwner)
     */
    function unPause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice UnPause the contract
     * @dev This should be a permissioned call (onlyOwner)
     */
    function pause() external onlyOwner {
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
