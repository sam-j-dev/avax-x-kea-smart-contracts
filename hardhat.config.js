require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const PRIVATE_KEY =
  process.env.PRIVATE_KEY ||
  "0x0000000000000000000000000000000000000000000000000000000000000000";
const AVALANCHE_FUJI_RPC_URL =
  process.env.AVALANCHE_FUJI_RPC_URL || "https://api.avax-test.network/ext/bc/C/rpc";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    // Avalanche Fuji C-Chain Testnet
    avalancheFuji: {
      url: AVALANCHE_FUJI_RPC_URL,
      accounts: [PRIVATE_KEY],
      chainId: 43113, // Avalanche Fuji C-Chain chain ID
      gasPrice: 30000000000, // 30 gwei - Avalanche typically needs higher gas
    },
    // Local Hardhat network for testing
    hardhat: {
      chainId: 31337,
    },
    // Localhost for local Hardhat node
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
  },
  paths: {
    sources: "./src",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },
  etherscan: {
    apiKey: {
      avalancheFuji: process.env.SNOWTRACE_API_KEY || "your-api-key",
    },
    customChains: [
      {
        network: "avalancheFuji",
        chainId: 43113, // Avalanche Fuji C-Chain chain ID
        urls: {
          apiURL: "https://api-testnet.snowscan.xyz/api",
          browserURL: "https://testnet.snowscan.xyz",
        },
      },
    ],
  },
};
