// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IRequestManager
 * @notice Interface for borrow request workflow and management
 */
interface IRequestManager {
    enum RequestStatus {
        PENDING,
        APPROVED,
        DISBURSED,
        DENIED,
        CANCELLED
    }

    struct BorrowRequest {
        address borrower;
        uint256 amount;
        uint256 termDays;
        uint256 timestamp;
        uint256 lockedAPY;
        RequestStatus status;
    }

    // Events
    event BorrowRequestSubmitted(
        uint256 indexed requestId,
        address indexed borrower,
        uint256 amount,
        uint256 termDays,
        uint256 indexed documentationNFT
    );
    event BorrowRequestApproved(uint256 indexed requestId, uint256 apy);
    event BorrowRequestDenied(uint256 indexed requestId, string reason);
    event BorrowDisbursed(
        uint256 indexed requestId,
        address indexed borrower,
        uint256 netAmount,
        uint256 withheld
    );
    event RequestCancelled(uint256 indexed requestId);

    // Borrower functions
    function submitBorrowRequest(
        uint256 amount,
        uint256 termDays,
        string memory businessName,
        string memory businessType,
        bytes32 financialStatementsHash,
        bytes32 businessPlanHash,
        bytes32 collateralProofHash,
        bytes32 kybDocumentsHash
    ) external returns (uint256 requestId);
    function cancelRequest(uint256 requestId) external;

    // Admin functions
    function approveBorrowRequest(uint256 requestId, uint256 apy) external;
    function denyBorrowRequest(
        uint256 requestId,
        string memory reason
    ) external;
    function disburseBorrow(uint256 requestId) external;

    // View functions
    function getRequest(
        uint256 requestId
    ) external view returns (BorrowRequest memory);
    function getBorrowerActiveRequest(
        address borrower
    ) external view returns (uint256);
}
