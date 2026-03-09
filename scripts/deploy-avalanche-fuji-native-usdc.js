const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("========================================");
  console.log("Deploying KEA Credit Contracts to Avalanche Fuji C-Chain");
  console.log("Using NATIVE USDC (No MockUSDC)");
  console.log("========================================\n");

  // ============================================================================
  // CONFIGURATION PARAMETERS - MODIFY THESE BEFORE DEPLOYMENT
  // ============================================================================
  
  // Pool Maximum Cap (in USDC with 6 decimals)
  // Set to 0 for unlimited pool size
  // Example: 1000000000000 = 1,000,000 USDC
  const POOL_MAX_CAP = 1000000000000n; // 0 = Unlimited (change this value as needed)
  
  console.log("📋 Configuration:");
  if (POOL_MAX_CAP === 0n) {
    console.log("   Pool Max Cap: UNLIMITED");
  } else {
    const capInUSDC = Number(POOL_MAX_CAP) / 1e6;
    console.log(`   Pool Max Cap: ${capInUSDC.toLocaleString()} USDC`);
  }
  console.log("");
  
  // ============================================================================

  // Load environment variables
  require("dotenv").config();

  // Get deployer account
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();

  console.log("Deploying contracts with account:", deployerAddress);

  // Check deployer balance
  const balance = await ethers.provider.getBalance(deployerAddress);
  console.log("Account balance:", ethers.formatEther(balance), "ETH\n");

  // Get Avalanche Fuji USDC address from environment variable
  const AVALANCHE_NATIVE_USDC_ADDRESS = process.env.AVALANCHE_NATIVE_USDC_ADDRESS;

  if (!AVALANCHE_NATIVE_USDC_ADDRESS) {
    throw new Error(
      "❌ AVALANCHE_NATIVE_USDC_ADDRESS not found in .env file!\n" +
        "   Please add: AVALANCHE_NATIVE_USDC_ADDRESS=0x5425890298aed601595a70AB815c96711a31Bc65\n" +
        "   This is USDC on Avalanche Fuji C-Chain"
    );
  }

  console.log("✅ Using Avalanche Fuji USDC at:", AVALANCHE_NATIVE_USDC_ADDRESS);
  console.log("");

  // Verify it's a valid address
  if (!ethers.isAddress(AVALANCHE_NATIVE_USDC_ADDRESS)) {
    throw new Error("❌ Invalid AVALANCHE_NATIVE_USDC_ADDRESS format!");
  }

  // Optional: Verify it's actually a USDC contract
  try {
    const usdc = await ethers.getContractAt("IERC20", AVALANCHE_NATIVE_USDC_ADDRESS);
    const symbol = await usdc.symbol();
    const decimals = await usdc.decimals();
    console.log(`   Token Symbol: ${symbol}`);
    console.log(`   Token Decimals: ${decimals}`);
    if (decimals !== 6) {
      console.warn(
        `   ⚠️  WARNING: Token has ${decimals} decimals, expected 6 for USDC!`
      );
    }
    console.log("");
  } catch (error) {
    console.warn(
      "   ⚠️  Could not verify token contract (might not have symbol/decimals methods)"
    );
    console.log("");
  }

  const deployedContracts = {};

  // Helper function to add delay between deployments
  const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

  // LendingPool
  console.log("1. Deploying LendingPool...");
  const LendingPool = await ethers.getContractFactory("LendingPool");
  const lendingPool = await LendingPool.deploy(AVALANCHE_NATIVE_USDC_ADDRESS);
  await lendingPool.waitForDeployment();
  const lendingPoolAddress = await lendingPool.getAddress();
  deployedContracts.LendingPool = lendingPoolAddress;
  console.log("   LendingPool deployed at:", lendingPoolAddress);
  console.log("");
  
  // Wait 3 seconds before next deployment
  console.log("   ⏳ Waiting 3s for transaction to settle...");
  await delay(3000);

  // CreditManager
  console.log("2. Deploying CreditManager...");
  const CreditManager = await ethers.getContractFactory("CreditManager");
  const creditManager = await CreditManager.deploy();
  await creditManager.waitForDeployment();
  const creditManagerAddress = await creditManager.getAddress();
  deployedContracts.CreditManager = creditManagerAddress;
  console.log("   CreditManager deployed at:", creditManagerAddress);
  console.log("");
  
  console.log("   ⏳ Waiting 3s for transaction to settle...");
  await delay(3000);

  // InterestRateModel
  console.log("3. Deploying InterestRateModel...");
  const PRECISION = BigInt(1e6); // 6 decimals
  const baseRate = 2n * PRECISION; // 2%
  const slope1 = 10n * PRECISION; // 10%
  const slope2 = 50n * PRECISION; // 50%
  const kinkPoint = 80n * PRECISION; // 80%
  const minAPY = 4n * PRECISION; // 4%
  const maxAPY = 25n * PRECISION; // 25%

  const InterestRateModel = await ethers.getContractFactory(
    "InterestRateModel"
  );
  const interestRateModel = await InterestRateModel.deploy(
    baseRate,
    slope1,
    slope2,
    kinkPoint,
    minAPY,
    maxAPY
  );
  await interestRateModel.waitForDeployment();
  const interestRateModelAddress = await interestRateModel.getAddress();
  deployedContracts.InterestRateModel = interestRateModelAddress;
  console.log("   InterestRateModel deployed at:", interestRateModelAddress);
  console.log("");
  
  console.log("   ⏳ Waiting 3s for transaction to settle...");
  await delay(3000);

  // LoanDocumentationNFT
  console.log("4. Deploying LoanDocumentationNFT...");
  const LoanDocumentationNFT = await ethers.getContractFactory(
    "LoanDocumentationNFT"
  );
  const loanDocNFT = await LoanDocumentationNFT.deploy();
  await loanDocNFT.waitForDeployment();
  const loanDocNFTAddress = await loanDocNFT.getAddress();
  deployedContracts.LoanDocumentationNFT = loanDocNFTAddress;
  console.log("   LoanDocumentationNFT deployed at:", loanDocNFTAddress);
  console.log("");
  
  console.log("   ⏳ Waiting 3s for transaction to settle...");
  await delay(3000);

  // RequestManager
  console.log("5. Deploying RequestManager...");
  const RequestManager = await ethers.getContractFactory("RequestManager");
  const requestManager = await RequestManager.deploy(
    AVALANCHE_NATIVE_USDC_ADDRESS,
    lendingPoolAddress,
    creditManagerAddress,
    interestRateModelAddress,
    loanDocNFTAddress
  );
  await requestManager.waitForDeployment();
  const requestManagerAddress = await requestManager.getAddress();
  deployedContracts.RequestManager = requestManagerAddress;
  console.log("   RequestManager deployed at:", requestManagerAddress);
  console.log("");
  
  console.log("   ⏳ Waiting 3s for transaction to settle...");
  await delay(3000);

  // RepaymentProcessor
  console.log("6. Deploying RepaymentProcessor...");
  const RepaymentProcessor = await ethers.getContractFactory(
    "RepaymentProcessor"
  );
  const repaymentProcessor = await RepaymentProcessor.deploy(
    AVALANCHE_NATIVE_USDC_ADDRESS,
    lendingPoolAddress,
    loanDocNFTAddress
  );
  await repaymentProcessor.waitForDeployment();
  const repaymentProcessorAddress = await repaymentProcessor.getAddress();
  deployedContracts.RepaymentProcessor = repaymentProcessorAddress;
  console.log("   RepaymentProcessor deployed at:", repaymentProcessorAddress);
  console.log("");
  
  console.log("   ⏳ Waiting 3s for transaction to settle...");
  await delay(3000);

  // DefaultManager
  console.log("7. Deploying DefaultManager...");
  const DefaultManager = await ethers.getContractFactory("DefaultManager");
  const defaultManager = await DefaultManager.deploy(
    lendingPoolAddress,
    creditManagerAddress,
    loanDocNFTAddress
  );
  await defaultManager.waitForDeployment();
  const defaultManagerAddress = await defaultManager.getAddress();
  deployedContracts.DefaultManager = defaultManagerAddress;
  console.log("   DefaultManager deployed at:", defaultManagerAddress);
  console.log("");
  
  console.log("   ⏳ Waiting 3s for transaction to settle...");
  await delay(3000);

  // YieldOptimizer
  console.log("8. Deploying YieldOptimizer...");
  const YieldOptimizer = await ethers.getContractFactory("YieldOptimizer");
  const yieldOptimizer = await YieldOptimizer.deploy(
    AVALANCHE_NATIVE_USDC_ADDRESS,
    lendingPoolAddress,
    ethers.ZeroAddress, // Aave pool (not deployed on Avalanche Fuji yet)
    ethers.ZeroAddress // aUSDC (not deployed on Avalanche Fuji yet)
  );
  await yieldOptimizer.waitForDeployment();
  const yieldOptimizerAddress = await yieldOptimizer.getAddress();
  deployedContracts.YieldOptimizer = yieldOptimizerAddress;
  console.log("   YieldOptimizer deployed at:", yieldOptimizerAddress);
  console.log("");

  // Save deployment info
  const deploymentInfo = {
    network: "Avalanche Fuji C-Chain Testnet",
    chainId: 43113,
    timestamp: new Date().toISOString(),
    deployer: deployerAddress,
    nativeUSDC: AVALANCHE_NATIVE_USDC_ADDRESS,
    contracts: deployedContracts,
    config: {
      poolMaxCap: POOL_MAX_CAP.toString(),
    },
  };

  const deploymentDir = path.join(__dirname, "..", "deployment");
  if (!fs.existsSync(deploymentDir)) {
    fs.mkdirSync(deploymentDir, { recursive: true });
  }

  const deploymentPath = path.join(
    deploymentDir,
    "avalanche-fuji-native-usdc-deployment.json"
  );
  fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));

  console.log("========================================");
  console.log("DEPLOYMENT COMPLETE!");
  console.log("========================================\n");

  console.log("Contract Addresses:");
  console.log("-------------------");
  console.log("Avalanche Fuji USDC :", AVALANCHE_NATIVE_USDC_ADDRESS);
  console.log("LendingPool         :", lendingPoolAddress);
  console.log("CreditManager       :", creditManagerAddress);
  console.log("InterestRateModel   :", interestRateModelAddress);
  console.log("LoanDocumentationNFT:", loanDocNFTAddress);
  console.log("RequestManager      :", requestManagerAddress);
  console.log("RepaymentProcessor  :", repaymentProcessorAddress);
  console.log("DefaultManager      :", defaultManagerAddress);
  console.log("YieldOptimizer      :", yieldOptimizerAddress);
  console.log("");

  console.log("Configuration:");
  console.log("--------------");
  if (POOL_MAX_CAP === 0n) {
    console.log("Pool Max Cap        : UNLIMITED");
  } else {
    const capInUSDC = Number(POOL_MAX_CAP) / 1e6;
    console.log(`Pool Max Cap        : ${capInUSDC.toLocaleString()} USDC`);
  }
  console.log("");

  console.log("✅ Deployment addresses saved to:", deploymentPath);
  console.log("");

  console.log("Next Steps:");
  console.log("1. Run: npm run configure:avax:native");
  console.log("   (This will set all permissions AND apply the pool max cap)");
  console.log("2. Fund wallets with Avalanche Fuji USDC from: https://core.app/en/tools/testnet-faucet/");
  console.log("3. Test deployment: npm run flow:avax:native");
  console.log("");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ ERROR:", error);
    process.exit(1);
  });
