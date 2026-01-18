import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

/**
 * Role hash constants used throughout the Renzo protocol
 */
export const ROLES = {
  RX_ETH_MINTER_BURNER: ethers.keccak256(ethers.toUtf8Bytes("RX_ETH_MINTER_BURNER")),
  OPERATOR_DELEGATOR_ADMIN: ethers.keccak256(ethers.toUtf8Bytes("OPERATOR_DELEGATOR_ADMIN")),
  ORACLE_ADMIN: ethers.keccak256(ethers.toUtf8Bytes("ORACLE_ADMIN")),
  RESTAKE_MANAGER_ADMIN: ethers.keccak256(ethers.toUtf8Bytes("RESTAKE_MANAGER_ADMIN")),
  TOKEN_ADMIN: ethers.keccak256(ethers.toUtf8Bytes("TOKEN_ADMIN")),
  NATIVE_ETH_RESTAKE_ADMIN: ethers.keccak256(ethers.toUtf8Bytes("NATIVE_ETH_RESTAKE_ADMIN")),
  ERC20_REWARD_ADMIN: ethers.keccak256(ethers.toUtf8Bytes("ERC20_REWARD_ADMIN")),
  DEPOSIT_WITHDRAW_PAUSER: ethers.keccak256(ethers.toUtf8Bytes("DEPOSIT_WITHDRAW_PAUSER")),
  DEFAULT_ADMIN_ROLE: ethers.ZeroHash,
};

/**
 * Common test constants
 */
export const CONSTANTS = {
  ZERO_ADDRESS: ethers.ZeroAddress,
  ONE_ETH: ethers.parseEther("1"),
  TEN_ETH: ethers.parseEther("10"),
  HUNDRED_ETH: ethers.parseEther("100"),
  MAX_UINT256: ethers.MaxUint256,
  ONE_DAY: 86400,
  ONE_WEEK: 604800,
};

/**
 * Interface for deployed test fixtures
 */
export interface TestFixture {
  roleManager: any;
  ezETH: any;
  renzoOracle: any;
  depositQueue: any;
  mockChainlinkOracle: any;
  mockToken: any;
  mockRestakeManager: any;
  mockWithdrawQueue: any;
  admin: SignerWithAddress;
  minter: SignerWithAddress;
  oracleAdmin: SignerWithAddress;
  restakeManagerAdmin: SignerWithAddress;
  user1: SignerWithAddress;
  user2: SignerWithAddress;
}

/**
 * Deploy the RoleManager contract
 * @param admin Admin address
 * @returns Deployed RoleManager contract
 */
export async function deployRoleManager(admin: SignerWithAddress) {
  const RoleManagerFactory = await ethers.getContractFactory("RoleManager");
  const roleManager = await upgrades.deployProxy(RoleManagerFactory, [admin.address], {
    initializer: "initialize",
  });
  await roleManager.waitForDeployment();
  return roleManager;
}

/**
 * Deploy the EzEthToken contract
 * @param roleManagerAddress RoleManager contract address
 * @returns Deployed EzEthToken contract
 */
export async function deployEzEthToken(roleManagerAddress: string) {
  const EzEthTokenFactory = await ethers.getContractFactory("EzEthToken");
  const ezETH = await upgrades.deployProxy(EzEthTokenFactory, [roleManagerAddress], {
    initializer: "initialize",
  });
  await ezETH.waitForDeployment();
  return ezETH;
}

/**
 * Deploy the RenzoOracle contract
 * @param roleManagerAddress RoleManager contract address
 * @returns Deployed RenzoOracle contract
 */
export async function deployRenzoOracle(roleManagerAddress: string) {
  const RenzoOracleFactory = await ethers.getContractFactory("RenzoOracle");
  const renzoOracle = await upgrades.deployProxy(RenzoOracleFactory, [roleManagerAddress], {
    initializer: "initialize",
  });
  await renzoOracle.waitForDeployment();
  return renzoOracle;
}

/**
 * Deploy the DepositQueue contract
 * @param roleManagerAddress RoleManager contract address
 * @returns Deployed DepositQueue contract
 */
export async function deployDepositQueue(roleManagerAddress: string) {
  const DepositQueueFactory = await ethers.getContractFactory("DepositQueue");
  const depositQueue = await upgrades.deployProxy(DepositQueueFactory, [roleManagerAddress], {
    initializer: "initialize",
  });
  await depositQueue.waitForDeployment();
  return depositQueue;
}

/**
 * Deploy mock contracts for testing
 */
export async function deployMocks() {
  // Deploy MockChainlinkOracle
  const MockOracleFactory = await ethers.getContractFactory("MockChainlinkOracle");
  const mockChainlinkOracle = await MockOracleFactory.deploy(18, ethers.parseEther("1"));
  await mockChainlinkOracle.waitForDeployment();

  // Deploy MockERC20
  const MockTokenFactory = await ethers.getContractFactory("MockERC20");
  const mockToken = await MockTokenFactory.deploy("Mock Token", "MTK", 18);
  await mockToken.waitForDeployment();

  // Deploy MockRestakeManager
  const MockRestakeManagerFactory = await ethers.getContractFactory("MockRestakeManager");
  const mockRestakeManager = await MockRestakeManagerFactory.deploy();
  await mockRestakeManager.waitForDeployment();

  // Deploy MockWithdrawQueue
  const MockWithdrawQueueFactory = await ethers.getContractFactory("MockWithdrawQueue");
  const mockWithdrawQueue = await MockWithdrawQueueFactory.deploy();
  await mockWithdrawQueue.waitForDeployment();

  return {
    mockChainlinkOracle,
    mockToken,
    mockRestakeManager,
    mockWithdrawQueue,
  };
}

/**
 * Deploy full test fixture with all contracts and roles configured
 * @returns Complete test fixture
 */
export async function deployFullFixture(): Promise<TestFixture> {
  const [admin, minter, oracleAdmin, restakeManagerAdmin, user1, user2] =
    await ethers.getSigners();

  // Deploy RoleManager
  const roleManager = await deployRoleManager(admin);
  const roleManagerAddress = await roleManager.getAddress();

  // Grant roles
  await roleManager.connect(admin).grantRole(ROLES.RX_ETH_MINTER_BURNER, minter.address);
  await roleManager.connect(admin).grantRole(ROLES.ORACLE_ADMIN, oracleAdmin.address);
  await roleManager.connect(admin).grantRole(ROLES.RESTAKE_MANAGER_ADMIN, restakeManagerAdmin.address);

  // Deploy main contracts
  const ezETH = await deployEzEthToken(roleManagerAddress);
  const renzoOracle = await deployRenzoOracle(roleManagerAddress);
  const depositQueue = await deployDepositQueue(roleManagerAddress);

  // Deploy mocks
  const mocks = await deployMocks();

  return {
    roleManager,
    ezETH,
    renzoOracle,
    depositQueue,
    ...mocks,
    admin,
    minter,
    oracleAdmin,
    restakeManagerAdmin,
    user1,
    user2,
  };
}

/**
 * Advance blockchain time
 * @param seconds Number of seconds to advance
 */
export async function advanceTime(seconds: number) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

/**
 * Advance blockchain blocks
 * @param blocks Number of blocks to mine
 */
export async function advanceBlocks(blocks: number) {
  for (let i = 0; i < blocks; i++) {
    await ethers.provider.send("evm_mine", []);
  }
}

/**
 * Get current block timestamp
 * @returns Current block timestamp
 */
export async function getBlockTimestamp(): Promise<number> {
  const block = await ethers.provider.getBlock("latest");
  return block!.timestamp;
}

/**
 * Snapshot the blockchain state
 * @returns Snapshot ID
 */
export async function takeSnapshot(): Promise<string> {
  return await ethers.provider.send("evm_snapshot", []);
}

/**
 * Revert to a previous snapshot
 * @param snapshotId Snapshot ID to revert to
 */
export async function revertToSnapshot(snapshotId: string) {
  await ethers.provider.send("evm_revert", [snapshotId]);
}
