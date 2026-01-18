// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockRestakeManager
 * @notice A mock RestakeManager contract for testing purposes
 * @dev Implements minimal IRestakeManager interface for testing
 */
contract MockRestakeManager {
    address public depositQueue;
    uint256 public totalTVL;
    
    mapping(address => bool) public collateralTokens;
    address[] public collateralTokenList;

    event ETHDeposited(address indexed sender, uint256 amount);
    event TokenDeposited(address indexed token, address indexed sender, uint256 amount);

    /**
     * @notice Set the deposit queue address
     * @param _depositQueue Address of the deposit queue
     */
    function setDepositQueue(address _depositQueue) external {
        depositQueue = _depositQueue;
    }

    /**
     * @notice Deposit ETH into the protocol
     */
    function depositETH() external payable {
        emit ETHDeposited(msg.sender, msg.value);
    }

    /**
     * @notice Deposit an ERC20 token
     * @param _collateralToken Token address
     * @param _amount Amount to deposit
     */
    function deposit(IERC20 _collateralToken, uint256 _amount) external {
        _collateralToken.transferFrom(msg.sender, address(this), _amount);
        emit TokenDeposited(address(_collateralToken), msg.sender, _amount);
    }

    /**
     * @notice Calculate TVLs (mock implementation)
     * @return operatorDelegatorTVLs Mock operator delegator TVLs
     * @return collateralTokenTVLs Mock collateral token TVLs
     * @return total Total TVL
     */
    function calculateTVLs()
        external
        view
        returns (
            uint256[][] memory operatorDelegatorTVLs,
            uint256[] memory collateralTokenTVLs,
            uint256 total
        )
    {
        operatorDelegatorTVLs = new uint256[][](1);
        operatorDelegatorTVLs[0] = new uint256[](1);
        operatorDelegatorTVLs[0][0] = totalTVL;
        
        collateralTokenTVLs = new uint256[](1);
        collateralTokenTVLs[0] = totalTVL;
        
        total = totalTVL;
    }

    /**
     * @notice Set mock TVL for testing
     * @param _tvl TVL to set
     */
    function setTVL(uint256 _tvl) external {
        totalTVL = _tvl;
    }

    /**
     * @notice Add a collateral token
     * @param token Token to add
     */
    function addCollateralToken(address token) external {
        collateralTokens[token] = true;
        collateralTokenList.push(token);
    }

    /**
     * @notice Get collateral token index
     * @param _collateralToken Token address
     * @return Index of the token
     */
    function getCollateralTokenIndex(IERC20 _collateralToken) external view returns (uint256) {
        for (uint256 i = 0; i < collateralTokenList.length; i++) {
            if (collateralTokenList[i] == address(_collateralToken)) {
                return i;
            }
        }
        revert("Token not found");
    }

    /**
     * @notice Get number of collateral tokens
     * @return Length of collateral token list
     */
    function getCollateralTokensLength() external view returns (uint256) {
        return collateralTokenList.length;
    }

    /**
     * @notice Stake ETH in operator delegator (mock)
     */
    function stakeEthInOperatorDelegator(
        address /* operatorDelegator */,
        bytes calldata /* pubkey */,
        bytes calldata /* signature */,
        bytes32 /* depositDataRoot */
    ) external payable {
        // Mock implementation
    }

    /**
     * @notice Deposit token rewards from protocol (mock)
     */
    function depositTokenRewardsFromProtocol(IERC20 _token, uint256 _amount) external {
        _token.transferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}
}
