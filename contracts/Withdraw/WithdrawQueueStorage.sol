// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "../Permissions/IRoleManager.sol";
import "../Oracle/IRenzoOracle.sol";
import "../IRestakeManager.sol";
import "../token/IEzEthToken.sol";

abstract contract WithdrawQueueStorageV1 {
    address public constant IS_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct TokenWithdrawBuffer {
        address asset;
        uint256 bufferAmount;
    }

    struct WithdrawRequest {
        address collateralToken;
        uint256 withdrawRequestID;
        uint256 amountToRedeem;
        uint256 ezETHLocked;
        uint256 createdAt;
    }

    /// @dev reference to the RenzoOracle contract
    IRenzoOracle public renzoOracle;

    /// @dev reference to the ezETH token contract
    IEzEthToken public ezETH;

    /// @dev reference to the RoleManager contract
    IRoleManager public roleManager;

    /// @dev reference to the RestakeManager contract
    IRestakeManager public restakeManager;

    /// @dev cooldown period for user to claim their withdrawal
    uint256 public coolDownPeriod;

    /// @dev nonce for tracking withdraw requests, This only increments (doesn't decrement)
    uint256 public withdrawRequestNonce;

    /// @dev mapping of withdrawalBufferTarget, indexed by token address
    mapping(address => uint256) public withdrawalBufferTarget;

    /// @dev mapping of claimReserve (already withdraw requested), indexed by token address
    mapping(address => uint256) public claimReserve;

    /// @dev mapiing of withdraw requests array, indexed by user address
    mapping(address => WithdrawRequest[]) public withdrawRequests;
}

abstract contract WithdrawQueueStorageV2 is WithdrawQueueStorageV1 {
    /// @dev Struct for the withdrawQueue
    struct WithdrawQueue {
        uint256 queuedWithdrawToFill;
        uint256 queuedWithdrawFilled;
    }

    /// @dev Struct for WithdrawRequest queue status with expected to be filled
    struct WithdrawQueueStatus {
        bool queued;
        uint256 fillAt;
    }

    /// @dev mapping of queued withdrawRequest, indexed by withdrawRequest hash
    mapping(bytes32 => WithdrawQueueStatus) public withdrawQueued;

    /// @dev mapping for asset withdrawQueue
    /// @dev WithdrawQueue is a sliding window
    WithdrawQueue public ethWithdrawQueue;
}

abstract contract WithdrawQueueStorageV3 is WithdrawQueueStorageV2 {
    /// @dev Deprecated - not using anymore as any asset can be added to WithdrawQueue
    /// @dev Tracks if Withdraw Queue enable for collateral asset
    mapping(address => bool) public erc20WithdrawQueueEnabled;

    /// @dev WithdrawQueue for ERC20 assets
    mapping(address => WithdrawQueue) public erc20WithdrawQueue;
}

abstract contract WithdrawQueueStorageV4 is WithdrawQueueStorageV3 {
    mapping(address => bool) public whitelisted;
}

abstract contract WithdrawQueueStorageV5 is WithdrawQueueStorageV4 {
    /// @dev mapping to track stETH depositors and their ezETH balance
    mapping(address => uint256) public stETHDepositors;

    /// @dev mapping to track stETH depositors and their withdrawal amount of ezETH at market rate
    mapping(bytes32 => uint256) public stETHDepositorsWithdrawalAmount;
}
