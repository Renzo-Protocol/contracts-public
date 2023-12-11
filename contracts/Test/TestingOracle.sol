//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @dev this is just a contract to use in unit testing - allows setting return values and mimics minimal logic
contract TestingOracle {

  uint80 roundId; 
  int256 answer;
  uint256 startedAt;
  uint256 updatedAt;
  uint80 answeredInRound;

  uint8 public internalDecimals;

  constructor() {
        internalDecimals = 18;
    }

  function setLatestRoundData(
    uint80 _roundId,
    int256 _answer,
    uint256 _startedAt,
    uint256 _updatedAt,
    uint80 _answeredInRound
    ) external
  {
    roundId = _roundId;
    answer = _answer;
    startedAt = _startedAt;
    updatedAt = _updatedAt;
    answeredInRound = _answeredInRound;
  }
  

function latestRoundData()
    external
    view
    returns (uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound){
      return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

  function setDecimals(uint8 _decimals) external {
    internalDecimals = _decimals;
  }

  function decimals() external view returns (uint8){
    return internalDecimals;
  }

}