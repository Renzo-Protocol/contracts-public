import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { BalancerRateProvider, RoleManager } from "../typechain-types";

describe("BalancerRateProvider", function () {
  let balancerRateProvider: BalancerRateProvider;
  let roleManager: RoleManager;
  let mockRestakeManager: any;
  let mockEzETH: any;
  let admin: SignerWithAddress;
  let user1: SignerWithAddress;

  beforeEach(async function () {
    [admin, user1] = await ethers.getSigners();

    // Deploy RoleManager
    const RoleManagerFactory = await ethers.getContractFactory("RoleManager");
    roleManager = (await upgrades.deployProxy(RoleManagerFactory, [admin.address], {
      initializer: "initialize",
    })) as unknown as RoleManager;
    await roleManager.waitForDeployment();

    // Deploy mock RestakeManager
    const MockRestakeManagerFactory = await ethers.getContractFactory("MockRestakeManager");
    mockRestakeManager = await MockRestakeManagerFactory.deploy();
    await mockRestakeManager.waitForDeployment();

    // Deploy mock EzETH token
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    mockEzETH = await MockERC20Factory.deploy("Renzo Restaked ETH", "ezETH", 18);
    await mockEzETH.waitForDeployment();

    // Deploy BalancerRateProvider
    const BalancerRateProviderFactory = await ethers.getContractFactory("BalancerRateProvider");
    balancerRateProvider = (await upgrades.deployProxy(
      BalancerRateProviderFactory,
      [await mockRestakeManager.getAddress(), await mockEzETH.getAddress()],
      { initializer: "initialize" }
    )) as unknown as BalancerRateProvider;
    await balancerRateProvider.waitForDeployment();
  });

  describe("Initialization", function () {
    it("should set the restake manager correctly", async function () {
      expect(await balancerRateProvider.restakeManager()).to.equal(
        await mockRestakeManager.getAddress()
      );
    });

    it("should set the ezETH token correctly", async function () {
      expect(await balancerRateProvider.ezETHToken()).to.equal(await mockEzETH.getAddress());
    });

    it("should revert if initialized with zero restake manager address", async function () {
      const BalancerRateProviderFactory = await ethers.getContractFactory("BalancerRateProvider");
      await expect(
        upgrades.deployProxy(
          BalancerRateProviderFactory,
          [ethers.ZeroAddress, await mockEzETH.getAddress()],
          { initializer: "initialize" }
        )
      ).to.be.revertedWithCustomError(balancerRateProvider, "InvalidZeroInput");
    });

    it("should revert if initialized with zero ezETH address", async function () {
      const BalancerRateProviderFactory = await ethers.getContractFactory("BalancerRateProvider");
      await expect(
        upgrades.deployProxy(
          BalancerRateProviderFactory,
          [await mockRestakeManager.getAddress(), ethers.ZeroAddress],
          { initializer: "initialize" }
        )
      ).to.be.revertedWithCustomError(balancerRateProvider, "InvalidZeroInput");
    });

    it("should not allow re-initialization", async function () {
      await expect(
        balancerRateProvider.initialize(
          await mockRestakeManager.getAddress(),
          await mockEzETH.getAddress()
        )
      ).to.be.revertedWith("Initializable: contract is already initialized");
    });
  });

  describe("Rate Calculation", function () {
    it("should return correct rate when TVL equals ezETH supply (1:1)", async function () {
      // Mint 100 ezETH
      await mockEzETH.mint(user1.address, ethers.parseEther("100"));
      // Set TVL to 100 ETH
      await mockRestakeManager.setTVL(ethers.parseEther("100"));

      const rate = await balancerRateProvider.getRate();
      expect(rate).to.equal(ethers.parseEther("1")); // 1:1 ratio
    });

    it("should return correct rate when TVL is higher than ezETH supply", async function () {
      // Mint 100 ezETH
      await mockEzETH.mint(user1.address, ethers.parseEther("100"));
      // Set TVL to 200 ETH (2x appreciation)
      await mockRestakeManager.setTVL(ethers.parseEther("200"));

      const rate = await balancerRateProvider.getRate();
      expect(rate).to.equal(ethers.parseEther("2")); // 2:1 ratio
    });

    it("should return correct rate when TVL is lower than ezETH supply", async function () {
      // Mint 100 ezETH
      await mockEzETH.mint(user1.address, ethers.parseEther("100"));
      // Set TVL to 50 ETH (slashing scenario)
      await mockRestakeManager.setTVL(ethers.parseEther("50"));

      const rate = await balancerRateProvider.getRate();
      expect(rate).to.equal(ethers.parseEther("0.5")); // 0.5:1 ratio
    });

    it("should return 1e18 when there is no ezETH supply", async function () {
      // No ezETH minted, TVL can be anything
      await mockRestakeManager.setTVL(ethers.parseEther("100"));

      const rate = await balancerRateProvider.getRate();
      // With zero supply, should return default rate of 1e18
      expect(rate).to.equal(ethers.parseEther("1"));
    });

    it("should handle large numbers correctly", async function () {
      // Mint 1 million ezETH
      await mockEzETH.mint(user1.address, ethers.parseEther("1000000"));
      // Set TVL to 1.5 million ETH
      await mockRestakeManager.setTVL(ethers.parseEther("1500000"));

      const rate = await balancerRateProvider.getRate();
      expect(rate).to.equal(ethers.parseEther("1.5"));
    });
  });

  describe("IRateProvider Interface", function () {
    it("should implement IRateProvider correctly", async function () {
      await mockEzETH.mint(user1.address, ethers.parseEther("100"));
      await mockRestakeManager.setTVL(ethers.parseEther("100"));

      // getRate should be callable and return a valid value
      const rate = await balancerRateProvider.getRate();
      expect(rate).to.be.gt(0);
    });
  });
});
