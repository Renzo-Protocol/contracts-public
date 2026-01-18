// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title MockWithdrawQueue
 * @notice A mock WithdrawQueue contract for testing purposes
 * @dev Implements minimal IWithdrawQueue interface for testing
 */
contract MockWithdrawQueue {
    address public constant IS_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    struct WithdrawRequest {
        address collateralToken;
        uint256 withdrawRequestID;
        uint256 amountToRedeem;
        uint256 ezETHLocked;
        uint256 createdAt;
    }

    mapping(address => uint256[]) public userWithdrawRequests;
    mapping(uint256 => WithdrawRequest) public withdrawRequestsById;
    
    uint256 public nextRequestId;
    uint256 public ethWithdrawBuffer;
    uint256 public stETHPendingAmount;

    event WithdrawRequestCreated(
        address indexed user,
        uint256 indexed requestId,
        address collateralToken,
        uint256 amount
    );
    event WithdrawClaimed(address indexed user, uint256 indexed requestId, uint256 amount);
    event EthBufferFilled(uint256 amount);

    /**
     * @notice Get withdraw requests for a user
     * @param _user User address
     * @return Array of request IDs
     */
    function withdrawRequests(address _user) external view returns (uint256[] memory) {
        return userWithdrawRequests[_user];
    }

    /**
     * @notice Fill ETH withdraw buffer
     */
    function fillEthWithdrawBuffer() external payable {
        ethWithdrawBuffer += msg.value;
        emit EthBufferFilled(msg.value);
    }

    /**
     * @notice Calculate amount to redeem (mock)
     * @param _amount Amount to redeem
     * @param /* _assetOut */ Asset to receive
     * @return operatorDelegatorTokenTVLs Mock TVLs
     * @return _amountToRedeem Amount to redeem
     */
    function calculateAmountToRedeem(
        uint256 _amount,
        address /* _assetOut */
    )
        external
        pure
        returns (
            uint256[][] memory operatorDelegatorTokenTVLs,
            uint256 _amountToRedeem
        )
    {
        operatorDelegatorTokenTVLs = new uint256[][](1);
        operatorDelegatorTokenTVLs[0] = new uint256[](1);
        operatorDelegatorTokenTVLs[0][0] = _amount;
        _amountToRedeem = _amount;
    }

    /**
     * @notice Request a withdrawal
     * @param _amount Amount to withdraw
     * @param _assetOut Asset to receive
     */
    function withdraw(uint256 _amount, address _assetOut) external {
        uint256 requestId = nextRequestId++;
        
        withdrawRequestsById[requestId] = WithdrawRequest({
            collateralToken: _assetOut,
            withdrawRequestID: requestId,
            amountToRedeem: _amount,
            ezETHLocked: _amount,
            createdAt: block.timestamp
        });
        
        userWithdrawRequests[msg.sender].push(requestId);
        
        emit WithdrawRequestCreated(msg.sender, requestId, _assetOut, _amount);
    }

    /**
     * @notice Get outstanding withdraw requests for a user
     * @param user User address
     * @return Number of outstanding requests
     */
    function getOutstandingWithdrawRequests(address user) external view returns (uint256) {
        return userWithdrawRequests[user].length;
    }

    /**
     * @notice Claim a withdrawal
     * @param withdrawRequestIndex Index of the request
     * @param user User address
     */
    function claim(uint256 withdrawRequestIndex, address user) external {
        require(withdrawRequestIndex < userWithdrawRequests[user].length, "Invalid index");
        
        uint256 requestId = userWithdrawRequests[user][withdrawRequestIndex];
        WithdrawRequest memory request = withdrawRequestsById[requestId];
        
        // In a real implementation, this would transfer tokens
        emit WithdrawClaimed(user, requestId, request.amountToRedeem);
    }

    /**
     * @notice Get stETH pending withdraw amount
     * @return Pending amount
     */
    function stETHPendingWithdrawAmount() external view returns (uint256) {
        return stETHPendingAmount;
    }

    /**
     * @notice Set stETH pending amount (for testing)
     * @param amount Amount to set
     */
    function setStETHPendingAmount(uint256 amount) external {
        stETHPendingAmount = amount;
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {
        ethWithdrawBuffer += msg.value;
    }
}
