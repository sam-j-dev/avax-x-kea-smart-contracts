// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ILoanDocumentationNFT.sol";

/**
 * @title LoanDocumentationNFT
 * @notice Non-transferable NFT registry for loan documentation and transparency
 * @dev Each loan request gets an NFT minted, held by owner/admin for audit trail
 *
 * Key Features:
 * - Non-transferable (Soulbound-like) - only owner/admin can hold
 * - Public documentation for transparency
 * - Tracks loan lifecycle from request to repayment/default
 * - IPFS hashes for off-chain documents
 * - Risk assessment metadata
 */
contract LoanDocumentationNFT is ERC721, Ownable, ILoanDocumentationNFT {
    // State variables
    uint256 private _nextTokenId;

    // Token ID => Documentation
    mapping(uint256 => LoanDocumentation) private _documentations;

    // Request ID => Token ID
    mapping(uint256 => uint256) private _requestIdToTokenId;

    // Borrower => Token IDs array
    mapping(address => uint256[]) private _borrowerTokens;

    // Authorized contracts that can update NFT status
    mapping(address => bool) public authorizedContracts;

    constructor()
        ERC721("KEA Loan Documentation", "KEALOAN")
        Ownable(msg.sender)
    {
        _nextTokenId = 1; // Start from 1
    }

    // Authorization management
    function setAuthorizedContract(
        address contractAddress,
        bool authorized
    ) external onlyOwner {
        authorizedContracts[contractAddress] = authorized;
    }

    modifier onlyAuthorized() {
        require(
            msg.sender == owner() || authorizedContracts[msg.sender],
            "Not authorized"
        );
        _;
    }

    /**
     * @notice Prevent all transfers - NFTs are non-transferable
     * @dev Override to make tokens soulbound to the contract
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting (from == address(0))
        // Block all transfers (from != address(0))
        require(
            from == address(0),
            "Loan documentation NFTs are non-transferable"
        );

        return super._update(to, tokenId, auth);
    }

    /**
     * @notice Mint new loan documentation NFT
     * @dev Called by RequestManager when borrower submits loan request
     */
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
    ) external override onlyAuthorized returns (uint256) {
        require(borrower != address(0), "Invalid borrower");
        require(requestId > 0, "Invalid request ID");
        require(
            _requestIdToTokenId[requestId] == 0,
            "Documentation already exists"
        );

        uint256 tokenId = _nextTokenId++;

        // Mint to owner (admin custody)
        _mint(owner(), tokenId);

        // Create documentation
        _documentations[tokenId] = LoanDocumentation({
            tokenId: tokenId,
            borrower: borrower,
            requestId: requestId,
            businessName: businessName,
            businessType: businessType,
            requestedAmount: requestedAmount,
            approvedAmount: 0,
            approvedAPY: 0,
            termDays: termDays,
            requestTimestamp: block.timestamp,
            approvalTimestamp: 0,
            disbursementTimestamp: 0,
            repaymentTimestamp: 0,
            financialStatementsHash: financialStatementsHash,
            businessPlanHash: businessPlanHash,
            collateralProofHash: collateralProofHash,
            kybDocumentsHash: kybDocumentsHash,
            riskScore: 0,
            riskCategory: "",
            status: LoanStatus.PENDING
        });

        // Map request ID to token ID
        _requestIdToTokenId[requestId] = tokenId;

        // Track borrower's tokens
        _borrowerTokens[borrower].push(tokenId);

        emit DocumentationMinted(tokenId, borrower, requestId, businessName);

        return tokenId;
    }

    /**
     * @notice Update loan status
     * @dev Called throughout loan lifecycle
     */
    function updateStatus(
        uint256 tokenId,
        LoanStatus newStatus
    ) external override onlyAuthorized {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        LoanDocumentation storage doc = _documentations[tokenId];
        LoanStatus oldStatus = doc.status;

        doc.status = newStatus;

        emit StatusUpdated(tokenId, oldStatus, newStatus);
    }

    /**
     * @notice Record loan approval details
     * @dev Called when admin approves loan request
     */
    function recordApproval(
        uint256 tokenId,
        uint256 approvedAmount,
        uint256 approvedAPY
    ) external override onlyAuthorized {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        LoanDocumentation storage doc = _documentations[tokenId];
        require(doc.status == LoanStatus.PENDING, "Not in pending status");

        doc.approvedAmount = approvedAmount;
        doc.approvedAPY = approvedAPY;
        doc.approvalTimestamp = block.timestamp;
        doc.status = LoanStatus.APPROVED;

        emit ApprovalRecorded(tokenId, approvedAmount, approvedAPY);
        emit StatusUpdated(tokenId, LoanStatus.PENDING, LoanStatus.APPROVED);
    }

    /**
     * @notice Record loan disbursement
     * @dev Called when funds are disbursed to borrower
     */
    function recordDisbursement(
        uint256 tokenId
    ) external override onlyAuthorized {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        LoanDocumentation storage doc = _documentations[tokenId];
        require(doc.status == LoanStatus.APPROVED, "Not in approved status");

        doc.disbursementTimestamp = block.timestamp;
        doc.status = LoanStatus.DISBURSED;

        emit StatusUpdated(tokenId, LoanStatus.APPROVED, LoanStatus.DISBURSED);
    }

    /**
     * @notice Record loan repayment
     * @dev Called when borrower repays loan
     */
    function recordRepayment(uint256 tokenId) external override onlyAuthorized {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        LoanDocumentation storage doc = _documentations[tokenId];
        require(doc.status == LoanStatus.DISBURSED, "Not in disbursed status");

        doc.repaymentTimestamp = block.timestamp;
        doc.status = LoanStatus.REPAID;

        emit StatusUpdated(tokenId, LoanStatus.DISBURSED, LoanStatus.REPAID);
    }

    /**
     * @notice Update risk assessment
     * @dev Can be called by admin to update risk scoring
     */
    function updateRiskAssessment(
        uint256 tokenId,
        uint8 riskScore,
        string memory riskCategory
    ) external override onlyAuthorized {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(riskScore <= 10, "Risk score must be 0-10");

        LoanDocumentation storage doc = _documentations[tokenId];
        doc.riskScore = riskScore;
        doc.riskCategory = riskCategory;

        emit RiskAssessmentUpdated(tokenId, riskScore, riskCategory);
    }

    // View functions

    /**
     * @notice Get full documentation for a token
     */
    function getDocumentation(
        uint256 tokenId
    ) external view override returns (LoanDocumentation memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _documentations[tokenId];
    }

    /**
     * @notice Get token ID by request ID
     */
    function getTokenIdByRequestId(
        uint256 requestId
    ) external view override returns (uint256) {
        return _requestIdToTokenId[requestId];
    }

    /**
     * @notice Get all token IDs for a borrower
     */
    function getBorrowerTokens(
        address borrower
    ) external view override returns (uint256[] memory) {
        return _borrowerTokens[borrower];
    }

    /**
     * @notice Get total number of documentations minted
     */
    function totalDocumentations() external view override returns (uint256) {
        return _nextTokenId - 1;
    }

    /**
     * @notice Get token URI (can be used for metadata)
     * @dev Override to provide IPFS metadata or API endpoint
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        // TODO: Return IPFS hash or API endpoint with full metadata
        // For now, return base URI + tokenId
        return
            string(
                abi.encodePacked(
                    "https://api.kea.credit/loan/",
                    _toString(tokenId)
                )
            );
    }

    /**
     * @notice Convert uint256 to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
