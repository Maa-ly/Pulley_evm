//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDC is ERC20, Ownable {
    uint8 private _decimals;
    
    constructor() ERC20("Mock USDC", "mUSDC") Ownable(msg.sender) {
        _decimals = 6; // USDC has 6 decimals
        _mint(msg.sender, 1000000 * 10**_decimals); // Mint 1M USDC
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    function faucet() external {
        _mint(msg.sender, 1000 * 10**_decimals); // Anyone can get 1000 USDC
    }
}


