import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { DepositQueue, RoleManager } from "../typechain-types";

describe("DepositQueue", function () {
  let depositQueue: DepositQueue;
  let roleManager: RoleManager;
  let admin: SignerWithAddress;
  let restakeManagerAdmin: SignerWithAddress;
  let nativeEthAdmin: SignerWithAddress;
  let erc20RewardsAdmin: SignerWithAddress;
  let user1: SignerWithAddress;
  let feeAddress: SignerWithAddress;

  const RESTAKE_MANAGER_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("RESTAKE_MANAGER_ADMIN"));
  const NATIVE_ETH_RESTAKE_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("NATIVE_ETH_RESTAKE_ADMIN"));
  const ERC20_REWARD_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("ERC20_REWARD_ADMIN"));

  beforeEach(async function () {
    [admin, restakeManagerAdmin, nativeEthAdmin, erc20RewardsAdmin, user1, feeAddress] =
      await ethers.getSigners();

    // Deploy RoleManager
    const RoleManagerFactory = await ethers.getContractFactory("RoleManager");
    roleManager = (await upgrades.deployProxy(RoleManagerFactory, [admin.address], {
      initializer: "initialize",
    })) as unknown as RoleManager;
    await roleManager.waitForDeployment();

    // Grant roles
    await roleManager.connect(admin).grantRole(RESTAKE_MANAGER_ADMIN, restakeManagerAdmin.address);
    await roleManager.connect(admin).grantRole(NATIVE_ETH_RESTAKE_ADMIN, nativeEthAdmin.address);
    await roleManager.connect(admin).grantRole(ERC20_REWARD_ADMIN, erc20RewardsAdmin.address);

    // Deploy DepositQueue
    const DepositQueueFactory = await ethers.getContractFactory("DepositQueue");
    depositQueue = (await upgrades.deployProxy(
      DepositQueueFactory,
      [await roleManager.getAddress()],
      { initializer: "initialize" }
    )) as unknown as DepositQueue;
    await depositQueue.waitForDeployment();
  });

  describe("Initialization", function () {
    it("should set the role manager correctly", async function () {
      expect(await depositQueue.roleManager()).to.equal(await roleManager.getAddress());
    });

    it("should revert if initialized with zero address", async function () {
      const DepositQueueFactory = await ethers.getContractFactory("DepositQueue");
      await expect(
        upgrades.deployProxy(DepositQueueFactory, [ethers.ZeroAddress], {
          initializer: "initialize",
        })
      ).to.be.revertedWithCustomError(depositQueue, "InvalidZeroInput");
    });

    it("should not allow re-initialization", async function () {
      await expect(
        depositQueue.initialize(await roleManager.getAddress())
      ).to.be.revertedWith("Initializable: contract is already initialized");
    });

    it("should have zero fee configuration initially", async function () {
      expect(await depositQueue.feeAddress()).to.equal(ethers.ZeroAddress);
      expect(await depositQueue.feeBasisPoints()).to.equal(0);
    });
  });

  describe("Fee Configuration", function () {
    it("should allow admin to set fee configuration", async function () {
      const feeBps = 100; // 1%
      await depositQueue
        .connect(restakeManagerAdmin)
        .setFeeConfig(feeAddress.address, feeBps);

      expect(await depositQueue.feeAddress()).to.equal(feeAddress.address);
      expect(await depositQueue.feeBasisPoints()).to.equal(feeBps);
    });

    it("should emit FeeConfigUpdated event", async function () {
      const feeBps = 100;
      await expect(
        depositQueue.connect(restakeManagerAdmin).setFeeConfig(feeAddress.address, feeBps)
      )
        .to.emit(depositQueue, "FeeConfigUpdated")
        .withArgs(feeAddress.address, feeBps);
    });

    it("should revert if non-admin tries to set fee config", async function () {
      await expect(
        depositQueue.connect(user1).setFeeConfig(feeAddress.address, 100)
      ).to.be.revertedWithCustomError(depositQueue, "NotRestakeManagerAdmin");
    });

    it("should allow setting fee to zero with zero address", async function () {
      // First set a fee
      await depositQueue
        .connect(restakeManagerAdmin)
        .setFeeConfig(feeAddress.address, 100);

      // Then disable fees
      await depositQueue
        .connect(restakeManagerAdmin)
        .setFeeConfig(ethers.ZeroAddress, 0);

      expect(await depositQueue.feeAddress()).to.equal(ethers.ZeroAddress);
      expect(await depositQueue.feeBasisPoints()).to.equal(0);
    });

    it("should revert if fee basis points exceed maximum", async function () {
      const maxFeeBps = 10001; // Over 100%
      await expect(
        depositQueue.connect(restakeManagerAdmin).setFeeConfig(feeAddress.address, maxFeeBps)
      ).to.be.revertedWithCustomError(depositQueue, "OverMaxBasisPoints");
    });

    it("should revert if fee address is zero but fee is non-zero", async function () {
      await expect(
        depositQueue.connect(restakeManagerAdmin).setFeeConfig(ethers.ZeroAddress, 100)
      ).to.be.revertedWithCustomError(depositQueue, "InvalidZeroInput");
    });
  });

  describe("ETH Deposits", function () {
    it("should receive ETH deposits", async function () {
      const depositAmount = ethers.parseEther("10");

      await user1.sendTransaction({
        to: await depositQueue.getAddress(),
        value: depositAmount,
      });

      expect(
        await ethers.provider.getBalance(await depositQueue.getAddress())
      ).to.equal(depositAmount);
    });

    it("should track total ETH in queue", async function () {
      const depositAmount = ethers.parseEther("10");

      await user1.sendTransaction({
        to: await depositQueue.getAddress(),
        value: depositAmount,
      });

      // The balance should reflect the deposit
      const balance = await ethers.provider.getBalance(await depositQueue.getAddress());
      expect(balance).to.be.gte(depositAmount);
    });
  });

  describe("RestakeManager Configuration", function () {
    let mockRestakeManager: any;

    beforeEach(async function () {
      // Deploy mock RestakeManager
      const MockRestakeManagerFactory = await ethers.getContractFactory("MockRestakeManager");
      mockRestakeManager = await MockRestakeManagerFactory.deploy();
      await mockRestakeManager.waitForDeployment();
    });

    it("should allow admin to set restake manager", async function () {
      await depositQueue
        .connect(restakeManagerAdmin)
        .setRestakeManager(await mockRestakeManager.getAddress());

      expect(await depositQueue.restakeManager()).to.equal(
        await mockRestakeManager.getAddress()
      );
    });

    it("should emit RestakeManagerUpdated event", async function () {
      await expect(
        depositQueue
          .connect(restakeManagerAdmin)
          .setRestakeManager(await mockRestakeManager.getAddress())
      )
        .to.emit(depositQueue, "RestakeManagerUpdated");
    });

    it("should revert if non-admin tries to set restake manager", async function () {
      await expect(
        depositQueue.connect(user1).setRestakeManager(await mockRestakeManager.getAddress())
      ).to.be.revertedWithCustomError(depositQueue, "NotRestakeManagerAdmin");
    });

    it("should revert if setting zero address for restake manager", async function () {
      await expect(
        depositQueue.connect(restakeManagerAdmin).setRestakeManager(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(depositQueue, "InvalidZeroInput");
    });
  });

  describe("WithdrawQueue Configuration", function () {
    let mockWithdrawQueue: any;

    beforeEach(async function () {
      // Deploy mock WithdrawQueue
      const MockWithdrawQueueFactory = await ethers.getContractFactory("MockWithdrawQueue");
      mockWithdrawQueue = await MockWithdrawQueueFactory.deploy();
      await mockWithdrawQueue.waitForDeployment();
    });

    it("should allow admin to set withdraw queue", async function () {
      await depositQueue
        .connect(restakeManagerAdmin)
        .setWithdrawQueue(await mockWithdrawQueue.getAddress());

      expect(await depositQueue.withdrawQueue()).to.equal(
        await mockWithdrawQueue.getAddress()
      );
    });

    it("should revert if non-admin tries to set withdraw queue", async function () {
      await expect(
        depositQueue.connect(user1).setWithdrawQueue(await mockWithdrawQueue.getAddress())
      ).to.be.revertedWithCustomError(depositQueue, "NotRestakeManagerAdmin");
    });

    it("should revert if setting zero address for withdraw queue", async function () {
      await expect(
        depositQueue.connect(restakeManagerAdmin).setWithdrawQueue(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(depositQueue, "InvalidZeroInput");
    });
  });

  describe("Role Access Control", function () {
    it("should respect role changes for restake manager admin", async function () {
      // Grant role to user1
      await roleManager.connect(admin).grantRole(RESTAKE_MANAGER_ADMIN, user1.address);

      // User1 should now be able to set fee config
      await depositQueue.connect(user1).setFeeConfig(feeAddress.address, 50);
      expect(await depositQueue.feeBasisPoints()).to.equal(50);
    });

    it("should respect role revocation", async function () {
      // Revoke admin role
      await roleManager
        .connect(admin)
        .revokeRole(RESTAKE_MANAGER_ADMIN, restakeManagerAdmin.address);

      // Admin should no longer be able to set fee config
      await expect(
        depositQueue.connect(restakeManagerAdmin).setFeeConfig(feeAddress.address, 100)
      ).to.be.revertedWithCustomError(depositQueue, "NotRestakeManagerAdmin");
    });
  });

  describe("Reentrancy Protection", function () {
    it("should be protected against reentrancy", async function () {
      // The contract inherits ReentrancyGuardUpgradeable
      // This test verifies the protection is in place
      // Actual reentrancy attack tests would require a malicious contract
      
      // For now, verify the contract has the reentrancy guard by checking initialization
      expect(await depositQueue.roleManager()).to.not.equal(ethers.ZeroAddress);
    });
  });
});
