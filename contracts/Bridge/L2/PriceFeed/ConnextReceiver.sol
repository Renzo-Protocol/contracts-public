// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { IXReceiver } from "@connext/interfaces/core/IXReceiver.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { IxRenzoDeposit } from "../IxRenzoDeposit.sol";
import "../../../Errors/Errors.sol";

contract ConnextReceiver is IXReceiver, Ownable, Pausable {
    /// @notice The address of connext Bridge
    address public connext;

    /// @notice The Address of xRenzoBridge contract on L1
    address public xRenzoBridgeL1;

    /// @notice The connext source chain domain id for Ethereum
    uint32 public connextEthChainDomain;

    /// @notice xRenzoDeposit Contract on L2
    IxRenzoDeposit public xRenzoDeposit;

    event XRenzoBridgeL1Updated(address newBridgeAddress, address oldBridgeAddress);
    event ConnextEthChainDomainUpdated(uint32 newSourceChainDomain, uint32 oldSourceChainDomain);
    event XRenzoDepositUpdated(address newRenzoDeposit, address oldRenzoDeposit);

    /**
     *  @dev Event emitted when a message is received from another chain
     *  @param messageId  The unique ID of the message
     *  @param sourceChainDomain  The chain domain id of the source chain
     *  @param sender  The address of the sender from the source chain.
     *  @param price  The price feed received on L2.
     *  @param timestamp  The timestamp when price feed was sent from L1.
     */
    event MessageReceived(
        bytes32 indexed messageId,
        uint32 indexed sourceChainDomain,
        address sender,
        uint256 price,
        uint256 timestamp
    );

    modifier onlySource(address _originSender, uint32 _origin) {
        if (
            _originSender != xRenzoBridgeL1 ||
            _origin != connextEthChainDomain ||
            msg.sender != connext
        ) revert UnAuthorisedCall();
        _;
    }

    constructor(address _connext, address _xRenzoBridgeL1, uint32 _connextEthChainDomain) {
        if (_xRenzoBridgeL1 == address(0) || _connextEthChainDomain == 0 || _connext == address(0))
            revert InvalidZeroInput();

        // Set connext bridge address
        connext = _connext;

        // Set xRenzoBridge L1 contract address
        xRenzoBridgeL1 = _xRenzoBridgeL1;

        // Set connext source chain Domain Id for Ethereum L1
        connextEthChainDomain = _connextEthChainDomain;

        // Pause The contract to setup xRenzoDeposit
        _pause();
    }

    function xReceive(
        bytes32 _transferId,
        uint256,
        address,
        address _originSender,
        uint32 _origin,
        bytes memory _callData
    ) external onlySource(_originSender, _origin) whenNotPaused returns (bytes memory) {
        (uint256 _price, uint256 _timestamp) = abi.decode(_callData, (uint256, uint256));
        xRenzoDeposit.updatePrice(_price, _timestamp);

        emit MessageReceived(_transferId, _origin, _originSender, _price, _timestamp);
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
     * @notice This function updates the allowed connext source chain domain
     * @dev This should be a permissioned call (onlyOnwer)
     * @param _newChainDomain New source chain Domain
     */
    function updateCCIPEthChainSelector(uint32 _newChainDomain) external onlyOwner {
        if (_newChainDomain == 0) revert InvalidZeroInput();
        emit ConnextEthChainDomainUpdated(_newChainDomain, connextEthChainDomain);
        connextEthChainDomain = _newChainDomain;
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
