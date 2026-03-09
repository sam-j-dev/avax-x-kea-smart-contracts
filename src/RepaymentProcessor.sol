// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILoanDocumentationNFT.sol";

/**
 * @title RepaymentProcessor
 * @notice Handles loan repayments and interest recognition
 * @dev Interest and fees are withheld at disbursement, recognized at repayment
 */
contract RepaymentProcessor is Ownable, ReentrancyGuard {
    ILendingPool public lendingPool;
    ILoanDocumentationNFT public loanDocNFT;
    IERC20 public immutable USDC;
    
    // Authorized contracts
    address public requestManager;

    // Loan tracking (synced with LendingPool)
    struct LoanDetails {
        uint256 principal;
        uint256 withheldInterest;
        uint256 dueDate;
        uint256 requestId; // Link to request/NFT
        bool active;
    }
    mapping(address => LoanDetails) public loans;

    event RepaymentSubmitted(
        address indexed borrower,
        uint256 principal,
        uint256 interest
    );
    event EarlyRepayment(address indexed borrower, uint256 daysEarly);

    constructor(
        address _usdc,
        address _lendingPool,
        address _loanDocNFT
    ) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC");
        require(_lendingPool != address(0), "Invalid LendingPool");
        require(_loanDocNFT != address(0), "Invalid LoanDocNFT");

        USDC = IERC20(_usdc);
        lendingPool = ILendingPool(_lendingPool);
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
     * @notice Record loan details (called by RequestManager after disbursement)
     * @dev This syncs loan data with RepaymentProcessor
     */
    function recordLoan(
        address borrower,
        uint256 principal,
        uint256 withheldInterest,
        uint256 dueDate,
        uint256 requestId
    ) external onlyAuthorized {
        loans[borrower] = LoanDetails({
            principal: principal,
            withheldInterest: withheldInterest,
            dueDate: dueDate,
            requestId: requestId,
            active: true
        });
    }

    /**
     * @notice Submit repayment (borrower repays principal only)
     * @dev Interest and fees were withheld at disbursement
     */
    function submitRepayment() external nonReentrant {
        LoanDetails storage loan = loans[msg.sender];
        require(loan.active, "No active loan");

        uint256 principalAmount = loan.principal;
        uint256 interestAmount = loan.withheldInterest;

        // Transfer principal from borrower
        require(
            USDC.transferFrom(
                msg.sender,
                address(lendingPool),
                principalAmount
            ),
            "Transfer failed"
        );

        // Record repayment in LendingPool
        lendingPool.recordRepayment(
            msg.sender,
            principalAmount,
            interestAmount
        );

        // Update documentation NFT - record repayment
        uint256 docTokenId = loanDocNFT.getTokenIdByRequestId(loan.requestId);
        loanDocNFT.recordRepayment(docTokenId);

        // Check if early repayment
        if (block.timestamp < loan.dueDate) {
            uint256 daysEarly = (loan.dueDate - block.timestamp) / 86400;
            emit EarlyRepayment(msg.sender, daysEarly);
        }

        // Clear loan
        delete loans[msg.sender];

        emit RepaymentSubmitted(msg.sender, principalAmount, interestAmount);
    }

    /**
     * @notice Validate repayment amount
     * @param borrower Address of borrower
     * @param submittedAmount Amount being submitted
     * @return True if amount is correct
     */
    function validateRepaymentAmount(
        address borrower,
        uint256 submittedAmount
    ) external view returns (bool) {
        LoanDetails memory loan = loans[borrower];
        return submittedAmount == loan.principal;
    }

    /**
     * @notice Get loan details
     * @param borrower Address of borrower
     * @return principal Principal amount
     * @return withheldInterest Interest withheld
     * @return dueDate Loan due date
     * @return active Loan status
     */
    function getLoanDetails(
        address borrower
    )
        external
        view
        returns (
            uint256 principal,
            uint256 withheldInterest,
            uint256 dueDate,
            bool active
        )
    {
        LoanDetails memory loan = loans[borrower];
        return (
            loan.principal,
            loan.withheldInterest,
            loan.dueDate,
            loan.active
        );
    }

    /**
     * @notice Check if loan is overdue
     * @param borrower Address of borrower
     * @return True if loan is past due date
     */
    function isOverdue(address borrower) external view returns (bool) {
        LoanDetails memory loan = loans[borrower];
        return loan.active && block.timestamp > loan.dueDate;
    }
}
