pragma solidity >=0.4.21 <0.9.0;

/**
 * @title Precompiled contract that exists in every Arbitrum chain at address(100), 0x0000000000000000000000000000000000000064. Exposes a variety of system-level functionality.
 * NOTE: This contract has unused functions removed from the interface to help with mock testing
 */
interface ArbSys {
    /**
     * @notice Send given amount of Eth to dest from sender.
     * This is a convenience function, which is equivalent to calling sendTxToL1 with empty calldataForL1.
     * @param destination recipient address on L1
     * @return unique identifier for this L2-to-L1 transaction.
     */
    function withdrawEth(address destination) external payable returns (uint);

    event L2ToL1Transaction(
        address caller,
        address indexed destination,
        uint indexed uniqueId,
        uint indexed batchNumber,
        uint indexInBatch,
        uint arbBlockNum,
        uint ethBlockNum,
        uint timestamp,
        uint callvalue,
        bytes data
    );
}
