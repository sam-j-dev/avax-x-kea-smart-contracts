const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CreditManager", function () {
  let creditManager;
  let owner, borrower1, borrower2;

  beforeEach(async function () {
    [owner, borrower1, borrower2] = await ethers.getSigners();

    const CreditManager = await ethers.getContractFactory("CreditManager");
    creditManager = await CreditManager.deploy();
    await creditManager.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the correct owner", async function () {
      expect(await creditManager.owner()).to.equal(owner.address);
    });
  });

  describe("Adding Borrowers", function () {
    it("Should allow owner to add a borrower", async function () {
      const creditLimit = ethers.parseUnits("50000", 6);
      const docsHash = ethers.keccak256(
        ethers.toUtf8Bytes("Due diligence docs")
      );

      await creditManager.addBorrower(borrower1.address, creditLimit, docsHash);

      const profile = await creditManager.getBorrowerProfile(borrower1.address);
      expect(profile.creditLimit).to.equal(creditLimit);
      expect(profile.currentBorrowed).to.equal(0);
      expect(profile.dueDiligenceHash).to.equal(docsHash);
      expect(profile.status).to.equal(1); // ACTIVE
    });

    it("Should fail if non-owner tries to add borrower", async function () {
      const creditLimit = ethers.parseUnits("50000", 6);
      const docsHash = ethers.keccak256(ethers.toUtf8Bytes("Docs"));

      await expect(
        creditManager
          .connect(borrower1)
          .addBorrower(borrower2.address, creditLimit, docsHash)
      ).to.be.reverted;
    });

    it("Should fail if credit limit is zero", async function () {
      const docsHash = ethers.keccak256(ethers.toUtf8Bytes("Docs"));

      await expect(
        creditManager.addBorrower(borrower1.address, 0, docsHash)
      ).to.be.revertedWith("Credit limit must be > 0");
    });

    it("Should fail if borrower already exists", async function () {
      const creditLimit = ethers.parseUnits("50000", 6);
      const docsHash = ethers.keccak256(ethers.toUtf8Bytes("Docs"));

      await creditManager.addBorrower(borrower1.address, creditLimit, docsHash);

      await expect(
        creditManager.addBorrower(borrower1.address, creditLimit, docsHash)
      ).to.be.revertedWith("Borrower already exists");
    });
  });

  describe("Borrower Status", function () {
    beforeEach(async function () {
      const creditLimit = ethers.parseUnits("50000", 6);
      const docsHash = ethers.keccak256(ethers.toUtf8Bytes("Docs"));
      await creditManager.addBorrower(borrower1.address, creditLimit, docsHash);
    });

    it("Should return true for active borrower", async function () {
      expect(await creditManager.isBorrowerActive(borrower1.address)).to.be
        .true;
    });

    it("Should return false for non-existent borrower", async function () {
      expect(await creditManager.isBorrowerActive(borrower2.address)).to.be
        .false;
    });

    it("Should return correct remaining credit", async function () {
      const creditLimit = ethers.parseUnits("50000", 6);
      const remaining = await creditManager.getRemainingCredit(
        borrower1.address
      );
      expect(remaining).to.equal(creditLimit);
    });
  });

  describe("Credit Increase Requests", function () {
    beforeEach(async function () {
      const creditLimit = ethers.parseUnits("50000", 6);
      const docsHash = ethers.keccak256(ethers.toUtf8Bytes("Docs"));
      await creditManager.addBorrower(borrower1.address, creditLimit, docsHash);
    });

    it("Should allow borrower to request credit increase", async function () {
      const additionalCredit = ethers.parseUnits("25000", 6);
      const newDocsHash = ethers.keccak256(ethers.toUtf8Bytes("Updated docs"));

      await creditManager
        .connect(borrower1)
        .requestCreditIncrease(additionalCredit, newDocsHash);

      const request = await creditManager.creditIncreaseRequests(
        borrower1.address
      );
      expect(request.additionalCredit).to.equal(additionalCredit);
      expect(request.newDocsHash).to.equal(newDocsHash);
      expect(request.processed).to.be.false;
    });

    it("Should fail if non-active borrower requests increase", async function () {
      const additionalCredit = ethers.parseUnits("25000", 6);
      const newDocsHash = ethers.keccak256(ethers.toUtf8Bytes("Docs"));

      await expect(
        creditManager
          .connect(borrower2)
          .requestCreditIncrease(additionalCredit, newDocsHash)
      ).to.be.revertedWith("Not active borrower");
    });

    it("Should allow owner to approve credit increase", async function () {
      const additionalCredit = ethers.parseUnits("25000", 6);
      const newDocsHash = ethers.keccak256(ethers.toUtf8Bytes("Updated docs"));
      const newTotalLimit = ethers.parseUnits("75000", 6);

      await creditManager
        .connect(borrower1)
        .requestCreditIncrease(additionalCredit, newDocsHash);
      await creditManager.approveCreditIncrease(
        borrower1.address,
        newTotalLimit
      );

      const profile = await creditManager.getBorrowerProfile(borrower1.address);
      expect(profile.creditLimit).to.equal(newTotalLimit);
      expect(profile.dueDiligenceHash).to.equal(newDocsHash);
    });
  });

  describe("Deactivating Borrowers", function () {
    beforeEach(async function () {
      const creditLimit = ethers.parseUnits("50000", 6);
      const docsHash = ethers.keccak256(ethers.toUtf8Bytes("Docs"));
      await creditManager.addBorrower(borrower1.address, creditLimit, docsHash);
    });

    it("Should allow owner to deactivate borrower with no outstanding loans", async function () {
      await creditManager.deactivateBorrower(borrower1.address, "Test reason");

      const profile = await creditManager.getBorrowerProfile(borrower1.address);
      expect(profile.status).to.equal(0); // INACTIVE
    });

    it("Should fail if borrower has outstanding loans", async function () {
      // Simulate outstanding loan
      await creditManager.updateBorrowedAmount(
        borrower1.address,
        ethers.parseUnits("10000", 6)
      );

      await expect(
        creditManager.deactivateBorrower(borrower1.address, "Test")
      ).to.be.revertedWith("Outstanding loans exist");
    });
  });

  describe("Updating Documentation", function () {
    beforeEach(async function () {
      const creditLimit = ethers.parseUnits("50000", 6);
      const docsHash = ethers.keccak256(ethers.toUtf8Bytes("Original docs"));
      await creditManager.addBorrower(borrower1.address, creditLimit, docsHash);
    });

    it("Should allow owner to update documentation hash", async function () {
      const newDocsHash = ethers.keccak256(ethers.toUtf8Bytes("Updated docs"));

      await creditManager.updateDocsHash(borrower1.address, newDocsHash);

      const profile = await creditManager.getBorrowerProfile(borrower1.address);
      expect(profile.dueDiligenceHash).to.equal(newDocsHash);
    });

    it("Should fail if borrower is not active", async function () {
      const newDocsHash = ethers.keccak256(ethers.toUtf8Bytes("Docs"));

      await expect(
        creditManager.updateDocsHash(borrower2.address, newDocsHash)
      ).to.be.revertedWith("Not active borrower");
    });
  });
});
