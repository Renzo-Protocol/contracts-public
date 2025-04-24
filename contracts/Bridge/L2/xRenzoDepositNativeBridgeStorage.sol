// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "./IxRenzoDeposit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Oracle/IRenzoOracleL2.sol";
import "../Connext/core/IWeth.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./ValueTransfer/IValueTransferBridge.sol";

abstract contract xRenzoDepositNativeBridgeStorageV1 is IxRenzoDeposit {
    /// @notice The last timestamp the price was updated
    uint256 public lastPriceTimestamp;

    /// @notice The last price that was updated - denominated in ETH with 18 decimal precision
    uint256 public lastPrice;

    /// @notice The xezETH token address
    IERC20 public xezETH;

    /// @notice The receiver middleware contract address
    address public receiver;

    /// @notice The contract address where the bridge call should be sent on mainnet ETH
    address public bridgeTargetAddress;

    // bridge fee in basis points 100 basis points = 1%
    uint256 public bridgeFeeShare;

    // Batch size for sweeping
    uint256 public sweepBatchSize;

    // WETH token for wrapping ETH
    IWeth public weth;

    /// @dev Contracts that routes funds down to mainnet per token
    mapping(IERC20 => IValueTransferBridge) public valueTransferBridges;

    /// @dev The mainnet destination domain to receive bridge funds
    uint32 public mainnetDestinationDomain;

    /// @dev The contract on mainnet to receive bridge funds
    address public mainnetRecipient;

    // @dev Mapping of supported tokens
    mapping(IERC20 => bool) public depositTokenSupported;

    // @dev Mapping of token to oracle lookup
    mapping(IERC20 => AggregatorV3Interface) public tokenOracleLookup;

    // @dev Bridge fees are sent to the bridge fee collector
    address public bridgeFeeCollector;

    // @dev The mapping of token to time based discount in basis points - 100 basis points = 1%
    mapping(IERC20 => uint256) public tokenTimeDiscountBasisPoints;
}
