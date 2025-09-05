//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {PermissionManager} from "../src/PermissionManager.sol";
import {PulleyToken} from "../src/Token/PulleyToken.sol";

import {PulTradingPool} from "../src/Pool/PuLTradingPool.sol";
import {PulleyController} from "../src/PulleyController.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {MockSToken} from "../src/mocks/MockSToken.sol";
import {MockBlocklockSender} from "../test/mocks/MockBlocklockSender.sol";

/**
 * @title DeployPulley
 * @notice Comprehensive deployment script for Pulley Protocol
 */
contract DeployPulley is Script {
    
    // Core contracts
    PermissionManager public permissionManager;
    PulleyToken public pulleyToken;

    PulTradingPool public tradingPool;
    PulleyController public controller;
    MockBlocklockSender public blocklockSender;
    
    // Mock tokens for testing
    MockUSDC public usdc;
    MockUSDT public usdt;
    MockSToken public sToken;
    
    // Configuration
    uint256 public constant THRESHOLD = 10000 * 1e18; // $10,000 USD
    address public constant AI_TRADER = 0x1234567890123456789012345678901234567890; // Replace with actual
    
    // Chainlink price feeds (replace with actual addresses for your network)
    address public constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6; // Example
    address public constant USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D; // Example  
    address public constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;  // Example
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying Pulley Protocol...");
        console.log("Deployer:", deployer);
        console.log("Network:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy core infrastructure
        _deployInfrastructure();
        
        // Step 2: Deploy mock assets (testnet only)
        if (block.chainid == 31337 || block.chainid == 11155111) { // Local or Sepolia
            _deployMockAssets();
        }
        
        // Step 3: Deploy core protocol contracts
        _deployProtocolContracts();
        
        // Step 4: Configure contract relationships
        _configureContracts();
        
        // Step 5: Set up permissions
        _setupPermissions();
        
        // Step 6: Configure assets and price feeds
        _configureAssets();
        
        // Step 7: Initial setup
        _initialSetup();
        
        vm.stopBroadcast();
        
        // Step 8: Verify deployment
        _verifyDeployment();
        
        console.log("=== DEPLOYMENT COMPLETE ===");
    }
    
    function _deployInfrastructure() internal {
        console.log("1. Deploying infrastructure...");
        
        // Deploy PermissionManager
        permissionManager = new PermissionManager();
        console.log("PermissionManager:", address(permissionManager));
        
        // Deploy MockBlocklockSender for testing
        if (block.chainid == 31337 || block.chainid == 11155111) {
            blocklockSender = new MockBlocklockSender();
            console.log("MockBlocklockSender:", address(blocklockSender));
        }
    }
    
    function _deployMockAssets() internal {
        console.log("2. Deploying mock assets...");
        
        // Deploy mock tokens
        usdc = new MockUSDC();
        usdt = new MockUSDT();
        sToken = new MockSToken();
        
        console.log("USDC:", address(usdc));
        console.log("USDT:", address(usdt));
        console.log("sToken:", address(sToken));
        
        // Mint initial supply to deployer for testing
        usdc.mint(msg.sender, 1000000 * 1e6); // 1M USDC
        usdt.mint(msg.sender, 1000000 * 1e6); // 1M USDT
        sToken.mint(msg.sender, 1000 * 1e18); // 1000 sToken
    }
    
    function _deployProtocolContracts() internal {
        console.log("3. Deploying protocol contracts...");
        
        // Prepare supported assets array
        address[] memory supportedAssets = new address[](3);
        if (block.chainid == 31337 || block.chainid == 11155111) {
            supportedAssets[0] = address(usdc);
            supportedAssets[1] = address(usdt);
            supportedAssets[2] = address(sToken);
        } else {
            // Mainnet addresses - replace with actual
            supportedAssets[0] = 0xa0b86A33e6411c4d7C0A0F6a1b5b1c0D1E2F3456; // USDC
            supportedAssets[1] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
            supportedAssets[2] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        }
        
        // Deploy PulleyToken
        pulleyToken = new PulleyToken(
            "Pulley Token",
            "PLLY",
            address(permissionManager),
            supportedAssets
        );
        console.log("PulleyToken:", address(pulleyToken));
        

        
        // Deploy TradingPool
        tradingPool = new PulTradingPool();
        tradingPool.initialize(
            "Pulley Pool Token",
            "PPT",
            address(permissionManager),
            address(0), // Controller set later
            address(0)  // PulleyToken set later
        );
        console.log("TradingPool:", address(tradingPool));
        
        // Deploy Controller
        address blocklockAddress = block.chainid == 31337 || block.chainid == 11155111
            ? address(blocklockSender) 
            : 0x0000000000000000000000000000000000000000; // Replace with actual Blocklock address
            
        controller = new PulleyController();
        controller.initialize(
            address(permissionManager),
            address(tradingPool),
            address(0), // No separate insurance pool
            address(pulleyToken),
            address(0), // AI trader
            supportedAssets
        );
        console.log("Controller:", address(controller));
    }
    
    function _configureContracts() internal {
        console.log("4. Configuring contract relationships...");
        
        // Set contract relationships
        pulleyToken.setContracts(
            address(0), 
            address(controller), 
            address(tradingPool)
        );
        
        tradingPool.updateController(address(controller));
        tradingPool.updatePulleyToken(address(pulleyToken));
        
        controller.setAITrader(AI_TRADER);
    }
    
    function _setupPermissions() internal {
        console.log("5. Setting up permissions...");
        
        // Grant admin permissions to deployer
        permissionManager.grantPermission(msg.sender, PulleyToken.setContracts.selector);
        permissionManager.grantPermission(msg.sender, PulTradingPool.updateController.selector);
        permissionManager.grantPermission(msg.sender, PulTradingPool.updatePulleyToken.selector);
        permissionManager.grantPermission(msg.sender, PulTradingPool.addAsset.selector);
        permissionManager.grantPermission(msg.sender, PulTradingPool.setPriceFeed.selector);
        permissionManager.grantPermission(msg.sender, PulTradingPool.updateThreshold.selector);
        permissionManager.grantPermission(msg.sender, PulleyController.setAITrader.selector);
        
        // Grant operational permissions
        permissionManager.grantPermission(address(controller), PulTradingPool.recordProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordLoss.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.distributePeriodProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordPeriodLoss.selector);
        
        permissionManager.grantPermission(address(tradingPool), PulleyController.receiveFunds.selector);
        permissionManager.grantPermission(AI_TRADER, PulleyController.checkAIWalletPnL.selector);
        
        // Grant Blocklock permissions for automation
        if (address(blocklockSender) != address(0)) {
            // Note: _handleBlocklockCallback is internal, so no external permission needed
            // The AbstractBlocklockReceiver handles the external callback routing
        }
        
        console.log("Permissions configured");
    }
    
    function _configureAssets() internal {
        console.log("6. Configuring assets and price feeds...");
        
        if (block.chainid == 31337 || block.chainid == 11155111) {
            // Add mock assets
            tradingPool.addAsset(address(usdc), 6, 1000e6, address(0));
            tradingPool.addAsset(address(usdt), 6, 1000e6, address(0));
            tradingPool.addAsset(address(sToken), 18, 1e18, address(0));
            
            // For testing, we can skip price feeds or use mock ones
            console.log("Mock assets configured");
        } else {
            // Mainnet configuration
            tradingPool.addAsset(0xa0b86A33e6411c4d7C0A0F6a1b5b1c0D1E2F3456, 6, 1000e6, address(0)); // USDC
            tradingPool.addAsset(0xdAC17F958D2ee523a2206206994597C13D831ec7, 6, 1000e6, address(0)); // USDT
            tradingPool.addAsset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 18, 1e18, address(0)); // WETH
            
            // Set Chainlink price feeds
            tradingPool.setPriceFeed(0xa0b86A33e6411c4d7C0A0F6a1b5b1c0D1E2F3456, USDC_USD_FEED);
            tradingPool.setPriceFeed(0xdAC17F958D2ee523a2206206994597C13D831ec7, USDT_USD_FEED);
            tradingPool.setPriceFeed(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, ETH_USD_FEED);
            
            console.log("Mainnet assets and price feeds configured");
        }
    }
    
    function _initialSetup() internal {
        console.log("7. Initial setup...");
        
        // Set threshold
        tradingPool.updateThreshold(THRESHOLD);
        console.log("Threshold set to:", THRESHOLD);
        
        // Trading periods now start automatically when thresholds are reached
        console.log("Trading periods will start automatically when thresholds are reached");
        
        // Fund controller for automation (if needed)
        if (address(controller).balance == 0) {
            controller.fundAutomation{value: 0.1 ether}();
            console.log("Controller funded for automation");
        }
    }
    
    function _verifyDeployment() internal view {
        console.log("8. Verifying deployment...");
        
        // Verify contract addresses are set correctly
        require(address(permissionManager) != address(0), "PermissionManager not deployed");
        require(address(pulleyToken) != address(0), "PulleyToken not deployed");

        require(address(tradingPool) != address(0), "TradingPool not deployed");
        require(address(controller) != address(0), "Controller not deployed");
        
        // Verify relationships
        require(pulleyToken.controller() == address(controller), "PulleyToken controller not set");
        require(tradingPool.controller() == address(controller), "TradingPool controller not set");
        require(tradingPool.pulleyToken() == address(pulleyToken), "TradingPool pulleyToken not set");
        
        // Verify threshold
        require(tradingPool.threshold() == THRESHOLD, "Threshold not set correctly");
        
        console.log("Deployment verified successfully");
    }
    
    // Helper function to get deployment addresses
    function getDeploymentAddresses() external view returns (
        address _permissionManager,
        address _pulleyToken,
        address _pulleyTokenEngine,
        address _tradingPool,
        address _controller,
        address _usdc,
        address _usdt,
        address _weth
    ) {
        return (
            address(permissionManager),
            address(pulleyToken),
            address(0),
            address(tradingPool),
            address(controller),
            address(usdc),
            address(usdt),
            address(sToken)
        );
    }
}
