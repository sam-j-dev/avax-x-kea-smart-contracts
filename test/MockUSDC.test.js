const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MockUSDC", function () {
  let mockUSDC;
  let owner, addr1, addr2;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    mockUSDC = await MockUSDC.deploy(
      "Mock USDC",
      "USDC",
      ethers.parseUnits("1000000", 6)
    );
    await mockUSDC.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the correct name and symbol", async function () {
      expect(await mockUSDC.name()).to.equal("Mock USDC");
      expect(await mockUSDC.symbol()).to.equal("USDC");
    });

    it("Should have 6 decimals", async function () {
      expect(await mockUSDC.decimals()).to.equal(6);
    });

    it("Should mint initial supply to owner", async function () {
      const ownerBalance = await mockUSDC.balanceOf(owner.address);
      expect(ownerBalance).to.equal(ethers.parseUnits("1000000", 6));
    });
  });

  describe("Faucet", function () {
    it("Should allow anyone to mint 1000 USDC from faucet", async function () {
      const faucetAmount = ethers.parseUnits("1000", 6);

      await mockUSDC.connect(addr1).faucet();
      const balance = await mockUSDC.balanceOf(addr1.address);

      expect(balance).to.equal(faucetAmount);
    });

    it("Should allow multiple faucet calls", async function () {
      const faucetAmount = ethers.parseUnits("1000", 6);

      await mockUSDC.connect(addr1).faucet();
      await mockUSDC.connect(addr1).faucet();

      const balance = await mockUSDC.balanceOf(addr1.address);
      expect(balance).to.equal(faucetAmount * 2n);
    });
  });

  describe("Minting (Owner only)", function () {
    it("Should allow owner to mint tokens", async function () {
      const mintAmount = ethers.parseUnits("5000", 6);

      await mockUSDC.mint(addr1.address, mintAmount);
      const balance = await mockUSDC.balanceOf(addr1.address);

      expect(balance).to.equal(mintAmount);
    });

    it("Should fail if non-owner tries to mint", async function () {
      const mintAmount = ethers.parseUnits("5000", 6);

      await expect(mockUSDC.connect(addr1).mint(addr2.address, mintAmount)).to
        .be.reverted;
    });
  });

  describe("Transfers", function () {
    it("Should transfer tokens between accounts", async function () {
      const transferAmount = ethers.parseUnits("100", 6);

      await mockUSDC.transfer(addr1.address, transferAmount);
      expect(await mockUSDC.balanceOf(addr1.address)).to.equal(transferAmount);

      await mockUSDC.connect(addr1).transfer(addr2.address, transferAmount);
      expect(await mockUSDC.balanceOf(addr2.address)).to.equal(transferAmount);
    });

    it("Should fail if sender doesn't have enough tokens", async function () {
      const largeAmount = ethers.parseUnits("1000000000", 6);

      await expect(mockUSDC.connect(addr1).transfer(addr2.address, largeAmount))
        .to.be.reverted;
    });
  });
});
