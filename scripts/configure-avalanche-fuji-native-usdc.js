const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("Configuring KEA Credit Contracts on Avalanche Fuji C-Chain");
  console.log("Using Native USDC");
  console.log("========================================\n");

  // Load deployment info
  const deploymentPath = path.join(
    __dirname,
    "..",
    "deployment",
    "avalanche-fuji-native-usdc-deployment.json"
  );

  if (!fs.existsSync(deploymentPath)) {
    throw new Error(
      `Deployment file not found at ${deploymentPath}\n` +
        "Please run: npm run deploy:avax:native first"
    );
  }

  const deployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));

  console.log("Loaded deployment from:", deploymentPath);
  console.log("Network:", deployment.network);
  console.log("Deployed by:", deployment.deployer);
  console.log("Timestamp:", deployment.timestamp, "\n");

  // Get signer
  const [deployer] = await ethers.getSigners();
  console.log("Configuring with account:", deployer.address, "\n");

  // Helper function to add delay between transactions
  const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

  // Get contract instances
  const lendingPool = await ethers.getContractAt(
    "LendingPool",
    deployment.contracts.LendingPool
  );

  const creditManager = await ethers.getContractAt(
    "CreditManager",
    deployment.contracts.CreditManager
  );

  const loanDocNFT = await ethers.getContractAt(
    "LoanDocumentationNFT",
    deployment.contracts.LoanDocumentationNFT
  );

  const requestManager = await ethers.getContractAt(
    "RequestManager",
    deployment.contracts.RequestManager
  );

  const repaymentProcessor = await ethers.getContractAt(
    "RepaymentProcessor",
    deployment.contracts.RepaymentProcessor
  );

  const defaultManager = await ethers.getContractAt(
    "DefaultManager",
    deployment.contracts.DefaultManager
  );

  // Step 1: Set authorized contracts on LendingPool
  console.log("Step 1: Setting authorized contracts on LendingPool...");
  const tx1 = await lendingPool.setAuthorizedContracts(
    deployment.contracts.RequestManager,
    deployment.contracts.RepaymentProcessor,
    deployment.contracts.DefaultManager,
    deployment.contracts.YieldOptimizer,
    deployment.contracts.CreditManager
  );
  await tx1.wait();
  console.log("   ✅ Authorized contracts set");
  console.log("   Transaction:", tx1.hash);
  await delay(3000);
  console.log("");

  // Step 1b: Set authorized contracts on CreditManager
  console.log("Step 1b: Setting authorized contracts on CreditManager...");
  const tx1b = await creditManager.setAuthorizedContracts(
    deployment.contracts.LendingPool,
    deployment.contracts.DefaultManager
  );
  await tx1b.wait();
  console.log("   ✅ CreditManager authorized contracts set");
  console.log("   Transaction:", tx1b.hash);
  await delay(3000);
  console.log("");

  // Step 1c: Set processor contracts on RequestManager for automatic recording
  console.log(
    "Step 1c: Setting processor contracts on RequestManager..."
  );
  const tx1c = await requestManager.setProcessorContracts(
    deployment.contracts.RepaymentProcessor,
    deployment.contracts.DefaultManager
  );
  await tx1c.wait();
  console.log("   ✅ RequestManager processor contracts set");
  console.log("   Transaction:", tx1c.hash);
  await delay(3000);
  console.log("");

  // Step 1d: Authorize RequestManager in RepaymentProcessor
  console.log(
    "Step 1d: Authorizing RequestManager in RepaymentProcessor..."
  );
  const tx1d = await repaymentProcessor.setRequestManager(
    deployment.contracts.RequestManager
  );
  await tx1d.wait();
  console.log("   ✅ RequestManager authorized in RepaymentProcessor");
  console.log("   Transaction:", tx1d.hash);
  await delay(3000);
  console.log("");

  // Step 1e: Authorize RequestManager in DefaultManager
  console.log("Step 1e: Authorizing RequestManager in DefaultManager...");
  const tx1e = await defaultManager.setRequestManager(
    deployment.contracts.RequestManager
  );
  await tx1e.wait();
  console.log("   ✅ RequestManager authorized in DefaultManager");
  console.log("   Transaction:", tx1e.hash);
  await delay(3000);
  console.log("");

  // Step 2: Set pool max cap
  console.log("Step 2: Setting pool maximum cap...");
  const poolMaxCap = BigInt(deployment.config?.poolMaxCap || "0");
  
  if (poolMaxCap === 0n) {
    console.log("   Pool cap: UNLIMITED (no cap set)");
  } else {
    const capInUSDC = Number(poolMaxCap) / 1e6;
    console.log(`   Pool cap: ${capInUSDC.toLocaleString()} USDC`);
  }
  
  const tx2 = await lendingPool.updatePoolMaxCap(poolMaxCap);
  await tx2.wait();
  console.log("   ✅ Pool max cap set");
  console.log("   Transaction:", tx2.hash);
  await delay(3000);
  console.log("");

  // Step 3: Authorize contracts on LoanDocumentationNFT
  console.log("Step 3: Authorizing contracts on LoanDocumentationNFT...");

  try {
    const tx3a = await loanDocNFT.setAuthorizedContract(
      deployment.contracts.RequestManager,
      true
    );
    await tx3a.wait();
    console.log("   ✅ RequestManager authorized");
    console.log("      Transaction:", tx3a.hash);
    await delay(3000);
  } catch (error) {
    console.error("   ❌ Failed to authorize RequestManager:", error.message);
    throw error;
  }

  try {
    const tx3b = await loanDocNFT.setAuthorizedContract(
      deployment.contracts.RepaymentProcessor,
      true
    );
    await tx3b.wait();
    console.log("   ✅ RepaymentProcessor authorized");
    console.log("      Transaction:", tx3b.hash);
    await delay(3000);
  } catch (error) {
    console.error(
      "   ❌ Failed to authorize RepaymentProcessor:",
      error.message
    );
    throw error;
  }

  try {
    const tx3c = await loanDocNFT.setAuthorizedContract(
      deployment.contracts.DefaultManager,
      true
    );
    await tx3c.wait();
    console.log("   ✅ DefaultManager authorized");
    console.log("      Transaction:", tx3c.hash);
    await delay(3000);
  } catch (error) {
    console.error("   ❌ Failed to authorize DefaultManager:", error.message);
    throw error;
  }

  // Verify authorizations
  console.log("\n========================================");
  console.log("VERIFYING ALL AUTHORIZATIONS");
  console.log("========================================");

  // Verify LendingPool authorizations
  console.log("\n1. LendingPool Authorizations:");
  const lpRequestManager = await lendingPool.requestManager();
  const lpRepaymentProcessor = await lendingPool.repaymentProcessor();
  const lpDefaultManager = await lendingPool.defaultManager();
  const lpYieldOptimizer = await lendingPool.yieldOptimizer();
  const lpCreditManager = await lendingPool.creditManager();
  
  console.log(`   RequestManager:      ${lpRequestManager === deployment.contracts.RequestManager ? "✅" : "❌"} ${lpRequestManager}`);
  console.log(`   RepaymentProcessor:  ${lpRepaymentProcessor === deployment.contracts.RepaymentProcessor ? "✅" : "❌"} ${lpRepaymentProcessor}`);
  console.log(`   DefaultManager:      ${lpDefaultManager === deployment.contracts.DefaultManager ? "✅" : "❌"} ${lpDefaultManager}`);
  console.log(`   YieldOptimizer:      ${lpYieldOptimizer === deployment.contracts.YieldOptimizer ? "✅" : "❌"} ${lpYieldOptimizer}`);
  console.log(`   CreditManager:       ${lpCreditManager === deployment.contracts.CreditManager ? "✅" : "❌"} ${lpCreditManager}`);

  // Verify CreditManager authorizations
  console.log("\n2. CreditManager Authorizations:");
  const cmLendingPool = await lendingPool.getAddress();
  const cmDefaultManager = await lendingPool.defaultManager();
  
  console.log(`   LendingPool:         ${cmLendingPool === deployment.contracts.LendingPool ? "✅" : "❌"} ${cmLendingPool}`);
  console.log(`   DefaultManager:      ${cmDefaultManager === deployment.contracts.DefaultManager ? "✅" : "❌"} ${cmDefaultManager}`);

  // Verify LoanDocumentationNFT authorizations
  console.log("\n3. LoanDocumentationNFT Authorizations:");
  const isRequestManagerAuth = await loanDocNFT.authorizedContracts(
    deployment.contracts.RequestManager
  );
  const isRepaymentProcessorAuth = await loanDocNFT.authorizedContracts(
    deployment.contracts.RepaymentProcessor
  );
  const isDefaultManagerAuth = await loanDocNFT.authorizedContracts(
    deployment.contracts.DefaultManager
  );

  console.log(`   RequestManager:      ${isRequestManagerAuth ? "✅" : "❌"}`);
  console.log(`   RepaymentProcessor:  ${isRepaymentProcessorAuth ? "✅" : "❌"}`);
  console.log(`   DefaultManager:      ${isDefaultManagerAuth ? "✅" : "❌"}`);

  // Verify pool max cap
  console.log("\n4. Pool Configuration:");
  const currentPoolCap = await lendingPool.poolMaxCap();
  if (currentPoolCap === 0n) {
    console.log(`   Pool Max Cap:        ✅ UNLIMITED`);
  } else {
    const capInUSDC = Number(currentPoolCap) / 1e6;
    console.log(`   Pool Max Cap:        ✅ ${capInUSDC.toLocaleString()} USDC`);
  }

  if (
    lpRequestManager !== deployment.contracts.RequestManager ||
    lpRepaymentProcessor !== deployment.contracts.RepaymentProcessor ||
    lpDefaultManager !== deployment.contracts.DefaultManager ||
    lpYieldOptimizer !== deployment.contracts.YieldOptimizer ||
    lpCreditManager !== deployment.contracts.CreditManager ||
    !isRequestManagerAuth ||
    !isRepaymentProcessorAuth ||
    !isDefaultManagerAuth
  ) {
    console.error("\n❌ ERROR: Not all contracts are properly authorized!");
    process.exit(1);
  }

  console.log("");

  console.log("========================================");
  console.log("CONFIGURATION COMPLETE!");
  console.log("========================================\n");

  console.log("All contracts are now properly configured and ready to use.\n");

  console.log("Next Steps:");
  console.log("1. Fund test wallets with Avalanche Fuji USDC from:");
  console.log("   - Core Faucet: https://core.app/en/tools/testnet-faucet/");
  console.log("   - Or transfer from another wallet");
  console.log("2. Test deployment: npm run flow:avax:native");
  console.log("3. Add borrowers using CreditManager");
  console.log("4. Lenders can deposit USDC");
  console.log("");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ ERROR:", error);
    process.exit(1);
  });
