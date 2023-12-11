//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "./ITestingEigenpodManager.sol";
import "../EigenLayer/libraries/BeaconChainProofs.sol";

/// @dev this is just a contract to use in unit testing - allows setting return values and mimics minimal logic
contract TestingEigenpod {

  ITestingEigenpodManager eigenpodManager;

  // constructor
  constructor(ITestingEigenpodManager _eigenpodManager) {
    eigenpodManager = _eigenpodManager;
  }

  function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable {
  }

  function verifyWithdrawalCredentials(
        uint64 ,
        uint40 ,
        BeaconChainProofs.ValidatorFieldsAndBalanceProofs memory ,
        bytes32[] calldata 
  ) external {
    eigenpodManager.recordBeaconChainETHBalanceUpdate(msg.sender, 32 ether);
  }

  // Allow sending ETH to simulate staking rewards
  receive() external payable {
  }
  
}