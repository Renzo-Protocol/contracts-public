// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./IxRenzoDeposit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../Connext/core/IConnext.sol";
import "./Oracle/IRenzoOracleL2.sol";

abstract contract xRenzoDepositStorageV1 is IxRenzoDeposit {
    /// @notice The last timestamp the price was updated
    uint256 public lastPriceTimestamp;

    /// @notice The last price that was updated - denominated in ETH with 18 decimal precision
    uint256 public lastPrice;

    /// @notice The xezETH token address
    IERC20 public xezETH;

    /// @notice The deposit token address - this is what users will deposit to mint xezETH
    IERC20 public depositToken;

    /// @notice The collateral token address - this is what the deposit token will be swapped into and bridged to L1
    IERC20 public collateralToken;

    /// @notice The address of the main Connext contract
    IConnext public connext;

    /// @notice The swap ID for the connext token swap
    bytes32 public swapKey;

    /// @notice The receiver middleware contract address
    address public receiver;

    /// @notice The bridge router fee basis points - 100 basis points = 1%
    uint256 public bridgeRouterFeeBps;

    /// @notice The bridge destination domain - mainnet ETH connext domain
    uint32 public bridgeDestinationDomain;

    /// @notice The contract address where the bridge call should be sent on mainnet ETH
    address public bridgeTargetAddress;

    /// @notice The mapping of allowed addresses that can trigger the bridge function
    mapping(address => bool) public allowedBridgeSweepers;
}

abstract contract xRenzoDepositStorageV2 is xRenzoDepositStorageV1 {
    /// @notice renzo oracle middleware for pulling price feed
    IRenzoOracleL2 public oracle;
}

abstract contract xRenzoDepositStorageV3 is xRenzoDepositStorageV2 {
    // bridge fee in basis points 100 basis points = 1%
    uint256 public bridgeFeeShare;

    // Batch size for sweeping
    uint256 public sweepBatchSize;

    // Total bridge fee collected for current batch
    uint256 public bridgeFeeCollected;
}
