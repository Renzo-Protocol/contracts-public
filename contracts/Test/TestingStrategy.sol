//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "../EigenLayer/interfaces/IStrategy.sol";

/// @dev this is just a contract to use in unit testing - allows setting return values and mimics minimal logic
contract TestingStrategy {

  uint256 public underlyingTokens;
  function setUnderlyingTokens(uint256 _tokens) external {
    underlyingTokens = _tokens;
  }

  uint256 public shares;
  function setShares(uint256 _shares) external {
    shares = _shares;
  }

  /// @dev uses the ratio of underlying tokens to shares to calculate the amount of underlying shares to return
  function underlyingToSharesView(uint256 amountUnderlying) external view returns (uint256){
    return amountUnderlying * underlyingTokens / shares;
  }

  function sharesToUnderlyingView(uint256 _shares) external view returns (uint256){
    return _shares * shares / underlyingTokens;
  }

  // Track the number of tokens deposited into this strategy by each account
  mapping(address => uint256) public accountTokens;
  function setAccountTokens(address _account, uint256 _tokens) external {
    accountTokens[_account] = _tokens;
  }

  function withdrawTokens( IERC20 token, address _destination, uint256 amount) external {
    token.transfer(_destination, amount);
  }

  function userUnderlyingView(address user) external view returns (uint256) {
    return accountTokens[user]; 
  }

}