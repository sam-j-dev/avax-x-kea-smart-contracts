// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ICreditManager.sol";

/**
 * @title CreditManager
 * @notice Manages borrower profiles, credit limits, and due diligence documentation
 * @dev Handles borrower onboarding and credit management
 */
contract CreditManager is ICreditManager, Ownable {
    // Borrower profiles
    mapping(address => BorrowerProfile) public borrowers;
    
    // Credit increase requests
    struct CreditIncreaseRequest {
        uint256 additionalCredit;
        bytes32 newDocsHash;
        uint256 timestamp;
        bool processed;
    }
    mapping(address => CreditIncreaseRequest) public creditIncreaseRequests;
    
    // Authorized contracts
    address public lendingPool;
    address public defaultManager;
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Set authorized contracts
     */
    function setAuthorizedContracts(
        address _lendingPool,
        address _defaultManager
    ) external onlyOwner {
        lendingPool = _lendingPool;
        defaultManager = _defaultManager;
    }
    
    modifier onlyAuthorized() {
        require(
            msg.sender == lendingPool ||
                msg.sender == defaultManager ||
                msg.sender == owner(),
            "Not authorized"
        );
        _;
    }
    
    /**
     * @notice Add new borrower with initial credit limit
     * @dev Only admin can call
     * @param borrowerAddress Address of the borrower
     * @param creditLimit Initial credit limit
     * @param docsHash IPFS hash of due diligence documents
     */
    function addBorrower(
        address borrowerAddress,
        uint256 creditLimit,
        bytes32 docsHash
    ) external override onlyOwner {
        require(borrowerAddress != address(0), "Invalid address");
        require(creditLimit > 0, "Credit limit must be > 0");
        require(borrowers[borrowerAddress].status == BorrowerStatus.INACTIVE, "Borrower already exists");
        
        borrowers[borrowerAddress] = BorrowerProfile({
            creditLimit: creditLimit,
            currentBorrowed: 0,
            dueDiligenceHash: docsHash,
            status: BorrowerStatus.ACTIVE,
            onboardDate: block.timestamp
        });
        
        emit BorrowerAdded(borrowerAddress, creditLimit, docsHash);
    }
    
    /**
     * @notice Borrower requests credit limit increase
     * @param additionalCredit Amount of additional credit requested
     * @param newDocsHash IPFS hash of updated documentation
     */
    function requestCreditIncrease(
        uint256 additionalCredit,
        bytes32 newDocsHash
    ) external override {
        require(borrowers[msg.sender].status == BorrowerStatus.ACTIVE, "Not active borrower");
        require(additionalCredit > 0, "Additional credit must be > 0");
        require(!creditIncreaseRequests[msg.sender].processed, "Pending request exists");
        
        creditIncreaseRequests[msg.sender] = CreditIncreaseRequest({
            additionalCredit: additionalCredit,
            newDocsHash: newDocsHash,
            timestamp: block.timestamp,
            processed: false
        });
        
        emit CreditIncreaseRequested(msg.sender, additionalCredit, newDocsHash);
    }
    
    /**
     * @notice Approve credit increase request
     * @dev Only admin can call
     * @param borrower Address of the borrower
     * @param newCreditLimit New total credit limit
     */
    function approveCreditIncrease(
        address borrower,
        uint256 newCreditLimit
    ) external override onlyOwner {
        require(borrowers[borrower].status == BorrowerStatus.ACTIVE, "Not active borrower");
        require(newCreditLimit > borrowers[borrower].creditLimit, "New limit must be higher");
        require(creditIncreaseRequests[borrower].timestamp > 0, "No pending request");
        
        borrowers[borrower].creditLimit = newCreditLimit;
        borrowers[borrower].dueDiligenceHash = creditIncreaseRequests[borrower].newDocsHash;
        creditIncreaseRequests[borrower].processed = true;
        
        emit CreditIncreaseApproved(borrower, newCreditLimit);
    }
    
    /**
     * @notice Deactivate borrower
     * @dev Only admin can call
     * @param borrower Address of the borrower
     * @param reason Reason for deactivation
     */
    function deactivateBorrower(
        address borrower,
        string memory reason
    ) external override onlyOwner {
        require(borrowers[borrower].status != BorrowerStatus.INACTIVE, "Already inactive");
        require(borrowers[borrower].currentBorrowed == 0, "Outstanding loans exist");
        
        borrowers[borrower].status = BorrowerStatus.INACTIVE;
        
        emit BorrowerDeactivated(borrower, reason);
    }
    
    /**
     * @notice Update borrower's documentation hash
     * @dev Only admin can call
     * @param borrower Address of the borrower
     * @param newHash New IPFS hash
     */
    function updateDocsHash(
        address borrower,
        bytes32 newHash
    ) external override onlyOwner {
        require(borrowers[borrower].status == BorrowerStatus.ACTIVE, "Not active borrower");
        
        borrowers[borrower].dueDiligenceHash = newHash;
        
        emit DocsHashUpdated(borrower, newHash);
    }
    
    /**
     * @notice Update borrower's current borrowed amount (called by LendingPool)
     * @dev Internal function, will be called via authorized contracts
     */
    function updateBorrowedAmount(address borrower, uint256 newAmount) external onlyAuthorized {
        borrowers[borrower].currentBorrowed = newAmount;
    }
    
    /**
     * @notice Mark borrower as defaulted (called by DefaultManager)
     */
    function markBorrowerDefaulted(address borrower) external onlyAuthorized {
        require(borrowers[borrower].status == BorrowerStatus.ACTIVE, "Not active borrower");
        borrowers[borrower].status = BorrowerStatus.DEFAULTED;
    }
    
    // View functions
    
    function getBorrowerProfile(address borrower) external view override returns (BorrowerProfile memory) {
        return borrowers[borrower];
    }
    
    function getRemainingCredit(address borrower) external view override returns (uint256) {
        BorrowerProfile memory profile = borrowers[borrower];
        if (profile.currentBorrowed >= profile.creditLimit) {
            return 0;
        }
        return profile.creditLimit - profile.currentBorrowed;
    }
    
    function isBorrowerActive(address borrower) external view override returns (bool) {
        return borrowers[borrower].status == BorrowerStatus.ACTIVE;
    }
}

