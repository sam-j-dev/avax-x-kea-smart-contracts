// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IRequestManager.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ICreditManager.sol";
import "./interfaces/IInterestRateModel.sol";
import "./interfaces/ILoanDocumentationNFT.sol";

/**
 * @title RequestManager
 * @notice Handles borrow request workflow, admin approval, and loan disbursement
 */
contract RequestManager is IRequestManager, Ownable, ReentrancyGuard {
    ILendingPool public lendingPool;
    ICreditManager public creditManager;
    IInterestRateModel public interestRateModel;
    ILoanDocumentationNFT public loanDocNFT;
    IERC20 public immutable USDC;
    
    // Additional contract references for automatic recording
    address public repaymentProcessor;
    address public defaultManager;

    // Request storage
    mapping(uint256 => BorrowRequest) public requests;
    mapping(address => uint256) public borrowerActiveRequest; // One active request per borrower
    uint256 public nextRequestId = 1;

    // Constants - Using 6 decimals for consistency with USDC and LP tokens
    uint256 private constant PRECISION = 1e6;
    uint256 private constant PERCENT_100 = 100 * PRECISION;
    uint256 private constant SECONDS_PER_DAY = 86400;
    uint256 private constant DAYS_PER_YEAR = 365;

    constructor(
        address _usdc,
        address _lendingPool,
        address _creditManager,
        address _interestRateModel,
        address _loanDocNFT
    ) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC");
        require(_lendingPool != address(0), "Invalid LendingPool");
        require(_creditManager != address(0), "Invalid CreditManager");
        require(_interestRateModel != address(0), "Invalid InterestRateModel");
        require(_loanDocNFT != address(0), "Invalid LoanDocNFT");

        USDC = IERC20(_usdc);
        lendingPool = ILendingPool(_lendingPool);
        creditManager = ICreditManager(_creditManager);
        interestRateModel = IInterestRateModel(_interestRateModel);
        loanDocNFT = ILoanDocumentationNFT(_loanDocNFT);
    }
    
    /**
     * @notice Set additional contract addresses for automatic recording
     * @param _repaymentProcessor Address of RepaymentProcessor
     * @param _defaultManager Address of DefaultManager
     */
    function setProcessorContracts(
        address _repaymentProcessor,
        address _defaultManager
    ) external onlyOwner {
        repaymentProcessor = _repaymentProcessor;
        defaultManager = _defaultManager;
    }

    /**
     * @notice Submit borrow request with documentation
     * @param amount Amount to borrow
     * @param termDays Loan term (30, 60, or 90 days)
     * @param businessName Borrower's business name
     * @param businessType Type of business
     * @param financialStatementsHash IPFS hash of financial statements
     * @param businessPlanHash IPFS hash of business plan
     * @param collateralProofHash IPFS hash of collateral documentation
     * @param kybDocumentsHash IPFS hash of KYB documents
     * @return requestId The ID of the created request
     */
    function submitBorrowRequest(
        uint256 amount,
        uint256 termDays,
        string memory businessName,
        string memory businessType,
        bytes32 financialStatementsHash,
        bytes32 businessPlanHash,
        bytes32 collateralProofHash,
        bytes32 kybDocumentsHash
    ) external override returns (uint256 requestId) {
        // Validate borrower
        require(
            creditManager.isBorrowerActive(msg.sender),
            "Not active borrower"
        );
        require(
            borrowerActiveRequest[msg.sender] == 0,
            "Existing pending request"
        );
        
        // Check if borrower has an active loan in LendingPool
        require(!lendingPool.hasActiveLoan(msg.sender), "Active loan exists - must repay before new request");

        // Validate amount and term
        require(amount > 0, "Amount must be > 0");
        require(
            amount <= creditManager.getRemainingCredit(msg.sender),
            "Exceeds remaining credit"
        );
        require(
            termDays == 30 || termDays == 60 || termDays == 90,
            "Invalid term (must be 30, 60, or 90 days)"
        );

        // Create request
        requestId = nextRequestId++;
        requests[requestId] = BorrowRequest({
            borrower: msg.sender,
            amount: amount,
            termDays: termDays,
            timestamp: block.timestamp,
            lockedAPY: 0, // Will be set on approval
            status: RequestStatus.PENDING
        });

        borrowerActiveRequest[msg.sender] = requestId;

        // Mint documentation NFT
        uint256 docTokenId = loanDocNFT.mintDocumentation(
            msg.sender,
            requestId,
            businessName,
            businessType,
            amount,
            termDays,
            financialStatementsHash,
            businessPlanHash,
            collateralProofHash,
            kybDocumentsHash
        );

        emit BorrowRequestSubmitted(
            requestId,
            msg.sender,
            amount,
            termDays,
            docTokenId
        );
    }

    /**
     * @notice Admin approves borrow request and sets APY
     * @param requestId ID of the request
     * @param apy Annual percentage yield (scaled by PRECISION)
     */
    function approveBorrowRequest(
        uint256 requestId,
        uint256 apy
    ) external override onlyOwner {
        BorrowRequest storage request = requests[requestId];
        require(request.status == RequestStatus.PENDING, "Request not pending");

        // Validate APY is within bounds
        require(interestRateModel.validateAPYRange(apy), "APY out of bounds");

        // Rule 2: Lock-Loan Maturity Matching
        uint256 loanDueDate = block.timestamp +
            (request.termDays * SECONDS_PER_DAY);
        uint256 upcomingWithdrawals = lendingPool.getUpcomingWithdrawals(
            loanDueDate
        );
        uint256 availableCapital = lendingPool.getAvailableCapital();

        require(
            availableCapital >= upcomingWithdrawals,
            "Insufficient capital for upcoming withdrawals"
        );

        // Lock APY
        request.lockedAPY = apy;
        request.status = RequestStatus.APPROVED;

        // Update documentation NFT with approval details
        uint256 docTokenId = loanDocNFT.getTokenIdByRequestId(requestId);
        loanDocNFT.recordApproval(docTokenId, request.amount, apy);

        emit BorrowRequestApproved(requestId, apy);
    }

    /**
     * @notice Admin disburses approved loan
     * @param requestId ID of the approved request
     */
    function disburseBorrow(
        uint256 requestId
    ) external override onlyOwner nonReentrant {
        BorrowRequest storage request = requests[requestId];
        require(
            request.status == RequestStatus.APPROVED,
            "Request not approved"
        );

        // Calculate interest and fees (upfront withholding)
        // Interest is withheld upfront and split: 90% to lenders, 10% to protocol
        uint256 interest = (request.amount *
            request.lockedAPY *
            request.termDays) / (PERCENT_100 * DAYS_PER_YEAR);
        // Note: The split into lenderShare (90%) and platformFee (10%) happens in LendingPool.recordBorrow()
        uint256 netDisbursement = request.amount - interest;

        // Record borrow in LendingPool (updates state, withholds interest)
        lendingPool.recordBorrow(
            request.borrower,
            request.amount,
            request.termDays,
            request.lockedAPY
        );

        // Disburse funds from LendingPool to borrower
        lendingPool.disburseLoan(request.borrower, netDisbursement);

        // Update request status
        request.status = RequestStatus.DISBURSED;
        delete borrowerActiveRequest[request.borrower];

        // Update documentation NFT - record disbursement
        uint256 docTokenId = loanDocNFT.getTokenIdByRequestId(requestId);
        loanDocNFT.recordDisbursement(docTokenId);
        
        // Automatically record loan in RepaymentProcessor for repayment tracking
        if (repaymentProcessor != address(0)) {
            uint256 lenderShare = (interest * 90) / 100; // 90% to lenders
            uint256 dueDate = block.timestamp + (request.termDays * SECONDS_PER_DAY);
            
            // Call RepaymentProcessor to record loan details
            (bool success, ) = repaymentProcessor.call(
                abi.encodeWithSignature(
                    "recordLoan(address,uint256,uint256,uint256,uint256)",
                    request.borrower,
                    request.amount,
                    lenderShare,
                    dueDate,
                    requestId
                )
            );
            require(success, "Failed to record in RepaymentProcessor");
        }
        
        // Automatically record due date in DefaultManager for default detection
        if (defaultManager != address(0)) {
            uint256 dueDate = block.timestamp + (request.termDays * SECONDS_PER_DAY);
            
            // Call DefaultManager to record due date
            (bool success, ) = defaultManager.call(
                abi.encodeWithSignature(
                    "recordLoanDueDate(address,uint256,uint256)",
                    request.borrower,
                    dueDate,
                    requestId
                )
            );
            require(success, "Failed to record in DefaultManager");
        }

        emit BorrowDisbursed(
            requestId,
            request.borrower,
            netDisbursement,
            interest // Total withheld = interest (split between lenders and protocol)
        );
    }
    
    /**
     * @notice Combined function: Approve and disburse loan in one transaction
     * @param requestId ID of the pending request
     * @param apy Annual percentage yield (scaled by PRECISION)
     * @dev This combines approveBorrowRequest() and disburseBorrow() for convenience
     */
    function approveAndDisburseLoan(
        uint256 requestId,
        uint256 apy
    ) external onlyOwner nonReentrant {
        // Validate and approve
        _validateAndApprove(requestId, apy);
        
        // Disburse and record
        _disburseAndRecord(requestId);
    }
    
    /**
     * @notice Internal: Validate and approve loan request
     */
    function _validateAndApprove(uint256 requestId, uint256 apy) internal {
        BorrowRequest storage request = requests[requestId];
        require(request.status == RequestStatus.PENDING, "Request not pending");
        require(interestRateModel.validateAPYRange(apy), "APY out of bounds");

        // Check maturity matching
        uint256 dueDate = block.timestamp + (request.termDays * SECONDS_PER_DAY);
        require(
            lendingPool.getAvailableCapital() >= lendingPool.getUpcomingWithdrawals(dueDate),
            "Insufficient capital for upcoming withdrawals"
        );

        // Approve request
        request.lockedAPY = apy;
        request.status = RequestStatus.APPROVED;
        
        uint256 docTokenId = loanDocNFT.getTokenIdByRequestId(requestId);
        loanDocNFT.recordApproval(docTokenId, request.amount, apy);
        
        emit BorrowRequestApproved(requestId, apy);
    }
    
    /**
     * @notice Internal: Disburse loan and record in processors
     */
    function _disburseAndRecord(uint256 requestId) internal {
        BorrowRequest storage request = requests[requestId];
        
        // Calculate terms
        uint256 interest = (request.amount * request.lockedAPY * request.termDays) / 
                          (PERCENT_100 * DAYS_PER_YEAR);
        uint256 netAmount = request.amount - interest;
        uint256 dueDate = block.timestamp + (request.termDays * SECONDS_PER_DAY);

        // Record and disburse
        lendingPool.recordBorrow(request.borrower, request.amount, request.termDays, request.lockedAPY);
        lendingPool.disburseLoan(request.borrower, netAmount);

        // Update status
        request.status = RequestStatus.DISBURSED;
        delete borrowerActiveRequest[request.borrower];
        
        uint256 docTokenId = loanDocNFT.getTokenIdByRequestId(requestId);
        loanDocNFT.recordDisbursement(docTokenId);

        // Auto-record in processors
        _recordInProcessors(request.borrower, request.amount, interest, dueDate, requestId);

        emit BorrowDisbursed(requestId, request.borrower, netAmount, interest);
    }
    
    /**
     * @notice Internal: Record loan in RepaymentProcessor and DefaultManager
     */
    function _recordInProcessors(
        address borrower,
        uint256 principal,
        uint256 interest,
        uint256 dueDate,
        uint256 reqId
    ) internal {
        if (repaymentProcessor != address(0)) {
            (bool success, ) = repaymentProcessor.call(
                abi.encodeWithSignature(
                    "recordLoan(address,uint256,uint256,uint256,uint256)",
                    borrower,
                    principal,
                    (interest * 90) / 100,
                    dueDate,
                    reqId
                )
            );
            require(success, "Failed to record in RepaymentProcessor");
        }
        
        if (defaultManager != address(0)) {
            (bool success, ) = defaultManager.call(
                abi.encodeWithSignature(
                    "recordLoanDueDate(address,uint256,uint256)",
                    borrower,
                    dueDate,
                    reqId
                )
            );
            require(success, "Failed to record in DefaultManager");
        }
    }

    /**
     * @notice Admin denies borrow request
     * @param requestId ID of the request
     * @param reason Reason for denial
     */
    function denyBorrowRequest(
        uint256 requestId,
        string memory reason
    ) external override onlyOwner {
        BorrowRequest storage request = requests[requestId];
        require(request.status == RequestStatus.PENDING, "Request not pending");

        request.status = RequestStatus.DENIED;
        delete borrowerActiveRequest[request.borrower];

        emit BorrowRequestDenied(requestId, reason);
    }

    /**
     * @notice Borrower cancels pending request
     * @param requestId ID of the request
     */
    function cancelRequest(uint256 requestId) external override {
        BorrowRequest storage request = requests[requestId];
        require(request.borrower == msg.sender, "Not request owner");
        require(request.status == RequestStatus.PENDING, "Cannot cancel");

        request.status = RequestStatus.CANCELLED;
        delete borrowerActiveRequest[msg.sender];

        emit RequestCancelled(requestId);
    }

    // View functions

    function getRequest(
        uint256 requestId
    ) external view override returns (BorrowRequest memory) {
        return requests[requestId];
    }

    function getBorrowerActiveRequest(
        address borrower
    ) external view override returns (uint256) {
        return borrowerActiveRequest[borrower];
    }
}
