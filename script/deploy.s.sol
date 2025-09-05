//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "../src/Token/PulleyToken.sol";
import "../src/PulleyController.sol";
import "../src/Pool/PuLTradingPool.sol";
import {PermissionManager} from "../src/PermissionManager.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockBlocklockSender.sol";

/**
 * @title Deploy Script for Simplified Pulley Protocol
 * @notice Deploys: TradingPool, PulleyToken (floating), PulleyTokenEngine, Controller
 */
contract DeployScript is Script {
    
    // Core contracts
    PulleyToken public pulleyToken;
    PulleyController public controller;
    PulTradingPool public tradingPool;

    PermissionManager public permissionManager;
    
    // Mock contracts (for testing)
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockERC20 public s_token;
    MockBlocklockSender public blocklockSender;
    
    // Configuration
    uint256 public constant THRESHOLD = 10000 * 1e18; // 10,000 USD threshold
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying Simplified Pulley Protocol...");
        
        // Deploy mock tokens for testing
        if (block.chainid == 31337) {
            _deployMockTokens();
        }
        
        // Deploy core contracts
        _deployCoreContracts();
        
        // Configure contracts
        _configureContracts();

        vm.stopBroadcast();
        
        // Log deployment
        _logDeployment();
    }
    
    function _deployMockTokens() internal {
        console.log("Deploying mock tokens...");
        
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);
        blocklockSender = new MockBlocklockSender();
        
        console.log("USDC:", address(usdc));
        console.log("USDT:", address(usdt));
        console.log("MockBlocklockSender:", address(blocklockSender));
    }
    
    function _deployCoreContracts() internal {
        console.log("Deploying core contracts...");
        
        // Deploy permission manager
        permissionManager = new PermissionManager();
        console.log("PermissionManager:", address(permissionManager));
        
        // Setup supported assets for PulleyToken
        address[] memory supportedAssets = new address[](2);
        if (block.chainid == 31337) {
            supportedAssets[0] = address(usdc);
            supportedAssets[1] = address(usdt);
        } else {
            // Use real addresses for mainnet/testnet
            supportedAssets[0] = 0xA0b86A33E6411c0C6E3a3f8D9C5e0D3e8b5A5e7F; // USDC
            supportedAssets[1] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        }
        
        // Deploy PulleyToken (floating stablecoin)
        pulleyToken = new PulleyToken(
            "Pulley Token",
            "PULL",
            address(permissionManager),
            supportedAssets
        );
        console.log("PulleyToken (Floating):", address(pulleyToken));
        

        
        // Deploy TradingPool (empty constructor)
        tradingPool = new PulTradingPool();
        console.log("TradingPool:", address(tradingPool));
        
        // Deploy Controller (empty constructor)
        controller = new PulleyController();
        console.log("Controller:", address(controller));
    }
    
    function _configureContracts() internal {
        console.log("Configuring contracts...");
        
        // Setup supported assets for initialization
        address[] memory supportedAssets = new address[](2);
        if (block.chainid == 31337) {
            supportedAssets[0] = address(usdc);
            supportedAssets[1] = address(usdt);
        } else {
            // Use real addresses for mainnet/testnet
            supportedAssets[0] = 0xA0b86A33E6411c0C6E3a3f8D9C5e0D3e8b5A5e7F; // USDC
            supportedAssets[1] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        }
        
        // Initialize TradingPool
        tradingPool.initialize(
            "Pulley Pool Token",
            "PPT",
            address(permissionManager),
            address(controller),
            address(pulleyToken)
        );
        
        // Initialize Controller
        controller.initialize(
            address(permissionManager),
            address(tradingPool),
            address(0), // No separate insurance pool
            address(pulleyToken),
            address(0), // AI Trader set later
            supportedAssets
        );
        
        // Set contract relationships
        pulleyToken.setContracts(address(0), address(controller), address(tradingPool));
        
        // Add assets to trading pool with proper parameters
        // For testing, we'll use mock price feeds (address(0) for now)
        if (block.chainid == 31337) {
            tradingPool.addAsset(address(usdc), 6, 1000 * 1e6, address(0)); // USDC with 1000 USDC threshold
            tradingPool.addAsset(address(usdt), 6, 1000 * 1e6, address(0)); // USDT with 1000 USDT threshold
        } else {
            // Use real price feed addresses for mainnet
            tradingPool.addAsset(0xA0b86A33E6411c0C6E3a3f8D9C5e0D3e8b5A5e7F, 6, 1000 * 1e6, 0x8A753747A1Fa494EC906cE90E9f37563A8AF630e); // USDC
            tradingPool.addAsset(0xdAC17F958D2ee523a2206206994597C13D831ec7, 6, 1000 * 1e6, 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D); // USDT
        }
        
        // Set threshold
        tradingPool.updateThreshold(THRESHOLD);
        
        console.log("Configuration complete");
    }
    
    function _logDeployment() internal view {
        console.log("\n=== SIMPLIFIED PULLEY PROTOCOL DEPLOYMENT ===");
        console.log("PermissionManager:", address(permissionManager));
        console.log("PulleyToken (Floating):", address(pulleyToken));

        console.log("TradingPool:", address(tradingPool));
        console.log("Controller:", address(controller));
        
        if (block.chainid == 31337) {
            console.log("\n=== MOCK CONTRACTS ===");
            console.log("USDC:", address(usdc));
            console.log("USDT:", address(usdt));
            console.log("MockBlocklockSender:", address(blocklockSender));
        }
        
        console.log("\n=== CONFIGURATION ===");
        console.log("Threshold:", THRESHOLD);
        console.log("Insurance Allocation: 15%");
        console.log("Trading Allocation: 85%");
        console.log("Profit Split - Insurance: 10%, Trading: 90%");
        console.log("Pulley Token: FLOATING (grows with utilization)");
        
        console.log("\n=== ARCHITECTURE ===");
        console.log("1. TradingPool - Users deposit, get pool tokens");
        console.log("2. PulleyToken - Floating stablecoin (anyone can mint)");
        console.log("3. PulleyTokenEngine - Manages floating stablecoin");
        console.log("4. Controller - 15%/85% split, AI trading integration");
        
        console.log("\n=== NEXT STEPS ===");
        console.log("1. Set up AI trader integration");
        console.log("2. Configure price oracles for trading pool");
        console.log("3. Fund Controller with ETH for Blocklock automation");
        console.log("4. Test with small deposits first");
        console.log("5. Verify Pulley token floating mechanism");
    }
}