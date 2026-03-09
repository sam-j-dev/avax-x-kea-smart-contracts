// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILendingPool
 * @notice Interface for the LendingPool contract - the core capital management hub
 */
interface ILendingPool {
    // Events
    event Deposit(
        address indexed lender,
        uint256 amount,
        uint256 shares,
        uint256 lockUntil
    );
    event Withdraw(address indexed lender, uint256 amount, uint256 shares);
    event WithdrawEarly(
        address indexed lender,
        uint256 amount,
        uint256 penalty
    );
    event BorrowRecorded(
        address indexed borrower,
        uint256 amount,
        uint256 termDays,
        uint256 fixedAPY
    );
    event RepaymentRecorded(
        address indexed borrower,
        uint256 principal,
        uint256 interest
    );
    event YieldRebalanced(uint256 amountDeployed, uint256 amountWithdrawn);
    event InterestRecognized(uint256 amount);
    event ReserveFundWithdrawn(address indexed admin, uint256 amount);
    event EmergencyWithdraw(address indexed admin, uint256 amount);
    event PoolMaxCapUpdated(uint256 newMaxCap);

    // Lender functions
    function deposit(uint256 amount, uint256 lockDays) external;
    function withdraw() external;
    function withdrawEarly() external;
    function withdrawPartial(uint256 usdcAmount) external;
    function claimYield() external;

    // Protocol functions (called by other contracts)
    function recordBorrow(
        address borrower,
        uint256 amount,
        uint256 termDays,
        uint256 fixedAPY
    ) external;
    function disburseLoan(address borrower, uint256 netAmount) external;
    function recordRepayment(
        address borrower,
        uint256 principalAmount,
        uint256 interestAmount
    ) external;
    function recordDefault(
        address borrower,
        uint256 principalLost,
        uint256 interestHeld
    ) external;

    // Admin functions
    function withdrawReserveFund(uint256 amount) external;
    function emergencyWithdraw() external;

    // View functions
    function getTotalAssets() external view returns (uint256);
    function getTotalLenderAssets() external view returns (uint256);
    function getAvailableCash() external view returns (uint256);
    function getTotalBorrowed() external view returns (uint256);
    function getWithheldInterest() external view returns (uint256);
    function getReserveFund() external view returns (uint256);
    function getSharePrice() external view returns (uint256);
    function getLenderInfo(
        address lender
    )
        external
        view
        returns (uint256 shares, uint256 lockUntil, uint256 depositAmount);
    function getUpcomingWithdrawals(
        uint256 untilDate
    ) external view returns (uint256);
    function calculateMaxBorrowable() external view returns (uint256);
    function getAvailableCapital() external view returns (uint256);
    function hasActiveLoan(address borrower) external view returns (bool);
}
