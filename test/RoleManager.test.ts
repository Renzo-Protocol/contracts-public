import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { RoleManager } from "../typechain-types";

describe("RoleManager", function () {
  let roleManager: RoleManager;
  let admin: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;

  // Role constants
  const RX_ETH_MINTER_BURNER = ethers.keccak256(ethers.toUtf8Bytes("RX_ETH_MINTER_BURNER"));
  const OPERATOR_DELEGATOR_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_DELEGATOR_ADMIN"));
  const ORACLE_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ADMIN"));
  const RESTAKE_MANAGER_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("RESTAKE_MANAGER_ADMIN"));
  const TOKEN_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("TOKEN_ADMIN"));
  const NATIVE_ETH_RESTAKE_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("NATIVE_ETH_RESTAKE_ADMIN"));
  const ERC20_REWARD_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("ERC20_REWARD_ADMIN"));
  const DEPOSIT_WITHDRAW_PAUSER = ethers.keccak256(ethers.toUtf8Bytes("DEPOSIT_WITHDRAW_PAUSER"));
  const DEFAULT_ADMIN_ROLE = ethers.ZeroHash;

  beforeEach(async function () {
    [admin, user1, user2, user3] = await ethers.getSigners();

    const RoleManagerFactory = await ethers.getContractFactory("RoleManager");
    roleManager = (await upgrades.deployProxy(RoleManagerFactory, [admin.address], {
      initializer: "initialize",
    })) as unknown as RoleManager;
    await roleManager.waitForDeployment();
  });

  describe("Initialization", function () {
    it("should set the admin as default admin", async function () {
      expect(await roleManager.hasRole(DEFAULT_ADMIN_ROLE, admin.address)).to.be.true;
    });

    it("should revert if initialized with zero address", async function () {
      const RoleManagerFactory = await ethers.getContractFactory("RoleManager");
      await expect(
        upgrades.deployProxy(RoleManagerFactory, [ethers.ZeroAddress], {
          initializer: "initialize",
        })
      ).to.be.revertedWithCustomError(roleManager, "InvalidZeroInput");
    });

    it("should not allow re-initialization", async function () {
      await expect(roleManager.initialize(user1.address)).to.be.revertedWith(
        "Initializable: contract is already initialized"
      );
    });
  });

  describe("Role Management", function () {
    describe("RX_ETH_MINTER_BURNER role", function () {
      it("should allow admin to grant minter/burner role", async function () {
        await roleManager.connect(admin).grantRole(RX_ETH_MINTER_BURNER, user1.address);
        expect(await roleManager.isRxEthMinterBurner(user1.address)).to.be.true;
      });

      it("should allow admin to revoke minter/burner role", async function () {
        await roleManager.connect(admin).grantRole(RX_ETH_MINTER_BURNER, user1.address);
        await roleManager.connect(admin).revokeRole(RX_ETH_MINTER_BURNER, user1.address);
        expect(await roleManager.isRxEthMinterBurner(user1.address)).to.be.false;
      });

      it("should not allow non-admin to grant minter/burner role", async function () {
        await expect(
          roleManager.connect(user1).grantRole(RX_ETH_MINTER_BURNER, user2.address)
        ).to.be.reverted;
      });
    });

    describe("OPERATOR_DELEGATOR_ADMIN role", function () {
      it("should correctly identify operator delegator admin", async function () {
        expect(await roleManager.isOperatorDelegatorAdmin(user1.address)).to.be.false;
        await roleManager.connect(admin).grantRole(OPERATOR_DELEGATOR_ADMIN, user1.address);
        expect(await roleManager.isOperatorDelegatorAdmin(user1.address)).to.be.true;
      });
    });

    describe("ORACLE_ADMIN role", function () {
      it("should correctly identify oracle admin", async function () {
        expect(await roleManager.isOracleAdmin(user1.address)).to.be.false;
        await roleManager.connect(admin).grantRole(ORACLE_ADMIN, user1.address);
        expect(await roleManager.isOracleAdmin(user1.address)).to.be.true;
      });
    });

    describe("RESTAKE_MANAGER_ADMIN role", function () {
      it("should correctly identify restake manager admin", async function () {
        expect(await roleManager.isRestakeManagerAdmin(user1.address)).to.be.false;
        await roleManager.connect(admin).grantRole(RESTAKE_MANAGER_ADMIN, user1.address);
        expect(await roleManager.isRestakeManagerAdmin(user1.address)).to.be.true;
      });
    });

    describe("TOKEN_ADMIN role", function () {
      it("should correctly identify token admin", async function () {
        expect(await roleManager.isTokenAdmin(user1.address)).to.be.false;
        await roleManager.connect(admin).grantRole(TOKEN_ADMIN, user1.address);
        expect(await roleManager.isTokenAdmin(user1.address)).to.be.true;
      });
    });

    describe("NATIVE_ETH_RESTAKE_ADMIN role", function () {
      it("should correctly identify native ETH restake admin", async function () {
        expect(await roleManager.isNativeEthRestakeAdmin(user1.address)).to.be.false;
        await roleManager.connect(admin).grantRole(NATIVE_ETH_RESTAKE_ADMIN, user1.address);
        expect(await roleManager.isNativeEthRestakeAdmin(user1.address)).to.be.true;
      });
    });

    describe("ERC20_REWARD_ADMIN role", function () {
      it("should correctly identify ERC20 rewards admin", async function () {
        expect(await roleManager.isERC20RewardsAdmin(user1.address)).to.be.false;
        await roleManager.connect(admin).grantRole(ERC20_REWARD_ADMIN, user1.address);
        expect(await roleManager.isERC20RewardsAdmin(user1.address)).to.be.true;
      });
    });

    describe("DEPOSIT_WITHDRAW_PAUSER role", function () {
      it("should correctly identify deposit/withdraw pauser", async function () {
        expect(await roleManager.isDepositWithdrawPauser(user1.address)).to.be.false;
        await roleManager.connect(admin).grantRole(DEPOSIT_WITHDRAW_PAUSER, user1.address);
        expect(await roleManager.isDepositWithdrawPauser(user1.address)).to.be.true;
      });
    });
  });

  describe("Multiple Roles", function () {
    it("should allow a user to have multiple roles", async function () {
      await roleManager.connect(admin).grantRole(RX_ETH_MINTER_BURNER, user1.address);
      await roleManager.connect(admin).grantRole(ORACLE_ADMIN, user1.address);
      await roleManager.connect(admin).grantRole(TOKEN_ADMIN, user1.address);

      expect(await roleManager.isRxEthMinterBurner(user1.address)).to.be.true;
      expect(await roleManager.isOracleAdmin(user1.address)).to.be.true;
      expect(await roleManager.isTokenAdmin(user1.address)).to.be.true;
    });

    it("should allow multiple users to have the same role", async function () {
      await roleManager.connect(admin).grantRole(ORACLE_ADMIN, user1.address);
      await roleManager.connect(admin).grantRole(ORACLE_ADMIN, user2.address);
      await roleManager.connect(admin).grantRole(ORACLE_ADMIN, user3.address);

      expect(await roleManager.isOracleAdmin(user1.address)).to.be.true;
      expect(await roleManager.isOracleAdmin(user2.address)).to.be.true;
      expect(await roleManager.isOracleAdmin(user3.address)).to.be.true;
    });
  });

  describe("Role Renunciation", function () {
    it("should allow a user to renounce their own role", async function () {
      await roleManager.connect(admin).grantRole(TOKEN_ADMIN, user1.address);
      expect(await roleManager.isTokenAdmin(user1.address)).to.be.true;

      await roleManager.connect(user1).renounceRole(TOKEN_ADMIN, user1.address);
      expect(await roleManager.isTokenAdmin(user1.address)).to.be.false;
    });

    it("should not allow a user to renounce another user's role", async function () {
      await roleManager.connect(admin).grantRole(TOKEN_ADMIN, user1.address);
      await expect(
        roleManager.connect(user2).renounceRole(TOKEN_ADMIN, user1.address)
      ).to.be.reverted;
    });
  });

  describe("Admin Role Transfer", function () {
    it("should allow admin to grant admin role to another user", async function () {
      await roleManager.connect(admin).grantRole(DEFAULT_ADMIN_ROLE, user1.address);
      expect(await roleManager.hasRole(DEFAULT_ADMIN_ROLE, user1.address)).to.be.true;
    });

    it("should allow new admin to manage roles", async function () {
      await roleManager.connect(admin).grantRole(DEFAULT_ADMIN_ROLE, user1.address);
      await roleManager.connect(user1).grantRole(ORACLE_ADMIN, user2.address);
      expect(await roleManager.isOracleAdmin(user2.address)).to.be.true;
    });
  });

  describe("Role Constants", function () {
    it("should have correct role constant values", async function () {
      expect(await roleManager.RX_ETH_MINTER_BURNER()).to.equal(RX_ETH_MINTER_BURNER);
      expect(await roleManager.OPERATOR_DELEGATOR_ADMIN()).to.equal(OPERATOR_DELEGATOR_ADMIN);
      expect(await roleManager.ORACLE_ADMIN()).to.equal(ORACLE_ADMIN);
      expect(await roleManager.RESTAKE_MANAGER_ADMIN()).to.equal(RESTAKE_MANAGER_ADMIN);
      expect(await roleManager.TOKEN_ADMIN()).to.equal(TOKEN_ADMIN);
      expect(await roleManager.NATIVE_ETH_RESTAKE_ADMIN()).to.equal(NATIVE_ETH_RESTAKE_ADMIN);
      expect(await roleManager.ERC20_REWARD_ADMIN()).to.equal(ERC20_REWARD_ADMIN);
      expect(await roleManager.DEPOSIT_WITHDRAW_PAUSER()).to.equal(DEPOSIT_WITHDRAW_PAUSER);
    });
  });
});
