// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IRestakeManager } from "../IRestakeManager.sol";
import { IWithdrawQueue } from "./IWithdrawQueue.sol";

abstract contract InstantWithdrawerStorageV1 {
    /// @dev Address to use for tokens when native ETH
    address public constant IS_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev The percentage of the buffer that will be enforced to not go below...
    /// e.g. setting to 9_000 means 90%, and only 10% of the buffer can be used for instant withdrawals.
    uint256 public allowedBufferDrawdownBps;

    /// @dev Destination where collected fees will be sent
    address public feeDestination;

    /// @dev The min fee charged when the buffer is full
    uint256 public minFeeBps;

    /// @dev The max fee charged when the buffer is drawn down to the allowedBufferDrawdownBps percentage
    uint256 public maxFeeBps;
}
