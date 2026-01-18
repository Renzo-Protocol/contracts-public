import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { EzEthToken, RoleManager } from "../typechain-types";

describe("EzEthToken", function () {
  let ezETH: EzEthToken;
  let roleManager: RoleManager;
  let admin: SignerWithAddress;
  let minter: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  const RX_ETH_MINTER_BURNER = ethers.keccak256(ethers.toUtf8Bytes("RX_ETH_MINTER_BURNER"));

  beforeEach(async function () {
    [admin, minter, user1, user2] = await ethers.getSigners();

    // Deploy RoleManager first
    const RoleManagerFactory = await ethers.getContractFactory("RoleManager");
    roleManager = (await upgrades.deployProxy(RoleManagerFactory, [admin.address], {
      initializer: "initialize",
    })) as unknown as RoleManager;
    await roleManager.waitForDeployment();

    // Grant minter role
    await roleManager.connect(admin).grantRole(RX_ETH_MINTER_BURNER, minter.address);

    // Deploy EzEthToken
    const EzEthTokenFactory = await ethers.getContractFactory("EzEthToken");
    ezETH = (await upgrades.deployProxy(
      EzEthTokenFactory,
      [await roleManager.getAddress()],
      { initializer: "initialize" }
    )) as unknown as EzEthToken;
    await ezETH.waitForDeployment();
  });

  describe("Initialization", function () {
    it("should have correct name", async function () {
      expect(await ezETH.name()).to.equal("Renzo Restaked ETH");
    });

    it("should have correct symbol", async function () {
      expect(await ezETH.symbol()).to.equal("ezETH");
    });

    it("should have 18 decimals", async function () {
      expect(await ezETH.decimals()).to.equal(18);
    });

    it("should have zero initial supply", async function () {
      expect(await ezETH.totalSupply()).to.equal(0);
    });

    it("should set the role manager correctly", async function () {
      expect(await ezETH.roleManager()).to.equal(await roleManager.getAddress());
    });

    it("should revert if initialized with zero address", async function () {
      const EzEthTokenFactory = await ethers.getContractFactory("EzEthToken");
      await expect(
        upgrades.deployProxy(EzEthTokenFactory, [ethers.ZeroAddress], {
          initializer: "initialize",
        })
      ).to.be.revertedWithCustomError(ezETH, "InvalidZeroInput");
    });

    it("should not allow re-initialization", async function () {
      await expect(
        ezETH.initialize(await roleManager.getAddress())
      ).to.be.revertedWith("Initializable: contract is already initialized");
    });
  });

  describe("Minting", function () {
    it("should allow minter to mint tokens", async function () {
      const amount = ethers.parseEther("100");
      await ezETH.connect(minter).mint(user1.address, amount);
      expect(await ezETH.balanceOf(user1.address)).to.equal(amount);
    });

    it("should increase total supply when minting", async function () {
      const amount = ethers.parseEther("100");
      await ezETH.connect(minter).mint(user1.address, amount);
      expect(await ezETH.totalSupply()).to.equal(amount);
    });

    it("should emit Transfer event on mint", async function () {
      const amount = ethers.parseEther("100");
      await expect(ezETH.connect(minter).mint(user1.address, amount))
        .to.emit(ezETH, "Transfer")
        .withArgs(ethers.ZeroAddress, user1.address, amount);
    });

    it("should revert if non-minter tries to mint", async function () {
      const amount = ethers.parseEther("100");
      await expect(
        ezETH.connect(user1).mint(user1.address, amount)
      ).to.be.revertedWithCustomError(ezETH, "NotMinterBurner");
    });

    it("should allow minting to multiple addresses", async function () {
      const amount1 = ethers.parseEther("100");
      const amount2 = ethers.parseEther("200");
      
      await ezETH.connect(minter).mint(user1.address, amount1);
      await ezETH.connect(minter).mint(user2.address, amount2);
      
      expect(await ezETH.balanceOf(user1.address)).to.equal(amount1);
      expect(await ezETH.balanceOf(user2.address)).to.equal(amount2);
      expect(await ezETH.totalSupply()).to.equal(amount1 + amount2);
    });
  });

  describe("Burning", function () {
    beforeEach(async function () {
      // Mint some tokens first
      await ezETH.connect(minter).mint(user1.address, ethers.parseEther("1000"));
    });

    it("should allow minter to burn tokens from user", async function () {
      const burnAmount = ethers.parseEther("100");
      const initialBalance = await ezETH.balanceOf(user1.address);
      
      await ezETH.connect(minter).burn(user1.address, burnAmount);
      
      expect(await ezETH.balanceOf(user1.address)).to.equal(initialBalance - burnAmount);
    });

    it("should decrease total supply when burning", async function () {
      const burnAmount = ethers.parseEther("100");
      const initialSupply = await ezETH.totalSupply();
      
      await ezETH.connect(minter).burn(user1.address, burnAmount);
      
      expect(await ezETH.totalSupply()).to.equal(initialSupply - burnAmount);
    });

    it("should emit Transfer event on burn", async function () {
      const burnAmount = ethers.parseEther("100");
      await expect(ezETH.connect(minter).burn(user1.address, burnAmount))
        .to.emit(ezETH, "Transfer")
        .withArgs(user1.address, ethers.ZeroAddress, burnAmount);
    });

    it("should revert if non-minter tries to burn", async function () {
      const burnAmount = ethers.parseEther("100");
      await expect(
        ezETH.connect(user2).burn(user1.address, burnAmount)
      ).to.be.revertedWithCustomError(ezETH, "NotMinterBurner");
    });

    it("should revert if burning more than balance", async function () {
      const balance = await ezETH.balanceOf(user1.address);
      await expect(
        ezETH.connect(minter).burn(user1.address, balance + 1n)
      ).to.be.revertedWith("ERC20: burn amount exceeds balance");
    });
  });

  describe("Transfers", function () {
    beforeEach(async function () {
      await ezETH.connect(minter).mint(user1.address, ethers.parseEther("1000"));
    });

    it("should allow transfers between users", async function () {
      const amount = ethers.parseEther("100");
      await ezETH.connect(user1).transfer(user2.address, amount);
      
      expect(await ezETH.balanceOf(user2.address)).to.equal(amount);
    });

    it("should emit Transfer event", async function () {
      const amount = ethers.parseEther("100");
      await expect(ezETH.connect(user1).transfer(user2.address, amount))
        .to.emit(ezETH, "Transfer")
        .withArgs(user1.address, user2.address, amount);
    });

    it("should update balances correctly after transfer", async function () {
      const amount = ethers.parseEther("100");
      const initialUser1Balance = await ezETH.balanceOf(user1.address);
      
      await ezETH.connect(user1).transfer(user2.address, amount);
      
      expect(await ezETH.balanceOf(user1.address)).to.equal(initialUser1Balance - amount);
      expect(await ezETH.balanceOf(user2.address)).to.equal(amount);
    });

    it("should revert if transferring more than balance", async function () {
      const balance = await ezETH.balanceOf(user1.address);
      await expect(
        ezETH.connect(user1).transfer(user2.address, balance + 1n)
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
    });

    it("should not affect total supply", async function () {
      const initialSupply = await ezETH.totalSupply();
      const amount = ethers.parseEther("100");
      
      await ezETH.connect(user1).transfer(user2.address, amount);
      
      expect(await ezETH.totalSupply()).to.equal(initialSupply);
    });
  });

  describe("Allowances", function () {
    beforeEach(async function () {
      await ezETH.connect(minter).mint(user1.address, ethers.parseEther("1000"));
    });

    it("should set allowance correctly", async function () {
      const amount = ethers.parseEther("500");
      await ezETH.connect(user1).approve(user2.address, amount);
      expect(await ezETH.allowance(user1.address, user2.address)).to.equal(amount);
    });

    it("should emit Approval event", async function () {
      const amount = ethers.parseEther("500");
      await expect(ezETH.connect(user1).approve(user2.address, amount))
        .to.emit(ezETH, "Approval")
        .withArgs(user1.address, user2.address, amount);
    });

    it("should allow transferFrom with sufficient allowance", async function () {
      const amount = ethers.parseEther("100");
      await ezETH.connect(user1).approve(user2.address, amount);
      
      await ezETH.connect(user2).transferFrom(user1.address, user2.address, amount);
      
      expect(await ezETH.balanceOf(user2.address)).to.equal(amount);
    });

    it("should reduce allowance after transferFrom", async function () {
      const approveAmount = ethers.parseEther("500");
      const transferAmount = ethers.parseEther("100");
      
      await ezETH.connect(user1).approve(user2.address, approveAmount);
      await ezETH.connect(user2).transferFrom(user1.address, user2.address, transferAmount);
      
      expect(await ezETH.allowance(user1.address, user2.address)).to.equal(
        approveAmount - transferAmount
      );
    });

    it("should revert transferFrom with insufficient allowance", async function () {
      const amount = ethers.parseEther("100");
      await ezETH.connect(user1).approve(user2.address, amount - 1n);
      
      await expect(
        ezETH.connect(user2).transferFrom(user1.address, user2.address, amount)
      ).to.be.revertedWith("ERC20: insufficient allowance");
    });

    it("should allow increaseAllowance", async function () {
      const initialAmount = ethers.parseEther("100");
      const increaseAmount = ethers.parseEther("50");
      
      await ezETH.connect(user1).approve(user2.address, initialAmount);
      await ezETH.connect(user1).increaseAllowance(user2.address, increaseAmount);
      
      expect(await ezETH.allowance(user1.address, user2.address)).to.equal(
        initialAmount + increaseAmount
      );
    });

    it("should allow decreaseAllowance", async function () {
      const initialAmount = ethers.parseEther("100");
      const decreaseAmount = ethers.parseEther("50");
      
      await ezETH.connect(user1).approve(user2.address, initialAmount);
      await ezETH.connect(user1).decreaseAllowance(user2.address, decreaseAmount);
      
      expect(await ezETH.allowance(user1.address, user2.address)).to.equal(
        initialAmount - decreaseAmount
      );
    });
  });

  describe("Role Changes", function () {
    it("should respect role changes - new minter can mint", async function () {
      // Grant minter role to user1
      await roleManager.connect(admin).grantRole(RX_ETH_MINTER_BURNER, user1.address);
      
      const amount = ethers.parseEther("100");
      await ezETH.connect(user1).mint(user2.address, amount);
      
      expect(await ezETH.balanceOf(user2.address)).to.equal(amount);
    });

    it("should respect role revocation - revoked minter cannot mint", async function () {
      // Revoke minter role from minter
      await roleManager.connect(admin).revokeRole(RX_ETH_MINTER_BURNER, minter.address);
      
      const amount = ethers.parseEther("100");
      await expect(
        ezETH.connect(minter).mint(user1.address, amount)
      ).to.be.revertedWithCustomError(ezETH, "NotMinterBurner");
    });
  });
});
