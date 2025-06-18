// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IMailbox } from "@hyperlane-xyz/core/contracts/interfaces/IMailbox.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IxRenzoDeposit } from "../IxRenzoDeposit.sol";
import { IRenzoOracleL2 } from "../Oracle/IRenzoOracleL2.sol";
import "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import "../../../Errors/Errors.sol";
import {
    StandardHookMetadata
} from "@hyperlane-xyz/core/contracts/hooks/libs/StandardHookMetadata.sol";

contract HyperlaneSender is Ownable, Pausable, ReentrancyGuard {
    using TypeCasts for address;

    struct DestinationParams {
        uint32 destinationDomain;
        address _renzoReceiver;
    }

    // Gas limit required to execute handle on destination chain
    uint256 public constant DESTINATION_GAS_LIMIT = 150_000;

    IMailbox public mailbox;

    IRenzoOracleL2 public renzoOracle;

    address public priceFeedSender;

    IxRenzoDeposit public xRenzoDeposit;

    address public pauser;

    uint256 public lastPriceSent;
    uint256 public lastPriceSentTimestamp;

    event XRenzoDepositUpdated(address newRenzoDeposit, address oldRenzoDeposit);
    event PauserUpdated(address oldPauser, address newPauser);
    event MessageSent(
        bytes32 indexed messageId,
        uint32 indexed destinationDomain,
        address receiver,
        uint256 exchangeRate,
        uint256 fees
    );

    /// @dev Only allows pauser and owner to change pause state
    modifier onlyOwnerOrPauser() {
        if (msg.sender != owner() && msg.sender != pauser) revert NotPauser();
        _;
    }

    /// @dev Only allows price feed sender to send price
    modifier onlyPriceFeedSender() {
        if (msg.sender != priceFeedSender) revert NotPriceFeedSender();
        _;
    }

    constructor(IMailbox _mailBox, IRenzoOracleL2 _oracle, IxRenzoDeposit _xRenzoDeposit) {
        if (
            address(_mailBox) == address(0) ||
            address(_oracle) == address(0) ||
            address(_xRenzoDeposit) == address(0)
        ) revert InvalidZeroInput();
        mailbox = _mailBox;
        renzoOracle = _oracle;
        xRenzoDeposit = _xRenzoDeposit;
        _pause();
    }

    function sendPrice(
        DestinationParams[] calldata destinationParams
    ) external payable onlyPriceFeedSender nonReentrant whenNotPaused {
        (uint256 exchangeRate, uint256 timestamp) = renzoOracle.getMintRate();

        bytes memory _callData = abi.encode(exchangeRate, timestamp);
        bytes memory metadata = _getMetadata();

        // send price to each chain
        for (uint256 i = 0; i < destinationParams.length; ) {
            uint256 fee = mailbox.quoteDispatch(
                destinationParams[i].destinationDomain,
                (destinationParams[i]._renzoReceiver).addressToBytes32(),
                _callData,
                metadata
            );
            bytes32 messageId = mailbox.dispatch{ value: fee }(
                destinationParams[i].destinationDomain,
                (destinationParams[i]._renzoReceiver).addressToBytes32(),
                _callData,
                metadata
            );

            emit MessageSent(
                messageId,
                destinationParams[i].destinationDomain,
                destinationParams[i]._renzoReceiver,
                exchangeRate,
                fee
            );

            unchecked {
                ++i;
            }
        }
        // update price in xRenzoDeposit
        xRenzoDeposit.updatePrice(exchangeRate, timestamp);

        // record the last price and timestamp
        lastPriceSent = exchangeRate;
        lastPriceSentTimestamp = timestamp;
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
     * @notice UnPause the contract
     * @dev This should be a permissioned call (onlyOwner)
     */
    function unPause() external onlyOwnerOrPauser {
        _unpause();
    }

    /**
     * @notice Pause the contract
     * @dev This should be a permissioned call (onlyOwner)
     */
    function pause() external onlyOwnerOrPauser {
        _pause();
    }

    function setPriceFeedSender(address _priceFeedSender) external onlyOwner {
        if (_priceFeedSender == address(0)) revert InvalidZeroInput();
        priceFeedSender = _priceFeedSender;
    }

    function rescueFunds() external onlyOwner {
        (bool success, ) = payable(msg.sender).call{ value: address(this).balance }("");
        if (!success) revert TransferFailed();
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

    function _getMetadata() internal view returns (bytes memory) {
        return
            StandardHookMetadata.formatMetadata(
                0, // ETH message value
                DESTINATION_GAS_LIMIT,
                address(this), // refund address
                bytes("") // custom metadata
            );
    }
}
