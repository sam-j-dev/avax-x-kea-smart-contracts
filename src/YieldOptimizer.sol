// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IYieldOptimizer.sol";
import "./interfaces/ILendingPool.sol";

/**
 * @title YieldOptimizer
 * @notice Manages idle capital deployment to Aave V3 for yield generation
 * @dev Isolated external protocol risk, can be upgraded for different strategies
 */
contract YieldOptimizer is IYieldOptimizer, Ownable {
    ILendingPool public lendingPool;
    IERC20 public immutable USDC;
    
    // Aave V3 integration (placeholder - would need actual Aave interfaces)
    address public aavePool;
    IERC20 public aUSDC; // Aave interest-bearing token
    
    // State
    uint256 public deployedAmount;
    uint256 public reserveBufferPercent = 20; // 20% reserve buffer
    uint256 public deploymentThreshold = 60; // Deploy when utilization < 60%
    
    // Constants
    uint256 private constant PRECISION = 1e18;
    uint256 private constant PERCENT_100 = 100 * PRECISION;
    uint256 private constant MAX_DEPLOYMENT_PERCENT = 30; // Max 30% of pool to Aave
    
    constructor(
        address _usdc,
        address _lendingPool,
        address _aavePool,
        address _aUSDC
    ) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC");
        require(_lendingPool != address(0), "Invalid LendingPool");
        
        USDC = IERC20(_usdc);
        lendingPool = ILendingPool(_lendingPool);
        aavePool = _aavePool;
        aUSDC = IERC20(_aUSDC);
    }
    
    /**
     * @notice Deploy capital to Aave
     * @param amount Amount of USDC to deploy
     */
    function deployCapital(uint256 amount) external override onlyOwner {
        require(amount > 0, "Amount must be > 0");
        
        // Check deployment limit (max 30% of total pool)
        uint256 totalAssets = lendingPool.getTotalAssets();
        uint256 maxDeployable = (totalAssets * MAX_DEPLOYMENT_PERCENT * PRECISION) / PERCENT_100;
        require(deployedAmount + amount <= maxDeployable, "Exceeds deployment limit");
        
        // Transfer USDC from LendingPool
        require(USDC.transferFrom(address(lendingPool), address(this), amount), "Transfer failed");
        
        // Deploy to Aave (simplified - actual implementation would call Aave's supply())
        // In production: aavePool.supply(address(USDC), amount, address(this), 0);
        
        deployedAmount += amount;
        
        emit CapitalDeployed(amount);
    }
    
    /**
     * @notice Withdraw capital from Aave
     * @param amount Amount to withdraw
     * @return Actual amount withdrawn (including yield)
     */
    function withdrawCapital(uint256 amount) external override onlyOwner returns (uint256) {
        require(amount > 0, "Amount must be > 0");
        require(amount <= deployedAmount, "Exceeds deployed amount");
        
        // Withdraw from Aave (simplified)
        // In production: aavePool.withdraw(address(USDC), amount, address(lendingPool));
        
        uint256 yield = 0; // Would calculate actual yield from aUSDC balance
        deployedAmount -= amount;
        
        // Transfer back to LendingPool
        require(USDC.transfer(address(lendingPool), amount), "Transfer failed");
        
        emit CapitalWithdrawn(amount, yield);
        return amount;
    }
    
    /**
     * @notice Withdraw capital for borrow request
     * @param amount Amount needed for borrower
     * @return Actual amount withdrawn
     */
    function withdrawForBorrow(uint256 amount) external override onlyOwner returns (uint256) {
        if (amount > deployedAmount) {
            amount = deployedAmount;
        }
        
        if (amount == 0) return 0;
        
        return this.withdrawCapital(amount);
    }
    
    /**
     * @notice Rebalance based on pool utilization
     * @dev Called periodically or after significant pool changes
     */
    function rebalance() external override onlyOwner {
        uint256 totalAssets = lendingPool.getTotalAssets();
        uint256 totalBorrowed = lendingPool.getTotalBorrowed();
        
        if (totalAssets == 0) return;
        
        uint256 utilization = (totalBorrowed * PERCENT_100) / totalAssets;
        uint256 availableCash = lendingPool.getAvailableCash();
        uint256 reserveBuffer = (totalAssets * reserveBufferPercent * PRECISION) / PERCENT_100;
        
        // If utilization low and excess cash, deploy more
        if (utilization < deploymentThreshold * PRECISION && availableCash > reserveBuffer) {
            uint256 deployable = availableCash - reserveBuffer;
            uint256 maxDeployable = (totalAssets * MAX_DEPLOYMENT_PERCENT * PRECISION) / PERCENT_100;
            
            if (deployedAmount < maxDeployable) {
                uint256 toDeploy = maxDeployable - deployedAmount;
                if (toDeploy > deployable) {
                    toDeploy = deployable;
                }
                
                if (toDeploy > 0) {
                    this.deployCapital(toDeploy);
                }
            }
        }
        
        // If need liquidity, withdraw from Aave
        if (availableCash < reserveBuffer && deployedAmount > 0) {
            uint256 needed = reserveBuffer - availableCash;
            if (needed > deployedAmount) {
                needed = deployedAmount;
            }
            this.withdrawCapital(needed);
        }
    }
    
    /**
     * @notice Emergency withdrawal (if Aave shows vulnerability)
     * @return Amount withdrawn
     */
    function emergencyWithdraw() external override onlyOwner returns (uint256) {
        uint256 amount = deployedAmount;
        if (amount == 0) return 0;
        
        // Withdraw all from Aave
        deployedAmount = 0;
        
        // Transfer to LendingPool
        require(USDC.transfer(address(lendingPool), amount), "Transfer failed");
        
        emit EmergencyWithdrawal(amount);
        return amount;
    }
    
    /**
     * @notice Set deployment threshold
     * @param percent New threshold percentage
     */
    function setDeploymentThreshold(uint256 percent) external override onlyOwner {
        require(percent <= 100, "Invalid percent");
        deploymentThreshold = percent;
        emit ThresholdUpdated(percent);
    }
    
    // View functions
    
    function getDeployedAmount() external view override returns (uint256) {
        return deployedAmount;
    }
    
    function getAccruedYield() external view override returns (uint256) {
        // Would calculate from aUSDC balance minus deployed amount
        return 0;
    }
    
    function getCurrentAPY() external view override returns (uint256) {
        // Would query Aave's current supply APY
        // Placeholder: ~4.5% APY
        return 45 * PRECISION / 10; // 4.5%
    }
}

