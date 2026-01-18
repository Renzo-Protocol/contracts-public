import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { RenzoOracle, RoleManager } from "../typechain-types";

describe("RenzoOracle", function () {
  let renzoOracle: RenzoOracle;
  let roleManager: RoleManager;
  let admin: SignerWithAddress;
  let oracleAdmin: SignerWithAddress;
  let user1: SignerWithAddress;

  const ORACLE_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ADMIN"));

  // Mock token and oracle addresses
  let mockToken: string;
  let mockChainlinkOracle: any;

  beforeEach(async function () {
    [admin, oracleAdmin, user1] = await ethers.getSigners();

    // Deploy RoleManager
    const RoleManagerFactory = await ethers.getContractFactory("RoleManager");
    roleManager = (await upgrades.deployProxy(RoleManagerFactory, [admin.address], {
      initializer: "initialize",
    })) as unknown as RoleManager;
    await roleManager.waitForDeployment();

    // Grant oracle admin role
    await roleManager.connect(admin).grantRole(ORACLE_ADMIN, oracleAdmin.address);

    // Deploy mock Chainlink oracle
    const MockOracleFactory = await ethers.getContractFactory("MockChainlinkOracle");
    mockChainlinkOracle = await MockOracleFactory.deploy(
      18, // decimals
      ethers.parseEther("1") // initial price: 1 ETH
    );
    await mockChainlinkOracle.waitForDeployment();

    // Deploy mock ERC20 token
    const MockTokenFactory = await ethers.getContractFactory("MockERC20");
    const mockTokenContract = await MockTokenFactory.deploy("Mock Token", "MTK", 18);
    await mockTokenContract.waitForDeployment();
    mockToken = await mockTokenContract.getAddress();

    // Deploy RenzoOracle
    const RenzoOracleFactory = await ethers.getContractFactory("RenzoOracle");
    renzoOracle = (await upgrades.deployProxy(
      RenzoOracleFactory,
      [await roleManager.getAddress()],
      { initializer: "initialize" }
    )) as unknown as RenzoOracle;
    await renzoOracle.waitForDeployment();
  });

  describe("Initialization", function () {
    it("should set the role manager correctly", async function () {
      expect(await renzoOracle.roleManager()).to.equal(await roleManager.getAddress());
    });

    it("should revert if initialized with zero address", async function () {
      const RenzoOracleFactory = await ethers.getContractFactory("RenzoOracle");
      await expect(
        upgrades.deployProxy(RenzoOracleFactory, [ethers.ZeroAddress], {
          initializer: "initialize",
        })
      ).to.be.revertedWithCustomError(renzoOracle, "InvalidZeroInput");
    });

    it("should not allow re-initialization", async function () {
      await expect(
        renzoOracle.initialize(await roleManager.getAddress())
      ).to.be.revertedWith("Initializable: contract is already initialized");
    });
  });

  describe("Oracle Configuration", function () {
    it("should allow oracle admin to set token oracle", async function () {
      await renzoOracle
        .connect(oracleAdmin)
        .setOracleAddress(mockToken, await mockChainlinkOracle.getAddress());

      expect(await renzoOracle.tokenOracleLookup(mockToken)).to.equal(
        await mockChainlinkOracle.getAddress()
      );
    });

    it("should emit OracleAddressUpdated event", async function () {
      await expect(
        renzoOracle
          .connect(oracleAdmin)
          .setOracleAddress(mockToken, await mockChainlinkOracle.getAddress())
      )
        .to.emit(renzoOracle, "OracleAddressUpdated")
        .withArgs(mockToken, await mockChainlinkOracle.getAddress());
    });

    it("should revert if non-admin tries to set oracle", async function () {
      await expect(
        renzoOracle
          .connect(user1)
          .setOracleAddress(mockToken, await mockChainlinkOracle.getAddress())
      ).to.be.revertedWithCustomError(renzoOracle, "NotOracleAdmin");
    });

    it("should revert if setting zero address for oracle", async function () {
      await expect(
        renzoOracle.connect(oracleAdmin).setOracleAddress(mockToken, ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(renzoOracle, "InvalidZeroInput");
    });

    it("should revert if setting oracle for zero token address", async function () {
      await expect(
        renzoOracle
          .connect(oracleAdmin)
          .setOracleAddress(ethers.ZeroAddress, await mockChainlinkOracle.getAddress())
      ).to.be.revertedWithCustomError(renzoOracle, "InvalidZeroInput");
    });

    it("should allow updating an existing oracle", async function () {
      // Set initial oracle
      await renzoOracle
        .connect(oracleAdmin)
        .setOracleAddress(mockToken, await mockChainlinkOracle.getAddress());

      // Deploy new oracle
      const MockOracleFactory = await ethers.getContractFactory("MockChainlinkOracle");
      const newOracle = await MockOracleFactory.deploy(18, ethers.parseEther("2"));
      await newOracle.waitForDeployment();

      // Update to new oracle
      await renzoOracle
        .connect(oracleAdmin)
        .setOracleAddress(mockToken, await newOracle.getAddress());

      expect(await renzoOracle.tokenOracleLookup(mockToken)).to.equal(
        await newOracle.getAddress()
      );
    });
  });

  describe("Price Lookups", function () {
    beforeEach(async function () {
      await renzoOracle
        .connect(oracleAdmin)
        .setOracleAddress(mockToken, await mockChainlinkOracle.getAddress());
    });

    it("should return correct price from oracle", async function () {
      const price = await renzoOracle.lookupTokenValue(mockToken, ethers.parseEther("1"));
      expect(price).to.equal(ethers.parseEther("1"));
    });

    it("should scale price correctly for different amounts", async function () {
      const amount = ethers.parseEther("10");
      const price = await renzoOracle.lookupTokenValue(mockToken, amount);
      expect(price).to.equal(ethers.parseEther("10"));
    });

    it("should handle price changes", async function () {
      // Update price in mock oracle
      await mockChainlinkOracle.setPrice(ethers.parseEther("2"));

      const price = await renzoOracle.lookupTokenValue(mockToken, ethers.parseEther("1"));
      expect(price).to.equal(ethers.parseEther("2"));
    });

    it("should revert for token without oracle", async function () {
      const randomToken = ethers.Wallet.createRandom().address;
      await expect(
        renzoOracle.lookupTokenValue(randomToken, ethers.parseEther("1"))
      ).to.be.revertedWithCustomError(renzoOracle, "OracleNotFound");
    });

    it("should revert if oracle returns stale data", async function () {
      // Set oracle to return stale data (timestamp too old)
      await mockChainlinkOracle.setStale(true);

      await expect(
        renzoOracle.lookupTokenValue(mockToken, ethers.parseEther("1"))
      ).to.be.revertedWithCustomError(renzoOracle, "OracleStaleData");
    });

    it("should revert if oracle returns zero/negative price", async function () {
      await mockChainlinkOracle.setPrice(0);

      await expect(
        renzoOracle.lookupTokenValue(mockToken, ethers.parseEther("1"))
      ).to.be.revertedWithCustomError(renzoOracle, "InvalidOraclePrice");
    });
  });

  describe("Mint Amount Calculation", function () {
    let mockEzETH: any;
    let restakeManager: any;

    beforeEach(async function () {
      await renzoOracle
        .connect(oracleAdmin)
        .setOracleAddress(mockToken, await mockChainlinkOracle.getAddress());
    });

    it("should calculate mint amount correctly with 1:1 ratio", async function () {
      const depositAmount = ethers.parseEther("10");
      const existingEzETH = ethers.parseEther("100");
      const totalTVL = ethers.parseEther("100");

      const mintAmount = await renzoOracle.calculateMintAmount(
        totalTVL,
        depositAmount,
        existingEzETH
      );

      // With 1:1 backing, should mint same amount as deposit value
      expect(mintAmount).to.equal(depositAmount);
    });

    it("should calculate mint amount correctly when no existing supply", async function () {
      const depositAmount = ethers.parseEther("10");
      const existingEzETH = 0n;
      const totalTVL = 0n;

      const mintAmount = await renzoOracle.calculateMintAmount(
        totalTVL,
        depositAmount,
        existingEzETH
      );

      // First deposit should mint 1:1
      expect(mintAmount).to.equal(depositAmount);
    });
  });

  describe("Redeem Amount Calculation", function () {
    beforeEach(async function () {
      await renzoOracle
        .connect(oracleAdmin)
        .setOracleAddress(mockToken, await mockChainlinkOracle.getAddress());
    });

    it("should calculate redeem amount correctly", async function () {
      const burnAmount = ethers.parseEther("10");
      const existingEzETH = ethers.parseEther("100");
      const totalTVL = ethers.parseEther("100");

      const redeemAmount = await renzoOracle.calculateRedeemAmount(
        burnAmount,
        existingEzETH,
        totalTVL
      );

      // With 1:1 backing, should redeem same value as burn amount
      expect(redeemAmount).to.equal(burnAmount);
    });

    it("should calculate redeem amount when value has appreciated", async function () {
      const burnAmount = ethers.parseEther("10");
      const existingEzETH = ethers.parseEther("100");
      const totalTVL = ethers.parseEther("200"); // 2x value

      const redeemAmount = await renzoOracle.calculateRedeemAmount(
        burnAmount,
        existingEzETH,
        totalTVL
      );

      // Should redeem 2x the burn amount
      expect(redeemAmount).to.equal(ethers.parseEther("20"));
    });
  });

  describe("Role Changes", function () {
    it("should respect new oracle admin", async function () {
      await roleManager.connect(admin).grantRole(ORACLE_ADMIN, user1.address);

      await renzoOracle
        .connect(user1)
        .setOracleAddress(mockToken, await mockChainlinkOracle.getAddress());

      expect(await renzoOracle.tokenOracleLookup(mockToken)).to.equal(
        await mockChainlinkOracle.getAddress()
      );
    });

    it("should revoke oracle admin access correctly", async function () {
      await roleManager.connect(admin).revokeRole(ORACLE_ADMIN, oracleAdmin.address);

      await expect(
        renzoOracle
          .connect(oracleAdmin)
          .setOracleAddress(mockToken, await mockChainlinkOracle.getAddress())
      ).to.be.revertedWithCustomError(renzoOracle, "NotOracleAdmin");
    });
  });
});
