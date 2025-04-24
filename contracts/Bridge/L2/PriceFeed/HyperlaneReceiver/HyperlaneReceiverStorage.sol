// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IxRenzoDeposit } from "../../IxRenzoDeposit.sol";

abstract contract HyperlaneReceiverStorageV1 {
    // tracks xRenzoDeposit contract on L2
    IxRenzoDeposit public xRenzoDeposit;

    /// @dev tracks the pauser account
    address public pauser;
}
