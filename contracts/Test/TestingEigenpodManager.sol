//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "./TestingEigenpod.sol";
import "./ITestingEigenpodManager.sol";
import "./TestingStrategyManager.sol";

/// @dev this is just a contract to use in unit testing - allows setting return values and mimics minimal logic
contract TestingEigenpodManager is ITestingEigenpodManager{
  mapping (address => address) eigenpodsToOwners;
  mapping(address => int256) public podOwnerShares;
  TestingStrategyManager testingStrategyManager;

  constructor(TestingStrategyManager _testingStrategyManager) {
    testingStrategyManager = _testingStrategyManager;
  }

  function createPod() external{
    TestingEigenpod pod = new TestingEigenpod(this);
    eigenpodsToOwners[msg.sender] = address(pod);
  }

  function ownerToPod(address podOwner) external view returns (address){
    return eigenpodsToOwners[podOwner];
  }

  function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable {
    TestingEigenpod pod = TestingEigenpod(payable(eigenpodsToOwners[msg.sender]));
    pod.stake{value: msg.value}(pubkey, signature, depositDataRoot);
  }

  function recordBeaconChainETHBalanceUpdate(address podOwner, int256 sharesDelta) external {
    podOwnerShares[podOwner] += sharesDelta;
    testingStrategyManager.setStakeryStrategyShares(podOwner, uint256(podOwnerShares[podOwner]));
  }

}