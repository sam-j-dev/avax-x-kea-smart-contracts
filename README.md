# KEA Credit — Smart Contracts

Solidity smart contracts for the KEA Credit DeFi lending protocol, deployed on **Avalanche Fuji C-Chain**. The protocol connects institutional lenders with screened SME borrowers through a permissioned, admin-governed lending pool.

---

## Contract Architecture

Eight purpose-built contracts, each with a single responsibility, communicating through defined interfaces.

| Contract | Role |
|---|---|
| `LendingPool` | Core capital hub — holds USDC, issues LP tokens, tracks loans & interest, enforces 80% utilization cap |
| `CreditManager` | Stores borrower profiles, credit limits, and default status — single source of eligibility truth |
| `RequestManager` | Manages the full loan lifecycle: submission, admin approval, and USDC disbursement |
| `RepaymentProcessor` | Accepts borrower repayments, splits interest between lenders and the protocol reserve |
| `DefaultManager` | Monitors loan due dates, marks defaults, and socializes losses proportionally across the pool |
| `InterestRateModel` | Calculates utilization-based APY guidance; admin locks in final rate at approval time |
| `LoanDocumentationNFT` | Mints a non-transferable (soulbound) NFT per loan as an immutable on-chain audit trail |
| `YieldOptimizer` | Deploys idle pool capital to Aave V3 to generate a base yield floor for lenders |

### Interfaces

Each contract has a corresponding interface under `src/interfaces/`:
`ICreditManager`, `ILendingPool`, `IRequestManager`, `IInterestRateModel`, `ILoanDocumentationNFT`, `IYieldOptimizer`

---

## Protocol Safeguards

- **80% utilization hard cap** — `LendingPool.recordBorrow()` reverts if total borrowed would exceed 80% of assets; always preserves a 20% liquid reserve
- **One active loan per borrower** — enforced at contract level via `borrowerActiveRequest` mapping
- **Rate locked at approval** — `InterestRateModel` provides guidance; admin sets and locks the final APY at approval time, never floating mid-loan
- **Equal-risk pooling** — defaults are socialized proportionally across all lenders, not isolated
- **Interest withheld in pool** — recognized interest accrues inside the pool before distribution, maintaining a cash buffer
- **Protocol reserve split** — a percentage of every repayment is routed to a separate reserve fund as a secondary loss buffer
- **ReentrancyGuard** on all fund-moving contracts

---

## Prerequisites

- Node.js >= 18
- npm or yarn
- A funded wallet on Avalanche Fuji C-Chain (get test AVAX from the [Avalanche Fuji Faucet](https://faucet.avax.network/))

---

## Installation

```bash
npm install
```

---

## Environment Setup

Copy the example env file and fill in your values:

```bash
cp env.example .env
```

| Variable | Description |
|---|---|
| `PRIVATE_KEY` | Admin/deployer wallet private key |
| `LENDER1_PRIVATE_KEY` | Test lender 1 wallet (for test flow) |
| `LENDER2_PRIVATE_KEY` | Test lender 2 wallet (for test flow) |
| `BORROWER_PRIVATE_KEY` | Test borrower wallet (for test flow) |
| `AVALANCHE_FUJI_RPC_URL` | Avalanche Fuji RPC — defaults to `https://api.avax-test.network/ext/bc/C/rpc` |
| `NATIVE_USDC_ADDRESS` | Fuji USDC: `0x5425890298aed601595a70AB815c96711a31Bc65` |
| `SNOWTRACE_API_KEY` | Optional — for contract verification on Snowscan |

After deployment, add the deployed contract addresses to `.env` for use in configure and test flow scripts.

---

## Scripts

### Compile

```bash
npm run compile
```

### Test

```bash
npm run test
```

### Test with gas report

```bash
npm run test:gas
```

### Deploy to Avalanche Fuji

Uses native Fuji USDC (no MockUSDC):

```bash
npm run deploy:avax:native
```

Before deploying, set `POOL_MAX_CAP` at the top of `scripts/deploy-avalanche-fuji-native-usdc.js` (in USDC with 6 decimals). Set to `0n` for unlimited.

### Configure contracts after deployment

Wires up contract references and sets initial parameters:

```bash
npm run configure:avax:native
```

### Run the full end-to-end test flow on Fuji

Simulates lender deposits, borrower requests, admin approval, disbursement, and repayment:

```bash
npm run flow:avax:native
```

### Lender withdraw all

Utility script to withdraw all lender positions:

```bash
npx hardhat run scripts/lender-withdraw-all.js --network avalancheFuji
```

### Verify contracts on Snowscan

```bash
npm run verify:avax -- <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
```

---

## Deployment Order

The contracts must be deployed and configured in this sequence:

1. `InterestRateModel`
2. `CreditManager`
3. `LoanDocumentationNFT`
4. `LendingPool` (requires USDC address + pool max cap)
5. `RequestManager` (requires USDC, LendingPool, CreditManager, InterestRateModel, LoanDocNFT)
6. `RepaymentProcessor` (requires USDC, LendingPool)
7. `DefaultManager` (requires LendingPool, CreditManager, LoanDocNFT)
8. `YieldOptimizer` (requires LendingPool, USDC)

After deployment, run the configure script to wire all contract cross-references and authorize contracts to call each other.

---

## Network Configuration

| Network | Chain ID | RPC |
|---|---|---|
| Avalanche Fuji C-Chain | 43113 | `https://api.avax-test.network/ext/bc/C/rpc` |
| Hardhat local | 31337 | `http://127.0.0.1:8545` |

Block explorer: [https://testnet.snowscan.xyz](https://testnet.snowscan.xyz)

---

## Project Structure

```
src/
├── interfaces/          # Contract interfaces (ICreditManager, ILendingPool, etc.)
├── LendingPool.sol
├── LendingPoolNoPenalty.sol
├── CreditManager.sol
├── RequestManager.sol
├── RepaymentProcessor.sol
├── DefaultManager.sol
├── InterestRateModel.sol
├── LoanDocumentationNFT.sol
├── YieldOptimizer.sol
└── MockUSDC.sol         # Test only — not for production deployment

scripts/
├── deploy-avalanche-fuji-native-usdc.js    # Main deployment script
├── configure-avalanche-fuji-native-usdc.js # Post-deploy wiring
├── unified-test-flow-avalanche-fuji-native-usdc.js  # End-to-end test
└── lender-withdraw-all.js                  # Utility

test/                    # Hardhat test suite
artifacts/               # Compiled contract artifacts (git-ignored)
cache/                   # Hardhat cache (git-ignored)
```

---

## Security Notes

- Never commit `.env` or any file containing private keys
- Use separate test wallets for development — never use a wallet holding real funds
- The `MockUSDC.sol` contract is for local testing only and must not be deployed to mainnet
- All fund-moving functions are protected with OpenZeppelin's `ReentrancyGuard`
- Contract cross-authorization uses explicit whitelists — not blanket `onlyOwner`

---