// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ICreditManager.sol";

/**
 * @title LendingPoolNoPenalty
 * @notice Same as LendingPool but early withdrawals have NO penalty - for specific pools only
 * @dev Use this variant for pools where lender lock period penalty is disabled
 */
contract LendingPoolNoPenalty is ILendingPool, ERC20, Ownable, ReentrancyGuard {
    IERC20 public immutable USDC;

    // Pool state (all in 6 decimals to match USDC)
    uint256 public availableCash; // Liquid USDC in pool
    uint256 public totalBorrowed; // Currently outstanding loans (assets)
    uint256 public recognizedInterest; // Interest from repaid loans
    uint256 public withheldInterest; // Interest from active loans (tracked separately)
    uint256 public reserveFund; // Protocol fees (separate accounting)
    uint256 public aaveYield; // Yield from Aave deployment

    // Individual deposit tracking
    struct DepositRecord {
        uint256 amount;
        uint256 timestamp;
        uint256 lockUntil;
        uint256 shares;
    }

    // Lender information
    struct LenderInfo {
        uint256 shares; // LP shares in 6 decimals (matches USDC)
        uint256 lockUntil; // Weighted average lock period
        uint256 depositAmount;
        uint256[] depositIds; // Array of deposit IDs
    }
    mapping(address => LenderInfo) public lenders;
    
    // Deposit tracking
    mapping(address => mapping(uint256 => DepositRecord)) public deposits; // lender => depositId => DepositRecord
    mapping(address => uint256) public nextDepositId; // Next deposit ID for each lender

    // Loan tracking
    struct LoanInfo {
        uint256 principal;
        uint256 withheldInterest;
        uint256 dueDate;
        bool active;
    }
    mapping(address => LoanInfo) public loans;

    // Constants - Using 6 decimals for consistency with USDC
    uint256 private constant PRECISION = 1e6; // 6 decimals
    uint256 private constant PERCENT_100 = 100 * PRECISION;
    uint256 private constant RESERVE_BUFFER = 20 * PRECISION; // 20%
    uint256 private constant MIN_LOCK_DAYS = 30;
    uint256 private constant SECONDS_PER_DAY = 86400;
    uint256 private constant DAYS_PER_YEAR = 365;

    // Authorized contracts
    address public requestManager;
    address public repaymentProcessor;
    address public defaultManager;
    address public yieldOptimizer;
    address public creditManager;

    // Pool configuration
    uint256 public poolMaxCap; // 0 = no cap

    constructor(
        address _usdc
    ) ERC20("KeaCredit LP Token", "kcLP") Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC address");
        USDC = IERC20(_usdc);
    }

    /**
     * @notice Override decimals to match USDC (6 decimals)
     * @dev This ensures LP tokens use the same decimal system as USDC
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // Authorization setup
    function setAuthorizedContracts(
        address _requestManager,
        address _repaymentProcessor,
        address _defaultManager,
        address _yieldOptimizer,
        address _creditManager
    ) external onlyOwner {
        requestManager = _requestManager;
        repaymentProcessor = _repaymentProcessor;
        defaultManager = _defaultManager;
        yieldOptimizer = _yieldOptimizer;
        creditManager = _creditManager;
    }

    modifier onlyAuthorized() {
        require(
            msg.sender == requestManager ||
                msg.sender == repaymentProcessor ||
                msg.sender == defaultManager ||
                msg.sender == yieldOptimizer ||
                msg.sender == owner(),
            "Not authorized"
        );
        _;
    }

    /**
     * @notice Deposit USDC and receive LP tokens
     * @param amount Amount of USDC to deposit
     * @param lockDays Lock period in days (minimum 30)
     */
    function deposit(
        uint256 amount,
        uint256 lockDays
    ) external override nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(lockDays >= MIN_LOCK_DAYS, "Lock period too short");

        // Check pool max cap
        uint256 totalAssets = getTotalAssets();
        require(poolMaxCap == 0 || totalAssets + amount <= poolMaxCap, "Exceeds pool max cap");

        // Transfer USDC from lender
        require(
            USDC.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // Calculate shares to mint
        // Both USDC and LP shares use 6 decimals for simplicity
        uint256 sharesToMint;
        uint256 currentSharePrice = getSharePrice();

        if (totalSupply() == 0) {
            // Initial deposit: 1 USDC = 1 share (1:1 ratio at same decimals)
            sharesToMint = amount;
        } else {
            // Subsequent deposits: shares = (amount * PRECISION) / share price
            sharesToMint = (amount * PRECISION) / currentSharePrice;
        }

        // Mint LP tokens
        _mint(msg.sender, sharesToMint);

        // Update pool state FIRST (needed for accurate share price in weighted calculation)
        availableCash += amount;

        // Record individual deposit
        uint256 depositId = nextDepositId[msg.sender];
        uint256 newLockUntil = block.timestamp + (lockDays * SECONDS_PER_DAY);
        
        deposits[msg.sender][depositId] = DepositRecord({
            amount: amount,
            timestamp: block.timestamp,
            lockUntil: newLockUntil,
            shares: sharesToMint
        });
        
        // Add deposit ID to lender's deposit list
        lenders[msg.sender].depositIds.push(depositId);
        nextDepositId[msg.sender]++;

        // Calculate weighted average lock period
        uint256 weightedLockPeriod = calculateWeightedLockPeriod(msg.sender);

        // Update lender info
        lenders[msg.sender].shares = lenders[msg.sender].shares + sharesToMint;
        lenders[msg.sender].lockUntil = weightedLockPeriod;
        lenders[msg.sender].depositAmount = lenders[msg.sender].depositAmount + amount;

        emit Deposit(msg.sender, amount, sharesToMint, weightedLockPeriod);
    }

    /**
     * @notice Withdraw after lock period expires
     */
    function withdraw() external override nonReentrant {
        LenderInfo memory lenderInfo = lenders[msg.sender];
        require(lenderInfo.shares > 0, "No shares");
        require(
            block.timestamp >= lenderInfo.lockUntil,
            "Lock period not expired"
        );

        // Calculate withdrawal amount
        // shares (6 decimals) * sharePrice (6 decimals) / PRECISION = USDC (6 decimals)
        uint256 withdrawalAmount = (lenderInfo.shares * getSharePrice()) /
            PRECISION;
        require(withdrawalAmount <= availableCash, "Insufficient liquidity");

        // Burn LP tokens
        _burn(msg.sender, lenderInfo.shares);

        // Update state
        availableCash -= withdrawalAmount;
        delete lenders[msg.sender];

        // Transfer USDC
        require(USDC.transfer(msg.sender, withdrawalAmount), "Transfer failed");

        emit Withdraw(msg.sender, withdrawalAmount, lenderInfo.shares);
    }

    /**
     * @notice Partial withdrawal - withdraws specific USDC amount
     * @param usdcAmount Amount of USDC to withdraw (in 6 decimals)
     * @dev NO PENALTY: Early withdrawal same as normal - full amount to lender
     */
    function withdrawPartial(uint256 usdcAmount) external nonReentrant {
        LenderInfo storage lenderInfo = lenders[msg.sender];
        require(lenderInfo.shares > 0, "No shares");
        require(usdcAmount > 0, "Amount must be > 0");

        uint256 currentSharePrice = getSharePrice();
        uint256 totalValue = (lenderInfo.shares * currentSharePrice) / PRECISION;
        require(usdcAmount <= totalValue, "Exceeds available balance");

        bool isEarlyWithdrawal = block.timestamp < lenderInfo.lockUntil;
        uint256 sharesToBurn = (usdcAmount * PRECISION) / currentSharePrice;
        uint256 actualWithdrawal = usdcAmount;

        // NO PENALTY: Early or normal - lender receives full amount
        require(usdcAmount <= availableCash, "Insufficient liquidity");
        availableCash -= usdcAmount;

        require(sharesToBurn <= lenderInfo.shares, "Insufficient shares");

        // Burn shares
        _burn(msg.sender, sharesToBurn);
        lenderInfo.shares -= sharesToBurn;

        // Update deposit amount proportionally
        uint256 remainingSharesRatio = (lenderInfo.shares * PRECISION) / (lenderInfo.shares + sharesToBurn);
        lenderInfo.depositAmount = (lenderInfo.depositAmount * remainingSharesRatio) / PRECISION;

        // Update deposit records proportionally
        _updateDepositRecordsProportional(msg.sender, sharesToBurn, lenderInfo.shares + sharesToBurn);

        // Recalculate weighted lock period if shares remain
        if (lenderInfo.shares > 0) {
            lenderInfo.lockUntil = calculateWeightedLockPeriod(msg.sender);
        } else {
            // If all shares withdrawn, clean up
            delete lenders[msg.sender];
        }

        // Transfer USDC to lender (full amount)
        require(USDC.transfer(msg.sender, actualWithdrawal), "Transfer failed");

        if (isEarlyWithdrawal) {
            emit WithdrawEarly(msg.sender, actualWithdrawal, 0); // No penalty
        } else {
            emit Withdraw(msg.sender, actualWithdrawal, sharesToBurn);
        }
    }

    /**
     * @notice Update deposit records proportionally when doing partial withdrawal
     * @param lender Address of the lender
     * @param sharesBurned Shares being burned
     * @param totalSharesBefore Total shares before burning
     */
    function _updateDepositRecordsProportional(
        address lender, 
        uint256 sharesBurned, 
        uint256 totalSharesBefore
    ) internal {
        uint256[] memory depositIdList = lenders[lender].depositIds;
        
        for (uint256 i = 0; i < depositIdList.length; i++) {
            uint256 depositId = depositIdList[i];
            DepositRecord storage record = deposits[lender][depositId];
            
            // Reduce shares proportionally
            uint256 newShares = (record.shares * (totalSharesBefore - sharesBurned)) / totalSharesBefore;
            record.shares = newShares;
            
            // Reduce amount proportionally
            uint256 newAmount = (record.amount * (totalSharesBefore - sharesBurned)) / totalSharesBefore;
            record.amount = newAmount;
        }
    }

    /**
     * @notice Early withdrawal - NO PENALTY variant
     * @dev Lender receives full amount regardless of lock period
     */
    function withdrawEarly() external override nonReentrant {
        LenderInfo memory lenderInfo = lenders[msg.sender];
        require(lenderInfo.shares > 0, "No shares");
        require(block.timestamp < lenderInfo.lockUntil, "Lock already expired");

        // Calculate full withdrawal value - NO PENALTY
        uint256 grossAmount = (lenderInfo.shares * getSharePrice()) / PRECISION;

        require(grossAmount <= availableCash, "Insufficient liquidity");

        // Burn LP tokens
        _burn(msg.sender, lenderInfo.shares);

        // Update state - full amount withdrawn, no penalty split
        availableCash -= grossAmount;
        delete lenders[msg.sender];

        // Transfer full amount to lender (no penalty)
        require(USDC.transfer(msg.sender, grossAmount), "Transfer failed");

        emit WithdrawEarly(msg.sender, grossAmount, 0); // No penalty
    }

    /**
     * @notice Record borrow (called by RequestManager)
     * @param borrower Address of borrower
     * @param amount Principal amount
     * @param termDays Loan term in days
     * @param fixedAPY Locked interest rate
     */
    function recordBorrow(
        address borrower,
        uint256 amount,
        uint256 termDays,
        uint256 fixedAPY
    ) external override onlyAuthorized {
        // Enforce single active loan per borrower
        require(!loans[borrower].active, "Borrower has active loan");

        // Enforce Rule 1: Reserve Buffer
        uint256 maxBorrowable = calculateMaxBorrowable();
        require(
            totalBorrowed + amount <= maxBorrowable,
            "Exceeds max borrowable"
        );

        // Calculate interest and fees
        uint256 interest = (amount * fixedAPY * termDays) /
            (PERCENT_100 * DAYS_PER_YEAR);
        uint256 platformFee = (interest * 10 * PRECISION) / PERCENT_100; // 10% of interest
        uint256 lenderShare = interest - platformFee;

        // Update state
        totalBorrowed += amount;
        withheldInterest += lenderShare;
        reserveFund += platformFee;
        // Remove platform fee from available cash (moves to reserve fund, not available for lending)
        availableCash -= platformFee;
        // Note: lenderShare (withheld interest) stays in availableCash but tracked separately
        // Note: availableCash is further deducted in disburseLoan (net amount to borrower)

        // Record loan
        loans[borrower] = LoanInfo({
            principal: amount,
            withheldInterest: lenderShare,
            dueDate: block.timestamp + (termDays * SECONDS_PER_DAY),
            active: true
        });

        emit BorrowRecorded(borrower, amount, termDays, fixedAPY);
    }

    /**
     * @notice Disburse loan funds to borrower (called by RequestManager)
     * @param borrower Address to receive funds
     * @param netAmount Net amount after interest withholding
     */
    function disburseLoan(
        address borrower,
        uint256 netAmount
    ) external override onlyAuthorized {
        require(netAmount > 0, "Invalid amount");
        require(netAmount <= availableCash, "Insufficient liquidity");
        require(
            USDC.balanceOf(address(this)) >= netAmount,
            "Insufficient balance"
        );

        // Deduct net amount from available cash (interest + fees stay in pool)
        availableCash -= netAmount;

        // Update credit manager - increase currentBorrowed
        if (creditManager != address(0)) {
            ICreditManager(creditManager).updateBorrowedAmount(
                borrower,
                loans[borrower].principal
            );
        }

        // Transfer USDC to borrower
        require(USDC.transfer(borrower, netAmount), "Transfer failed");
    }

    /**
     * @notice Record repayment (called by RepaymentProcessor)
     * @param borrower Address of borrower
     * @param principalAmount Principal being repaid
     * @param interestAmount Interest amount (already held)
     */
    function recordRepayment(
        address borrower,
        uint256 principalAmount,
        uint256 interestAmount
    ) external override onlyAuthorized {
        require(loans[borrower].active, "No active loan");

        // Update state
        totalBorrowed -= principalAmount;
        availableCash += principalAmount;

        // Recognize interest (move from withheld to recognized)
        // Interest was withheld upfront and already in availableCash, just update tracking
        withheldInterest -= interestAmount;
        recognizedInterest += interestAmount;
        // Note: No change to availableCash - interest was already there, just releasing the "withheld" status

        // Update credit manager - decrease currentBorrowed to 0
        if (creditManager != address(0)) {
            ICreditManager(creditManager).updateBorrowedAmount(borrower, 0);
        }

        // Clear loan
        delete loans[borrower];

        emit RepaymentRecorded(borrower, principalAmount, interestAmount);
        emit InterestRecognized(interestAmount);
    }

    /**
     * @notice Record default (called by DefaultManager)
     * @param borrower Address of borrower
     * @param principalLost Principal amount lost
     * @param interestHeld Interest that was withheld
     */
    function recordDefault(
        address borrower,
        uint256 principalLost,
        uint256 interestHeld
    ) external override onlyAuthorized {
        require(loans[borrower].active, "No active loan");

        // Release withheld interest (no change to availableCash - it was already there)
        withheldInterest -= interestHeld;
        // Note: Interest stays in availableCash to offset the principal loss

        // Remove principal from borrowed (it's lost)
        totalBorrowed -= principalLost;

        // Net loss = Principal - Interest (socialized via share price decrease)
        // No need to explicitly reduce availableCash as principal was never returned

        // Update credit manager - decrease currentBorrowed to 0
        if (creditManager != address(0)) {
            ICreditManager(creditManager).updateBorrowedAmount(borrower, 0);
        }

        // Clear loan
        delete loans[borrower];
    }

    /**
     * @notice Claim yield (auto-compounds if not called)
     */
    function claimYield() external override {
        // In this model, yield auto-compounds via share price
        // This function can be used for manual distribution if needed
        revert("Yield auto-compounds");
    }

    // Admin functions

    /**
     * @notice Withdraw accumulated protocol fees from reserve fund
     * @param amount Amount to withdraw (must be <= reserveFund balance)
     * @dev Only owner can call this function
     */
    function withdrawReserveFund(
        uint256 amount
    ) external override onlyOwner nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(amount <= reserveFund, "Insufficient reserve fund");
        require(
            USDC.balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );

        reserveFund -= amount;

        require(USDC.transfer(msg.sender, amount), "Transfer failed");

        emit ReserveFundWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Emergency withdraw ALL USDC from the pool
     * @dev CRITICAL: This withdraws everything - use only in emergencies
     * @dev This will break the protocol state and prevent normal operations
     * @dev Only owner can call this function
     */
    function emergencyWithdraw() external override onlyOwner nonReentrant {
        uint256 totalBalance = USDC.balanceOf(address(this));
        require(totalBalance > 0, "No funds to withdraw");

        // Transfer entire USDC balance to owner
        require(USDC.transfer(msg.sender, totalBalance), "Transfer failed");

        emit EmergencyWithdraw(msg.sender, totalBalance);

        // Note: This does NOT reset pool state variables
        // The pool will be in an inconsistent state after this call
        // This function should only be used in critical emergencies
        // (e.g., security breach, critical bug discovery)
    }

    /**
     * @notice Update pool maximum cap
     * @param newMaxCap New maximum cap (0 for no cap)
     * @dev Only owner can call this function
     */
    function updatePoolMaxCap(uint256 newMaxCap) external onlyOwner {
        poolMaxCap = newMaxCap;
        emit PoolMaxCapUpdated(newMaxCap);
    }

    /**
     * @notice Calculate weighted average lock period for a lender
     * @param lender Address of the lender
     * @return Weighted average lock until timestamp
     */
    function calculateWeightedLockPeriod(address lender) internal view returns (uint256) {
        uint256[] memory depositIdList = lenders[lender].depositIds;
        if (depositIdList.length == 0) {
            return 0;
        }

        uint256 totalValue = 0;
        uint256 weightedSum = 0;
        uint256 currentTime = block.timestamp;

        for (uint256 i = 0; i < depositIdList.length; i++) {
            uint256 depositId = depositIdList[i];
            DepositRecord memory record = deposits[lender][depositId];
            
            // Only include deposits that haven't expired yet
            if (record.lockUntil > currentTime) {
                uint256 depositValue = (record.shares * getSharePrice()) / PRECISION;
                totalValue += depositValue;
                weightedSum += depositValue * record.lockUntil;
            }
        }

        if (totalValue == 0) {
            return currentTime; // All deposits expired
        }

        return weightedSum / totalValue;
    }

    // View functions

    function getTotalAssets() public view override returns (uint256) {
        // Total pool value = liquid cash + borrowed principal + protocol reserves + Aave deposits
        // Note: withheldInterest and recognizedInterest are already in availableCash, don't double-count
        return availableCash + totalBorrowed + reserveFund + aaveYield;
    }

    /**
     * @notice Get total assets that belong to lenders (excludes reserve fund)
     * @dev Used for share price calculation - reserve fund belongs to protocol, not lenders
     * @return Total lender assets in USDC (6 decimals)
     */
    function getTotalLenderAssets() public view returns (uint256) {
        // Lender assets = liquid cash + borrowed principal + Aave deposits
        // EXCLUDES reserveFund (protocol fees belong to owner, not lenders)
        return availableCash + totalBorrowed + aaveYield;
    }

    function getAvailableCash() external view override returns (uint256) {
        return availableCash;
    }

    function getTotalBorrowed() external view override returns (uint256) {
        return totalBorrowed;
    }

    function getWithheldInterest() external view override returns (uint256) {
        return withheldInterest;
    }

    function getReserveFund() external view override returns (uint256) {
        return reserveFund;
    }

    function getSharePrice() public view override returns (uint256) {
        if (totalSupply() == 0) {
            return PRECISION; // 1:1 initial price (1.000000 in 6 decimals)
        }
        // IMPORTANT: Use getTotalLenderAssets() NOT getTotalAssets()
        // Reserve fund belongs to protocol owner, not lenders
        // Share price = (lenderAssets * PRECISION) / totalSupply
        // Result is price per share in 6 decimal precision (e.g., 1.005000 = 1.005 USDC per share)
        return (getTotalLenderAssets() * PRECISION) / totalSupply();
    }

    function getLenderInfo(
        address lender
    )
        external
        view
        override
        returns (uint256 shares, uint256 lockUntil, uint256 depositAmount)
    {
        LenderInfo memory info = lenders[lender];
        return (info.shares, info.lockUntil, info.depositAmount);
    }

    function getUpcomingWithdrawals(
        uint256 untilDate
    ) external view override returns (uint256) {
        // This would need to iterate through all lenders (expensive)
        // In production, consider using an indexed structure or off-chain calculation
        // For now, return 0 as placeholder
        return 0;
    }

    function calculateMaxBorrowable() public view override returns (uint256) {
        // Use lender assets only - can't borrow from protocol reserves!
        uint256 lenderAssets = getTotalLenderAssets();
        return (lenderAssets * 80 * PRECISION) / PERCENT_100; // 80% of lender assets
    }

    function getAvailableCapital() external view override returns (uint256) {
        // Available cash already includes withheldInterest, just return availableCash
        // Note: withheldInterest is tracked separately but physically in availableCash
        return availableCash;
    }

    function hasActiveLoan(address borrower) external view returns (bool) {
        return loans[borrower].active;
    }

    /**
     * @notice Calculate current pool APY for lenders
     * @dev APY = (Total Interest Earning / Total Assets) * (365 / Average Loan Term)
     * @return Current annualized APY in 6 decimal precision (e.g., 12000000 = 12% APY)
     */
    function getCurrentPoolAPY() external view returns (uint256) {
        // Use lender assets only - APY is for lenders, not including protocol reserves
        uint256 lenderAssets = getTotalLenderAssets();
        if (lenderAssets == 0 || totalBorrowed == 0) {
            return 0;
        }

        // Calculate total annual interest potential
        // withheldInterest represents interest from active loans
        // We annualize it based on utilization
        uint256 utilizationRate = (totalBorrowed * PRECISION) / lenderAssets;
        
        // Estimate APY based on withheld interest as percentage of borrowed amount
        // Assuming average 60-day term (simplified)
        uint256 averageTermDays = 60;
        if (totalBorrowed > 0 && withheldInterest > 0) {
            // Calculate the interest rate: (withheldInterest / totalBorrowed)
            // Then annualize it: * (365 / averageTermDays)
            uint256 termInterestRate = (withheldInterest * PERCENT_100) / totalBorrowed;
            uint256 annualizedRate = (termInterestRate * DAYS_PER_YEAR) / averageTermDays;
            
            // Apply utilization to get pool APY
            // Pool APY = Loan APY * Utilization Rate * (1 - Protocol Fee)
            // Protocol takes 10%, so lenders get 90%
            uint256 lenderShare = (annualizedRate * 90) / 100;
            return (lenderShare * utilizationRate) / PRECISION;
        }

        return 0;
    }

    /**
     * @notice Get all deposit records for a lender
     * @param lender Address of the lender
     * @return depositIds Array of deposit IDs
     * @return amounts Array of deposit amounts
     * @return timestamps Array of deposit timestamps
     * @return lockUntils Array of lock until timestamps
     * @return shares Array of shares for each deposit
     */
    function getLenderDeposits(address lender) external view returns (
        uint256[] memory depositIds,
        uint256[] memory amounts,
        uint256[] memory timestamps,
        uint256[] memory lockUntils,
        uint256[] memory shares
    ) {
        uint256[] memory ids = lenders[lender].depositIds;
        uint256 length = ids.length;

        depositIds = new uint256[](length);
        amounts = new uint256[](length);
        timestamps = new uint256[](length);
        lockUntils = new uint256[](length);
        shares = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 depositId = ids[i];
            DepositRecord memory record = deposits[lender][depositId];
            
            depositIds[i] = depositId;
            amounts[i] = record.amount;
            timestamps[i] = record.timestamp;
            lockUntils[i] = record.lockUntil;
            shares[i] = record.shares;
        }

        return (depositIds, amounts, timestamps, lockUntils, shares);
    }
}
