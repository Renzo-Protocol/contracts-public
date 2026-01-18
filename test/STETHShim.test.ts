import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { STETHShim } from "../typechain-types";

describe("STETHShim", function () {
  let stETHShim: STETHShim;
  let deployer: SignerWithAddress;

  beforeEach(async function () {
    [deployer] = await ethers.getSigners();

    const STETHShimFactory = await ethers.getContractFactory("STETHShim");
    stETHShim = await STETHShimFactory.deploy();
    await stETHShim.waitForDeployment();
  });

  describe("Metadata", function () {
    it("should return correct decimals", async function () {
      expect(await stETHShim.decimals()).to.equal(18);
    });

    it("should return correct description", async function () {
      expect(await stETHShim.description()).to.equal("stETH Chainlink Shim");
    });

    it("should return correct version", async function () {
      expect(await stETHShim.version()).to.equal(1);
    });
  });

  describe("Price Data", function () {
    it("should return 1:1 price ratio in latestRoundData", async function () {
      const [roundId, answer, startedAt, updatedAt, answeredInRound] =
        await stETHShim.latestRoundData();

      // Price should be 1e18 (1:1 ratio)
      expect(answer).to.equal(ethers.parseEther("1"));
      expect(roundId).to.equal(1);
      expect(answeredInRound).to.equal(1);
      expect(startedAt).to.be.gt(0);
      expect(updatedAt).to.be.gt(0);
    });

    it("should revert on getRoundData (historical data not available)", async function () {
      await expect(stETHShim.getRoundData(1)).to.be.revertedWithCustomError(
        stETHShim,
        "NotImplemented"
      );
    });
  });

  describe("Chainlink Interface Compliance", function () {
    it("should implement AggregatorV3Interface correctly", async function () {
      // Verify all required functions are callable
      await expect(stETHShim.decimals()).to.not.be.reverted;
      await expect(stETHShim.description()).to.not.be.reverted;
      await expect(stETHShim.version()).to.not.be.reverted;
      await expect(stETHShim.latestRoundData()).to.not.be.reverted;
    });
  });
});
