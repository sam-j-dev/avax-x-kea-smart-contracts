// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IInterestRateModel
 * @notice Interface for interest rate calculations and admin-set rates
 */
interface IInterestRateModel {
    // Events
    event APYSet(uint256 indexed requestId, uint256 apy);
    event ParametersUpdated(uint256 baseRate, uint256 slope1, uint256 slope2, uint256 kinkPoint);
    event BoundsUpdated(uint256 minAPY, uint256 maxAPY);
    
    // View functions
    function getSuggestedAPY(uint256 utilization) external view returns (uint256);
    function validateAPYRange(uint256 apy) external view returns (bool);
    function getMinAPY() external view returns (uint256);
    function getMaxAPY() external view returns (uint256);
    function getKinkPoint() external view returns (uint256);
    function getBaseRate() external view returns (uint256);
    function getMaxUtilizationCap(uint256 upcomingWithdrawals, uint256 totalAssets) external view returns (uint256);
    
    // Admin functions
    function updateParameters(
        uint256 newBase,
        uint256 newSlope1,
        uint256 newSlope2,
        uint256 newKink,
        uint256 newMin,
        uint256 newMax
    ) external;
}

