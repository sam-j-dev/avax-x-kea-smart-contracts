// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IYieldOptimizer
 * @notice Interface for idle capital deployment to Aave V3
 */
interface IYieldOptimizer {
    // Events
    event CapitalDeployed(uint256 amount);
    event CapitalWithdrawn(uint256 amount, uint256 yield);
    event EmergencyWithdrawal(uint256 amount);
    event ThresholdUpdated(uint256 newThreshold);
    
    // Core functions
    function deployCapital(uint256 amount) external;
    function withdrawCapital(uint256 amount) external returns (uint256);
    function withdrawForBorrow(uint256 amount) external returns (uint256);
    function rebalance() external;
    function emergencyWithdraw() external returns (uint256);
    
    // View functions
    function getDeployedAmount() external view returns (uint256);
    function getAccruedYield() external view returns (uint256);
    function getCurrentAPY() external view returns (uint256);
    
    // Admin functions
    function setDeploymentThreshold(uint256 percent) external;
}

