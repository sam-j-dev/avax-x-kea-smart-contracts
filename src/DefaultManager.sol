// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ICreditManager.sol";
import "./interfaces/ILoanDocumentationNFT.sol";

/**
 * @title DefaultManager
 * @notice Handles loan defaults and loss socialization
 * @dev Monitors due dates, triggers defaults, distributes losses to lenders
 */
contract DefaultManager is Ownable {
    ILendingPool public lendingPool;
    ICreditManager public creditManager;
    ILoanDocumentationNFT public loanDocNFT;
    
    // Authorized contracts
    address public requestManager;

    // Grace period before default (7 days)
    uint256 public constant GRACE_PERIOD = 7 days;

    // Default tracking
    struct DefaultRecord {
        uint256 principalLost;
        uint256 interestHeld;
        uint256 netLoss;
        uint256 requestId; // Link to NFT
        uint256 timestamp;
    }
    mapping(address => DefaultRecord) public defaults;
    mapping(address => uint256) public loanDueDates;
    mapping(address => uint256) public loanRequestIds; // Track requestId per borrower

    event DefaultMarked(
        address indexed borrower,
        uint256 principalLost,
        uint256 interestHeld,
        uint256 netLoss
    );
    event LoanDueDateRecorded(address indexed borrower, uint256 dueDate);
    event GracePeriodExpired(address indexed borrower);

    constructor(
        address _lendingPool,
        address _creditManager,
        address _loanDocNFT
    ) Ownable(msg.sender) {
        require(_lendingPool != address(0), "Invalid LendingPool");
        require(_creditManager != address(0), "Invalid CreditManager");
        require(_loanDocNFT != address(0), "Invalid LoanDocNFT");

        lendingPool = ILendingPool(_lendingPool);
        creditManager = ICreditManager(_creditManager);
        loanDocNFT = ILoanDocumentationNFT(_loanDocNFT);
    }
    
    /**
     * @notice Set RequestManager address for authorization
     * @param _requestManager Address of RequestManager
     */
    function setRequestManager(address _requestManager) external onlyOwner {
        requestManager = _requestManager;
    }
    
    modifier onlyAuthorized() {
        require(
            msg.sender == owner() || msg.sender == requestManager,
            "Not authorized"
        );
        _;
    }

    /**
     * @notice Record loan due date (called when loan is disbursed)
     * @param borrower Address of borrower
     * @param dueDate Unix timestamp of due date
     * @param requestId Request ID for NFT tracking
     */
    function recordLoanDueDate(
        address borrower,
        uint256 dueDate,
        uint256 requestId
    ) external onlyAuthorized {
        loanDueDates[borrower] = dueDate;
        loanRequestIds[borrower] = requestId;
        emit LoanDueDateRecorded(borrower, dueDate);
    }

    /**
     * @notice Mark loan as defaulted (after grace period)
     * @param borrower Address of borrower
     */
    function markDefault(address borrower) external onlyOwner {
        uint256 dueDate = loanDueDates[borrower];
        require(dueDate > 0, "No active loan");
        require(
            block.timestamp > dueDate + GRACE_PERIOD,
            "Grace period not expired"
        );

        // Get loan details from LendingPool
        (
            uint256 principalLost,
            uint256 interestHeld,
            ,
            bool active
        ) = getLoanInfo(borrower);
        require(active, "Loan not active");

        // Calculate net loss (Principal - Interest collected)
        uint256 netLoss = principalLost > interestHeld
            ? principalLost - interestHeld
            : 0;

        // Get request ID for NFT update
        uint256 requestId = loanRequestIds[borrower];

        // Record default
        defaults[borrower] = DefaultRecord({
            principalLost: principalLost,
            interestHeld: interestHeld,
            netLoss: netLoss,
            requestId: requestId,
            timestamp: block.timestamp
        });

        // Notify LendingPool to handle loss socialization
        lendingPool.recordDefault(borrower, principalLost, interestHeld);

        // Mark borrower as defaulted in CreditManager
        creditManager.markBorrowerDefaulted(borrower);

        // Update documentation NFT - mark as defaulted
        uint256 docTokenId = loanDocNFT.getTokenIdByRequestId(requestId);
        loanDocNFT.updateStatus(
            docTokenId,
            ILoanDocumentationNFT.LoanStatus.DEFAULTED
        );

        // Clear due date and request ID
        delete loanDueDates[borrower];
        delete loanRequestIds[borrower];

        emit DefaultMarked(borrower, principalLost, interestHeld, netLoss);
    }

    /**
     * @notice Calculate loss for a potential default
     * @param borrower Address of borrower
     * @return netLoss Net loss amount (Principal - Interest)
     */
    function calculateLoss(
        address borrower
    ) external view returns (uint256 netLoss) {
        (uint256 principal, uint256 interest, , bool active) = getLoanInfo(
            borrower
        );
        if (!active) return 0;

        netLoss = principal > interest ? principal - interest : 0;
    }

    /**
     * @notice Check if loan is in default status (past grace period)
     * @param borrower Address of borrower
     * @return True if in default
     */
    function queryDefaultStatus(address borrower) external view returns (bool) {
        uint256 dueDate = loanDueDates[borrower];
        if (dueDate == 0) return false;
        return block.timestamp > dueDate + GRACE_PERIOD;
    }

    /**
     * @notice Check if loan is overdue but still in grace period
     * @param borrower Address of borrower
     * @return True if overdue but in grace period
     */
    function isInGracePeriod(address borrower) external view returns (bool) {
        uint256 dueDate = loanDueDates[borrower];
        if (dueDate == 0) return false;
        return
            block.timestamp > dueDate &&
            block.timestamp <= dueDate + GRACE_PERIOD;
    }

    /**
     * @notice Get default record
     * @param borrower Address of borrower
     * @return Default record details
     */
    function getDefaultRecord(
        address borrower
    ) external view returns (DefaultRecord memory) {
        return defaults[borrower];
    }

    /**
     * @notice Get loan info from LendingPool (internal helper)
     */
    function getLoanInfo(
        address borrower
    )
        internal
        view
        returns (
            uint256 principal,
            uint256 withheldInterest,
            uint256 dueDate,
            bool active
        )
    {
        // This would need to call LendingPool's loan info
        // For now, return placeholder values
        // In production, LendingPool should expose getLoanInfo()
        return (0, 0, 0, false);
    }
}
