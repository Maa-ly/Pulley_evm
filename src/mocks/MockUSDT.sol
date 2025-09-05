//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDT is ERC20, Ownable {
    uint8 private _decimals;
    
    constructor() ERC20("Mock USDT", "mUSDT") Ownable(msg.sender) {
        _decimals = 6; // USDT has 6 decimals
        _mint(msg.sender, 1000000 * 10**_decimals); // Mint 1M USDT
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    function faucet() external {
        _mint(msg.sender, 1000 * 10**_decimals); // Anyone can get 1000 USDT
    }
}


