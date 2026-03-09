const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Helper function to format USDC (6 decimals)
function formatUSDC(amount) {
  return ethers.formatUnits(amount, 6);
}

async function main() {
  console.log("\n");
  console.log("╔═══════════════════════════════════════════════════════════════════════════╗");
  console.log("║             LENDER WITHDRAWAL SCRIPT - WITHDRAW ALL FUNDS                 ║");
  console.log("╚═══════════════════════════════════════════════════════════════════════════╝");

  // Load deployment
  const deploymentPath = path.join(
    __dirname,
    "..",
    "deployment",
    "arc-testnet-native-usdc-deployment.json"
  );

  if (!fs.existsSync(deploymentPath)) {
    throw new Error(
      `❌ Deployment file not found!\n` +
        `   Please run: npm run deploy:arc:native first`
    );
  }

  const deployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  const contracts = deployment.contracts;
  const NATIVE_USDC_ADDRESS = deployment.nativeUSDC;

  console.log(`\nDeployment Network: ${deployment.network}`);
  console.log(`Chain ID: ${deployment.chainId}\n`);

  // Load wallets from environment variables
  require("dotenv").config();

  if (!process.env.LENDER1_PRIVATE_KEY || !process.env.LENDER2_PRIVATE_KEY) {
    throw new Error("Missing lender private keys in .env file");
  }

  const lender1 = new ethers.Wallet(
    process.env.LENDER1_PRIVATE_KEY,
    ethers.provider
  );
  const lender2 = new ethers.Wallet(
    process.env.LENDER2_PRIVATE_KEY,
    ethers.provider
  );

  console.log("Lenders:");
  console.log(`  Lender 1: ${lender1.address}`);
  console.log(`  Lender 2: ${lender2.address}\n`);

  // Get contract instances
  const usdc = await ethers.getContractAt("IERC20", NATIVE_USDC_ADDRESS);
  const lendingPool = await ethers.getContractAt(
    "LendingPool",
    contracts.LendingPool
  );

  // ============================================================================
  // CHECK LENDER POSITIONS
  // ============================================================================
  console.log("═".repeat(80));
  console.log("CHECKING LENDER POSITIONS");
  console.log("═".repeat(80));

  const sharePrice = await lendingPool.getSharePrice();
  console.log(`\nCurrent Share Price: ${formatUSDC(sharePrice)} USDC per share\n`);

  // Lender 1
  const [l1Shares, l1LockUntil, l1DepositAmount] = await lendingPool.getLenderInfo(lender1.address);
  const l1Value = (l1Shares * sharePrice) / BigInt(1e6);
  const l1UsdcBefore = await usdc.balanceOf(lender1.address);
  
  console.log("Lender 1 Position:");
  console.log(`  Shares:          ${formatUSDC(l1Shares)}`);
  console.log(`  Current Value:   ${formatUSDC(l1Value)} USDC`);
  console.log(`  Original Deposit: ${formatUSDC(l1DepositAmount)} USDC`);
  console.log(`  Profit/Loss:     ${formatUSDC(l1Value - l1DepositAmount)} USDC`);
  console.log(`  Lock Until:      ${new Date(Number(l1LockUntil) * 1000).toLocaleString()}`);
  console.log(`  USDC Balance:    ${formatUSDC(l1UsdcBefore)} USDC`);
  
  const l1IsLocked = l1LockUntil > BigInt(Math.floor(Date.now() / 1000));
  console.log(`  Status:          ${l1IsLocked ? "🔒 LOCKED (early withdrawal penalty applies)" : "✅ UNLOCKED"}\n`);

  // Lender 2
  const [l2Shares, l2LockUntil, l2DepositAmount] = await lendingPool.getLenderInfo(lender2.address);
  const l2Value = (l2Shares * sharePrice) / BigInt(1e6);
  const l2UsdcBefore = await usdc.balanceOf(lender2.address);
  
  console.log("Lender 2 Position:");
  console.log(`  Shares:          ${formatUSDC(l2Shares)}`);
  console.log(`  Current Value:   ${formatUSDC(l2Value)} USDC`);
  console.log(`  Original Deposit: ${formatUSDC(l2DepositAmount)} USDC`);
  console.log(`  Profit/Loss:     ${formatUSDC(l2Value - l2DepositAmount)} USDC`);
  console.log(`  Lock Until:      ${new Date(Number(l2LockUntil) * 1000).toLocaleString()}`);
  console.log(`  USDC Balance:    ${formatUSDC(l2UsdcBefore)} USDC`);
  
  const l2IsLocked = l2LockUntil > BigInt(Math.floor(Date.now() / 1000));
  console.log(`  Status:          ${l2IsLocked ? "🔒 LOCKED (early withdrawal penalty applies)" : "✅ UNLOCKED"}\n`);

  // ============================================================================
  // WITHDRAW LENDER 1
  // ============================================================================
  if (l1Shares > 0n) {
    console.log("═".repeat(80));
    console.log("WITHDRAWING LENDER 1");
    console.log("═".repeat(80));

    try {
      if (l1IsLocked) {
        const daysRemaining = (Number(l1LockUntil) - Math.floor(Date.now() / 1000)) / 86400;
        const penaltyPct = Math.min(Math.floor(daysRemaining), 50);
        console.log(`\n⚠️  Early withdrawal - ~${Math.floor(daysRemaining)} days remaining`);
        console.log(`   Estimated penalty: ~${penaltyPct}% (1% per day, max 50%)`);
        console.log(`   50% to protocol, 50% stays in pool (boosts other lenders)\n`);
        
        console.log("Processing early withdrawal...");
        const tx1 = await lendingPool.connect(lender1).withdrawEarly();
        const receipt1 = await tx1.wait();
        console.log(`✅ Lender 1 withdrew early (with penalty)`);
        console.log(`   Transaction: ${receipt1.hash}`);
      } else {
        console.log("\n✅ Lock expired - normal withdrawal (no penalty)\n");
        console.log("Processing withdrawal...");
        const tx1 = await lendingPool.connect(lender1).withdraw();
        const receipt1 = await tx1.wait();
        console.log(`✅ Lender 1 withdrew successfully`);
        console.log(`   Transaction: ${receipt1.hash}`);
      }

      const l1UsdcAfter = await usdc.balanceOf(lender1.address);
      const l1Received = l1UsdcAfter - l1UsdcBefore;
      console.log(`\n   USDC Received:   ${formatUSDC(l1Received)} USDC`);
      console.log(`   New Balance:     ${formatUSDC(l1UsdcAfter)} USDC\n`);
    } catch (error) {
      console.log(`\n❌ Withdrawal failed: ${error.message}`);
      
      // Check available liquidity
      const availableCash = await lendingPool.getAvailableCash();
      const totalBorrowed = await lendingPool.getTotalBorrowed();
      
      console.log(`\n   Pool Status:`);
      console.log(`   Available Cash:   ${formatUSDC(availableCash)} USDC`);
      console.log(`   Total Borrowed:   ${formatUSDC(totalBorrowed)} USDC`);
      console.log(`   Required Amount:  ${formatUSDC(l1Value)} USDC`);
      
      if (availableCash < l1Value) {
        console.log(`\n   ⚠️  Insufficient liquidity in pool`);
        console.log(`   💡 Wait for borrowers to repay loans or try again later\n`);
      }
    }
  } else {
    console.log("\n⚠️  Lender 1 has no shares to withdraw\n");
  }

  // ============================================================================
  // WITHDRAW LENDER 2
  // ============================================================================
  if (l2Shares > 0n) {
    console.log("═".repeat(80));
    console.log("WITHDRAWING LENDER 2");
    console.log("═".repeat(80));

    try {
      if (l2IsLocked) {
        const daysRemaining = (Number(l2LockUntil) - Math.floor(Date.now() / 1000)) / 86400;
        const penaltyPct = Math.min(Math.floor(daysRemaining), 50);
        console.log(`\n⚠️  Early withdrawal - ~${Math.floor(daysRemaining)} days remaining`);
        console.log(`   Estimated penalty: ~${penaltyPct}% (1% per day, max 50%)`);
        console.log(`   50% to protocol, 50% stays in pool (boosts other lenders)\n`);
        
        console.log("Processing early withdrawal...");
        const tx2 = await lendingPool.connect(lender2).withdrawEarly();
        const receipt2 = await tx2.wait();
        console.log(`✅ Lender 2 withdrew early (with penalty)`);
        console.log(`   Transaction: ${receipt2.hash}`);
      } else {
        console.log("\n✅ Lock expired - normal withdrawal (no penalty)\n");
        console.log("Processing withdrawal...");
        const tx2 = await lendingPool.connect(lender2).withdraw();
        const receipt2 = await tx2.wait();
        console.log(`✅ Lender 2 withdrew successfully`);
        console.log(`   Transaction: ${receipt2.hash}`);
      }

      const l2UsdcAfter = await usdc.balanceOf(lender2.address);
      const l2Received = l2UsdcAfter - l2UsdcBefore;
      console.log(`\n   USDC Received:   ${formatUSDC(l2Received)} USDC`);
      console.log(`   New Balance:     ${formatUSDC(l2UsdcAfter)} USDC\n`);
    } catch (error) {
      console.log(`\n❌ Withdrawal failed: ${error.message}`);
      
      // Check available liquidity
      const availableCash = await lendingPool.getAvailableCash();
      const totalBorrowed = await lendingPool.getTotalBorrowed();
      
      console.log(`\n   Pool Status:`);
      console.log(`   Available Cash:   ${formatUSDC(availableCash)} USDC`);
      console.log(`   Total Borrowed:   ${formatUSDC(totalBorrowed)} USDC`);
      console.log(`   Required Amount:  ${formatUSDC(l2Value)} USDC`);
      
      if (availableCash < l2Value) {
        console.log(`\n   ⚠️  Insufficient liquidity in pool`);
        console.log(`   💡 Wait for borrowers to repay loans or try again later\n`);
      }
    }
  } else {
    console.log("\n⚠️  Lender 2 has no shares to withdraw\n");
  }

  // ============================================================================
  // FINAL POOL STATE
  // ============================================================================
  console.log("═".repeat(80));
  console.log("FINAL POOL STATE");
  console.log("═".repeat(80));

  const totalAssets = await lendingPool.getTotalAssets();
  const availableCash = await lendingPool.getAvailableCash();
  const totalBorrowed = await lendingPool.getTotalBorrowed();
  const reserveFund = await lendingPool.getReserveFund();
  const totalSupply = await lendingPool.totalSupply();
  const finalSharePrice = await lendingPool.getSharePrice();

  console.log(`\nTotal Assets:     ${formatUSDC(totalAssets)} USDC`);
  console.log(`Available Cash:   ${formatUSDC(availableCash)} USDC`);
  console.log(`Total Borrowed:   ${formatUSDC(totalBorrowed)} USDC`);
  console.log(`Total Shares:     ${formatUSDC(totalSupply)}`);
  console.log(`Share Price:      ${formatUSDC(finalSharePrice)} USDC per share`);
  console.log(`Reserve Fund:     ${formatUSDC(reserveFund)} USDC`);

  console.log("\n✅ All withdrawals complete!\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ ERROR:", error);
    process.exit(1);
  });
