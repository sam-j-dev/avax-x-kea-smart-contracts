const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LendingPool", function () {
  let mockUSDC, lendingPool;
  let owner, lender1, lender2, borrower;
  const PRECISION = ethers.parseEther("1");

  beforeEach(async function () {
    [owner, lender1, lender2, borrower] = await ethers.getSigners();

    // Deploy MockUSDC
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    mockUSDC = await MockUSDC.deploy(
      "Mock USDC",
      "USDC",
      ethers.parseUnits("10000000", 6)
    );
    await mockUSDC.waitForDeployment();

    // Deploy LendingPool
    const LendingPool = await ethers.getContractFactory("LendingPool");
    lendingPool = await LendingPool.deploy(await mockUSDC.getAddress());
    await lendingPool.waitForDeployment();

    // Fund test accounts
    await mockUSDC.transfer(lender1.address, ethers.parseUnits("100000", 6));
    await mockUSDC.transfer(lender2.address, ethers.parseUnits("50000", 6));
  });

  describe("Deployment", function () {
    it("Should set the correct USDC address", async function () {
      expect(await lendingPool.USDC()).to.equal(await mockUSDC.getAddress());
    });

    it("Should set the correct owner", async function () {
      expect(await lendingPool.owner()).to.equal(owner.address);
    });

    it("Should have initial share price of 1:1", async function () {
      expect(await lendingPool.getSharePrice()).to.equal(PRECISION);
    });

    it("Should have zero available cash initially", async function () {
      expect(await lendingPool.getAvailableCash()).to.equal(0);
    });
  });

  describe("Deposits", function () {
    it("Should allow lenders to deposit USDC", async function () {
      const depositAmount = ethers.parseUnits("10000", 6);
      const lockDays = 30;

      await mockUSDC
        .connect(lender1)
        .approve(await lendingPool.getAddress(), depositAmount);
      await lendingPool.connect(lender1).deposit(depositAmount, lockDays);

      const [shares, lockUntil, depositedAmount] =
        await lendingPool.getLenderInfo(lender1.address);
      expect(depositedAmount).to.equal(depositAmount);
      expect(shares).to.equal(depositAmount); // Initial 1:1 ratio
      expect(lockUntil).to.be.gt(0);
    });

    it("Should update available cash after deposit", async function () {
      const depositAmount = ethers.parseUnits("10000", 6);

      await mockUSDC
        .connect(lender1)
        .approve(await lendingPool.getAddress(), depositAmount);
      await lendingPool.connect(lender1).deposit(depositAmount, 30);

      expect(await lendingPool.getAvailableCash()).to.equal(depositAmount);
    });

    it("Should fail if lock period is too short", async function () {
      const depositAmount = ethers.parseUnits("10000", 6);

      await mockUSDC
        .connect(lender1)
        .approve(await lendingPool.getAddress(), depositAmount);
      await expect(
        lendingPool.connect(lender1).deposit(depositAmount, 15)
      ).to.be.revertedWith("Lock period too short");
    });

    it("Should fail if amount is zero", async function () {
      await expect(
        lendingPool.connect(lender1).deposit(0, 30)
      ).to.be.revertedWith("Amount must be > 0");
    });

    it("Should handle multiple lender deposits", async function () {
      const amount1 = ethers.parseUnits("50000", 6);
      const amount2 = ethers.parseUnits("30000", 6);

      await mockUSDC
        .connect(lender1)
        .approve(await lendingPool.getAddress(), amount1);
      await lendingPool.connect(lender1).deposit(amount1, 60);

      await mockUSDC
        .connect(lender2)
        .approve(await lendingPool.getAddress(), amount2);
      await lendingPool.connect(lender2).deposit(amount2, 30);

      expect(await lendingPool.getAvailableCash()).to.equal(amount1 + amount2);
    });
  });

  describe("Withdrawals", function () {
    beforeEach(async function () {
      const depositAmount = ethers.parseUnits("10000", 6);
      await mockUSDC
        .connect(lender1)
        .approve(await lendingPool.getAddress(), depositAmount);
      await lendingPool.connect(lender1).deposit(depositAmount, 30);
    });

    it("Should fail withdrawal before lock period expires", async function () {
      await expect(lendingPool.connect(lender1).withdraw()).to.be.revertedWith(
        "Lock period not expired"
      );
    });

    it("Should allow early withdrawal with penalty", async function () {
      const balanceBefore = await mockUSDC.balanceOf(lender1.address);

      await lendingPool.connect(lender1).withdrawEarly();

      const balanceAfter = await mockUSDC.balanceOf(lender1.address);
      const received = balanceAfter - balanceBefore;

      // Should receive less than deposited due to penalty
      expect(received).to.be.lt(ethers.parseUnits("10000", 6));
      expect(received).to.be.gt(0);
    });

    it("Should burn LP tokens on early withdrawal", async function () {
      const [sharesBefore] = await lendingPool.getLenderInfo(lender1.address);
      expect(sharesBefore).to.be.gt(0);

      await lendingPool.connect(lender1).withdrawEarly();

      const [sharesAfter] = await lendingPool.getLenderInfo(lender1.address);
      expect(sharesAfter).to.equal(0);
    });
  });

  describe("Share Price", function () {
    it("Should maintain 1:1 share price with single deposit", async function () {
      const depositAmount = ethers.parseUnits("10000", 6);

      await mockUSDC
        .connect(lender1)
        .approve(await lendingPool.getAddress(), depositAmount);
      await lendingPool.connect(lender1).deposit(depositAmount, 30);

      const sharePrice = await lendingPool.getSharePrice();
      expect(sharePrice).to.equal(PRECISION);
    });

    it("Should calculate total assets correctly", async function () {
      const depositAmount = ethers.parseUnits("10000", 6);

      await mockUSDC
        .connect(lender1)
        .approve(await lendingPool.getAddress(), depositAmount);
      await lendingPool.connect(lender1).deposit(depositAmount, 30);

      const totalAssets = await lendingPool.getTotalAssets();
      expect(totalAssets).to.equal(depositAmount);
    });
  });

  describe("Authorized Contracts", function () {
    it("Should allow owner to set authorized contracts", async function () {
      await lendingPool.setAuthorizedContracts(
        borrower.address, // requestManager
        lender1.address, // repaymentProcessor
        lender2.address, // defaultManager
        owner.address // yieldOptimizer
      );

      expect(await lendingPool.requestManager()).to.equal(borrower.address);
      expect(await lendingPool.repaymentProcessor()).to.equal(lender1.address);
      expect(await lendingPool.defaultManager()).to.equal(lender2.address);
      expect(await lendingPool.yieldOptimizer()).to.equal(owner.address);
    });

    it("Should fail if non-owner tries to set authorized contracts", async function () {
      await expect(
        lendingPool
          .connect(lender1)
          .setAuthorizedContracts(
            borrower.address,
            lender1.address,
            lender2.address,
            owner.address
          )
      ).to.be.reverted;
    });
  });

  describe("View Functions", function () {
    it("Should return correct lender info", async function () {
      const depositAmount = ethers.parseUnits("5000", 6);
      const lockDays = 45;

      await mockUSDC
        .connect(lender1)
        .approve(await lendingPool.getAddress(), depositAmount);
      await lendingPool.connect(lender1).deposit(depositAmount, lockDays);

      const [shares, lockUntil, depositedAmount] =
        await lendingPool.getLenderInfo(lender1.address);

      expect(depositedAmount).to.equal(depositAmount);
      expect(shares).to.be.gt(0);
      expect(lockUntil).to.be.gt(
        await ethers.provider.getBlock("latest").then((b) => b.timestamp)
      );
    });

    it("Should return zero for non-existent lender", async function () {
      const [shares, lockUntil, depositedAmount] =
        await lendingPool.getLenderInfo(borrower.address);

      expect(depositedAmount).to.equal(0);
      expect(shares).to.equal(0);
      expect(lockUntil).to.equal(0);
    });
  });
});
