// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ICreditManager
 * @notice Interface for managing borrower profiles and credit limits
 */
interface ICreditManager {
    enum BorrowerStatus { INACTIVE, ACTIVE, DEFAULTED }
    
    struct BorrowerProfile {
        uint256 creditLimit;
        uint256 currentBorrowed;
        bytes32 dueDiligenceHash;
        BorrowerStatus status;
        uint256 onboardDate;
    }
    
    // Events
    event BorrowerAdded(address indexed borrower, uint256 creditLimit, bytes32 docsHash);
    event CreditIncreaseRequested(address indexed borrower, uint256 additionalCredit, bytes32 newDocsHash);
    event CreditIncreaseApproved(address indexed borrower, uint256 newCreditLimit);
    event BorrowerDeactivated(address indexed borrower, string reason);
    event DocsHashUpdated(address indexed borrower, bytes32 newHash);
    
    // Admin functions
    function addBorrower(address borrowerAddress, uint256 creditLimit, bytes32 docsHash) external;
    function approveCreditIncrease(address borrower, uint256 newCreditLimit) external;
    function deactivateBorrower(address borrower, string memory reason) external;
    function updateDocsHash(address borrower, bytes32 newHash) external;
    
    // Borrower functions
    function requestCreditIncrease(uint256 additionalCredit, bytes32 newDocsHash) external;
    
    // Protocol functions
    function updateBorrowedAmount(address borrower, uint256 newAmount) external;
    function markBorrowerDefaulted(address borrower) external;
    
    // View functions
    function getBorrowerProfile(address borrower) external view returns (BorrowerProfile memory);
    function getRemainingCredit(address borrower) external view returns (uint256);
    function isBorrowerActive(address borrower) external view returns (bool);
}

