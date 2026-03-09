// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IInterestRateModel.sol";

/**
 * @title InterestRateModel
 * @notice Provides utilization-based rate guidance; admin sets and locks final APY at request approval time
 * @dev Admin-controlled rate setting for SME lending with utilization-based guidance
 */
contract InterestRateModel is IInterestRateModel, Ownable {
    // Rate parameters (for guidance calculation)
    uint256 public baseRate; // Base rate (e.g., 2%)
    uint256 public slope1; // Rate increase per % utilization below kink (e.g., 10%)
    uint256 public slope2; // Rate increase per % utilization above kink (e.g., 50%)
    uint256 public kinkPoint; // Utilization threshold (e.g., 80%)

    // Rate bounds
    uint256 public minAPY; // Minimum allowed APY (e.g., 4%)
    uint256 public maxAPY; // Maximum allowed APY (e.g., 25%)

    // Constants for precision - Using 6 decimals for consistency with USDC and LP tokens
    uint256 private constant PRECISION = 1e6;
    uint256 private constant PERCENT_100 = 100 * PRECISION;

    constructor(
        uint256 _baseRate,
        uint256 _slope1,
        uint256 _slope2,
        uint256 _kinkPoint,
        uint256 _minAPY,
        uint256 _maxAPY
    ) Ownable(msg.sender) {
        require(_kinkPoint <= PERCENT_100, "Kink point must be <= 100%");
        require(_minAPY < _maxAPY, "Min APY must be < Max APY");

        baseRate = _baseRate;
        slope1 = _slope1;
        slope2 = _slope2;
        kinkPoint = _kinkPoint;
        minAPY = _minAPY;
        maxAPY = _maxAPY;
    }

    /**
     * @notice Get suggested APY based on utilization (guidance only)
     * @param utilization Current utilization ratio (0-100%, scaled by PRECISION)
     * @return Suggested APY (scaled by PRECISION)
     */
    function getSuggestedAPY(
        uint256 utilization
    ) external view override returns (uint256) {
        if (utilization < kinkPoint) {
            // Below kink: Base Rate + (Slope1 × Utilization)
            return baseRate + ((slope1 * utilization) / PERCENT_100);
        } else {
            // Above kink: Kink Rate + (Slope2 × (Utilization - Kink))
            uint256 kinkRate = baseRate + ((slope1 * kinkPoint) / PERCENT_100);
            uint256 excessUtilization = utilization - kinkPoint;
            return kinkRate + ((slope2 * excessUtilization) / PERCENT_100);
        }
    }

    /**
     * @notice Validate if APY is within allowed bounds
     * @param apy The APY to validate
     * @return True if APY is within bounds
     */
    function validateAPYRange(
        uint256 apy
    ) external view override returns (bool) {
        return apy >= minAPY && apy <= maxAPY;
    }

    /**
     * @notice Get maximum utilization cap based on upcoming withdrawals
     * @param upcomingWithdrawals Sum of lender locks expiring in next 30 days
     * @param totalAssets Total pool assets
     * @return Maximum utilization percentage (scaled by PRECISION)
     */
    function getMaxUtilizationCap(
        uint256 upcomingWithdrawals,
        uint256 totalAssets
    ) external pure override returns (uint256) {
        if (totalAssets == 0) return 80 * PRECISION; // Default 80%

        uint256 withdrawalRatio = (upcomingWithdrawals * PERCENT_100) /
            totalAssets;

        // High withdrawal obligations (>15%): Conservative 60% cap
        if (withdrawalRatio > 15 * PRECISION) {
            return 60 * PRECISION;
        }
        // Low withdrawal obligations (<5%): Aggressive 90% cap
        else if (withdrawalRatio < 5 * PRECISION) {
            return 90 * PRECISION;
        }
        // Normal conditions: Standard 80% cap
        else {
            return 80 * PRECISION;
        }
    }

    /**
     * @notice Update rate model parameters
     * @dev Only owner can call
     */
    function updateParameters(
        uint256 newBase,
        uint256 newSlope1,
        uint256 newSlope2,
        uint256 newKink,
        uint256 newMin,
        uint256 newMax
    ) external override onlyOwner {
        require(newKink <= PERCENT_100, "Kink point must be <= 100%");
        require(newMin < newMax, "Min APY must be < Max APY");

        baseRate = newBase;
        slope1 = newSlope1;
        slope2 = newSlope2;
        kinkPoint = newKink;
        minAPY = newMin;
        maxAPY = newMax;

        emit ParametersUpdated(newBase, newSlope1, newSlope2, newKink);
        emit BoundsUpdated(newMin, newMax);
    }

    // View functions
    function getMinAPY() external view override returns (uint256) {
        return minAPY;
    }

    function getMaxAPY() external view override returns (uint256) {
        return maxAPY;
    }

    function getKinkPoint() external view override returns (uint256) {
        return kinkPoint;
    }

    function getBaseRate() external view override returns (uint256) {
        return baseRate;
    }
}
