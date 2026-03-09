// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUSDC
 * @notice Mock USDC token for testnet deployment
 * @dev Only for testing purposes - DO NOT use in production
 */
contract MockUSDC is ERC20, Ownable {
    uint8 private _decimals = 6;
    
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Mint tokens (testnet only)
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    /**
     * @notice Faucet function - anyone can mint small amounts for testing
     * @dev Limited to 1000 USDC per call
     */
    function faucet() external {
        uint256 faucetAmount = 1000 * 10**_decimals; // 1000 USDC
        _mint(msg.sender, faucetAmount);
    }
}

