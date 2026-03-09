// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILoanDocumentationNFT
 * @notice Interface for the Loan Documentation NFT registry
 * @dev Used for transparency and audit trail of loan documentation
 */
interface ILoanDocumentationNFT {
    // Loan status enum
    enum LoanStatus {
        PENDING, // Request submitted, awaiting approval
        APPROVED, // Approved by admin, awaiting disbursement
        DISBURSED, // Funds disbursed to borrower
        REPAID, // Loan fully repaid
        DEFAULTED // Loan defaulted
    }

    // Loan documentation structure
    struct LoanDocumentation {
        uint256 tokenId;
        address borrower;
        uint256 requestId;
        // Public metadata
        string businessName;
        string businessType;
        uint256 requestedAmount;
        uint256 approvedAmount;
        uint256 approvedAPY;
        uint256 termDays;
        uint256 requestTimestamp;
        uint256 approvalTimestamp;
        uint256 disbursementTimestamp;
        uint256 repaymentTimestamp;
        // Document hashes (IPFS/Arweave)
        bytes32 financialStatementsHash;
        bytes32 businessPlanHash;
        bytes32 collateralProofHash;
        bytes32 kybDocumentsHash;
        // Risk assessment
        uint8 riskScore; // 1-10
        string riskCategory; // "Low", "Medium", "High"
        // Status
        LoanStatus status;
    }

    // Events
    event DocumentationMinted(
        uint256 indexed tokenId,
        address indexed borrower,
        uint256 indexed requestId,
        string businessName
    );
    event StatusUpdated(
        uint256 indexed tokenId,
        LoanStatus oldStatus,
        LoanStatus newStatus
    );
    event ApprovalRecorded(
        uint256 indexed tokenId,
        uint256 approvedAmount,
        uint256 approvedAPY
    );
    event RiskAssessmentUpdated(
        uint256 indexed tokenId,
        uint8 riskScore,
        string riskCategory
    );

    // Functions
    function mintDocumentation(
        address borrower,
        uint256 requestId,
        string memory businessName,
        string memory businessType,
        uint256 requestedAmount,
        uint256 termDays,
        bytes32 financialStatementsHash,
        bytes32 businessPlanHash,
        bytes32 collateralProofHash,
        bytes32 kybDocumentsHash
    ) external returns (uint256);

    function updateStatus(uint256 tokenId, LoanStatus newStatus) external;

    function recordApproval(
        uint256 tokenId,
        uint256 approvedAmount,
        uint256 approvedAPY
    ) external;

    function recordDisbursement(uint256 tokenId) external;

    function recordRepayment(uint256 tokenId) external;

    function updateRiskAssessment(
        uint256 tokenId,
        uint8 riskScore,
        string memory riskCategory
    ) external;

    // View functions
    function getDocumentation(
        uint256 tokenId
    ) external view returns (LoanDocumentation memory);

    function getTokenIdByRequestId(
        uint256 requestId
    ) external view returns (uint256);

    function getBorrowerTokens(
        address borrower
    ) external view returns (uint256[] memory);

    function totalDocumentations() external view returns (uint256);
}
