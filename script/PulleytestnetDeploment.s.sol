//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "../src/Token/PulleyToken.sol";
import "../src/PulleyController.sol";
import "../src/Pool/PuLTradingPool.sol";
import {PermissionManager} from "../src/PermissionManager.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockUSDT.sol";
import "../src/mocks/MockSToken.sol";

import "../src/wallet.sol";
import "../src/clonePUlleytrade/clonePuLTrade.sol";


contract DeployScript is Script {

     // Core contracts
    PermissionManager public permissionManager;
    PulleyToken public pulleyToken;
    Wallet public wallet;
    PulTradingPool public tradingPool;
    PulleyController public controller;
    ClonePuLTrade public cloneFactory;
    MockUSDC public usdc;
    MockUSDT public usdt;
    MockSToken public sToken;
   

    address[] public supportedAssets;
  

    function run() external {
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);
        vm.createSelectFork(vm.rpcUrl("sonicchain"));
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying Simplified Pulley Protocol...");

        // Deploy all contracts
        _deployContracts();
        
        // Initialize contracts with proper configuration
        _configureContracts(deployer);
        
        // Set up permissions
        _setupPermissions();
        
        // Log deployment information
        _logDeployment();

        vm.stopBroadcast();
        
    }

    function _deployContracts() internal {
        console.log("Deploying contracts...");

        // Deploy mock tokens first
        usdc = new MockUSDC();
        console.log("USDC:", address(usdc));
        
        usdt = new MockUSDT();
        console.log("USDT:", address(usdt));
        
        sToken = new MockSToken();
        console.log("sToken:", address(sToken));
        
        // Set up supported assets array
        supportedAssets = new address[](3);
        supportedAssets[0] = address(usdc);
        supportedAssets[1] = address(usdt);
        supportedAssets[2] = address(sToken);

        // Deploy core contracts
        permissionManager = new PermissionManager();
        console.log("PermissionManager:", address(permissionManager));
        
        wallet = new Wallet();
        console.log("Wallet:", address(wallet));
        
        pulleyToken = new PulleyToken(
            "Pulley Token",
            "PUL",
            address(permissionManager),
            supportedAssets
        );
        console.log("PulleyToken:", address(pulleyToken));

        // Deploy implementations first (these will be used as templates)
        PulTradingPool tradingPoolImplementation = new PulTradingPool();
        console.log("TradingPool Implementation:", address(tradingPoolImplementation));
        
        PulleyController controllerImplementation = new PulleyController();
        console.log("Controller Implementation:", address(controllerImplementation));
        
        // Deploy Clone Factory with implementations
        cloneFactory = new ClonePuLTrade(
            address(tradingPoolImplementation),
            address(controllerImplementation),
            address(wallet),
            address(pulleyToken),
            address(permissionManager),
            msg.sender // Owner
        );
        console.log("Clone Factory:", address(cloneFactory));
    }

    function _configureContracts(address deployer) internal {
        console.log("Configuring contracts...");

        // Grant permission to clone factory for addAsset (needed before clone creation)
        permissionManager.grantPermission(address(cloneFactory), PulTradingPool.addAsset.selector);
        console.log("Permissions granted to clone factory");
        
        // Create the main trading pool and controller using the clone factory
        console.log("Creating main trading pool and controller via clone factory...");
        
        // Create clone with default parameters
        (address poolAddress, address controllerAddress, address walletAddress) = cloneFactory.quickCreateClone(
            "Pulley Main Pool", // name
            "PULMP", // symbol
            address(sToken), // Use sToken as the custom asset for the main pool
            18, // sToken has 18 decimals
            1000 * 1e18, // 1000 USD threshold
            1000 * 1e18, // 1000 USD max deposit
            1000 * 1e18  // 1000 USD min deposit
        );
        
        tradingPool = PulTradingPool(payable(poolAddress));
        controller = PulleyController(payable(controllerAddress));
        
        console.log("Main Trading Pool:", address(tradingPool));
        console.log("Main Controller:", address(controller));

        // Initialize Wallet with the cloned controller
        wallet.initialize(address(controller), address(controller)); // Controller is the AI signer
        console.log("Wallet initialized");

        // Grant permission to deployer for setContracts
        permissionManager.grantPermission(deployer, PulleyToken.setContracts.selector);
        
        // Grant permission to deployer for addAsset
        permissionManager.grantPermission(deployer, PulTradingPool.addAsset.selector);
        
        // Grant permission to deployer for setAIWallet
        permissionManager.grantPermission(deployer, PulleyController.setAIWallet.selector);

        // Set up contract references
        pulleyToken.setContracts(address(0), address(controller), address(tradingPool));
        console.log("PulleyToken contract references set");

        // Add supported assets to trading pool (decimals are determined by the asset contracts)
        // Note: Users can add their own assets with any decimals via the trading pool interface
        tradingPool.addAsset(
            address(usdc),
            6, // MockUSDC has 6 decimals (this is just for the main pool example)
            1000 * 1e18, // 1000 USD threshold
            address(0) // No price feed for mock tokens
        );
        console.log("USDC added to trading pool (6 decimals)");

        tradingPool.addAsset(
            address(usdt),
            6, // MockUSDT has 6 decimals (this is just for the main pool example)
            1000 * 1e18, // 1000 USD threshold
            address(0) // No price feed for mock tokens
        );
        console.log("USDT added to trading pool (6 decimals)");

        tradingPool.addAsset(
            address(sToken),
            18, // MockSToken has 18 decimals (this is just for the main pool example)
            1000 * 1e18, // 1000 USD threshold
            address(0) // No price feed for mock tokens
        );
        console.log("sToken added to trading pool (18 decimals)");

        // Set AI wallet in controller
        controller.setAIWallet(payable(address(wallet)));
        console.log("AI wallet set in controller");
        
        console.log("Main trading pool and controller created and configured successfully!");
    }

    function _setupPermissions() internal {
        console.log("Setting up permissions...");

        // Grant permissions to controller for trading pool functions
        bytes4[] memory controllerFunctions = new bytes4[](6);
        controllerFunctions[0] = bytes4(keccak256("recordProfit(uint256)"));
        controllerFunctions[1] = bytes4(keccak256("recordLoss(uint256)"));
        controllerFunctions[2] = bytes4(keccak256("distributeTradersProfit(uint256)"));
        controllerFunctions[3] = bytes4(keccak256("recordTradingProfit(uint256)"));
        controllerFunctions[4] = bytes4(keccak256("recordTradingLoss(uint256)"));
        controllerFunctions[5] = bytes4(keccak256("distributePeriodProfit(address,uint256,uint256)"));

        permissionManager.grantBatchPermission(address(controller), controllerFunctions);
        console.log("Controller permissions granted");

        // Grant permissions to trading pool for controller functions
        bytes4[] memory tradingPoolFunctions = new bytes4[](4);
        tradingPoolFunctions[0] = bytes4(keccak256("receiveFunds(address,uint256)"));
        tradingPoolFunctions[1] = bytes4(keccak256("reportTradingResult(bytes32,int256)"));
        tradingPoolFunctions[2] = bytes4(keccak256("updateAssetSupport(address,bool)"));
        tradingPoolFunctions[3] = bytes4(keccak256("mint(address,uint256)"));

        permissionManager.grantBatchPermission(address(tradingPool), tradingPoolFunctions);
        console.log("Trading pool permissions granted");

        // Grant permissions to pulley token for controller functions
        bytes4[] memory tokenFunctions = new bytes4[](3);
        tokenFunctions[0] = bytes4(keccak256("updateUtilization(uint256)"));
        tokenFunctions[1] = bytes4(keccak256("coverLoss(uint256)"));
        tokenFunctions[2] = bytes4(keccak256("addProfits(uint256)"));

        permissionManager.grantBatchPermission(address(pulleyToken), tokenFunctions);
        console.log("Pulley token permissions granted");

        // Grant permissions to clone factory for creating clones
        bytes4[] memory cloneFactoryFunctions = new bytes4[](2);
        cloneFactoryFunctions[0] = bytes4(keccak256("createClone((address,address,address,uint256,uint256,uint256,string,string))"));
        cloneFactoryFunctions[1] = bytes4(keccak256("quickCreateClone(string,string,address,uint256,uint256,uint256)"));

        permissionManager.grantBatchPermission(address(cloneFactory), cloneFactoryFunctions);
        console.log("Clone factory permissions granted");

        // Grant comprehensive permissions to deployer for system management
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        
        bytes4[] memory deployerFunctions = new bytes4[](15);
        deployerFunctions[0] = bytes4(keccak256("recordProfit(uint256)"));
        deployerFunctions[1] = bytes4(keccak256("recordLoss(uint256)"));
        deployerFunctions[2] = bytes4(keccak256("distributeTradersProfit(uint256)"));
        deployerFunctions[3] = bytes4(keccak256("recordTradingProfit(uint256)"));
        deployerFunctions[4] = bytes4(keccak256("recordTradingLoss(uint256)"));
        deployerFunctions[5] = bytes4(keccak256("distributePeriodProfit(address,uint256,uint256)"));
        deployerFunctions[6] = bytes4(keccak256("receiveFunds(address,uint256)"));
        deployerFunctions[7] = bytes4(keccak256("checkAIWalletPnL(address)"));
        deployerFunctions[8] = bytes4(keccak256("updateAssetSupport(address,bool)"));
        deployerFunctions[9] = bytes4(keccak256("mint(address,uint256)"));
        deployerFunctions[10] = bytes4(keccak256("updateUtilization(uint256)"));
        deployerFunctions[11] = bytes4(keccak256("coverLoss(uint256)"));
        deployerFunctions[12] = bytes4(keccak256("addProfits(uint256)"));
        deployerFunctions[13] = bytes4(keccak256("createClone((address,address,address,uint256,uint256,uint256,string,string))"));
        deployerFunctions[14] = bytes4(keccak256("quickCreateClone(string,string,address,uint256,uint256,uint256)"));

        permissionManager.grantBatchPermission(deployer, deployerFunctions);
        console.log("Deployer permissions granted:", deployer);
    }

    function _logDeployment() internal {
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Network: sonic Testnet");
        console.log("Deployer:", msg.sender);
        console.log("");
        
        console.log("=== CORE CONTRACTS ===");
        console.log("PermissionManager:", address(permissionManager));
        console.log("Wallet:", address(wallet));
        console.log("PulleyToken:", address(pulleyToken));
        console.log("Clone Factory:", address(cloneFactory));
        console.log("");
        
        console.log("=== MAIN TRADING POOL (CREATED VIA CLONE) ===");
        console.log("TradingPool:", address(tradingPool));
        console.log("Controller:", address(controller));
        console.log("");
        
        console.log("=== MOCK TOKENS ===");
        console.log("USDC:", address(usdc));
        console.log("USDT:", address(usdt));
        console.log("sToken:", address(sToken));
        console.log("");
        
        console.log("=== CONFIGURATION ===");
        console.log("Supported Assets Count:", supportedAssets.length);
        console.log("Example Assets (for main pool):");
        console.log("  - USDC: 6 decimals, 1000 USD threshold");
        console.log("  - USDT: 6 decimals, 1000 USD threshold");
        console.log("  - sToken: 18 decimals, 1000 USD threshold (used as custom asset)");
        console.log("");
        console.log("Note: Users can add custom assets with ANY decimals via tradingPool.addAsset()");
        console.log("Only native token and PulleyToken have fixed decimals");
        console.log("");
        console.log("AI Signer: Controller (", address(controller), ")");
        console.log("Deployer (Admin):", vm.addr(vm.envUint("PRIVATE_KEY")));
        console.log("Deployer has full system permissions");
        console.log("");
        
        console.log("=== VERIFICATION COMMANDS ===");
        console.log("forge verify-contract", address(permissionManager), "PermissionManager");
        console.log("forge verify-contract", address(wallet), "Wallet");
        console.log("forge verify-contract", address(pulleyToken), "PulleyToken");
        console.log("forge verify-contract", address(tradingPool), "PulTradingPool");
        console.log("forge verify-contract", address(controller), "PulleyController");
        console.log("forge verify-contract", address(cloneFactory), "ClonePuLTrade");
        console.log("");
        
        console.log("=== TESTING ===");
        console.log("1. Mint some USDC/USDT tokens");
        console.log("2. Approve main trading pool to spend tokens");
        console.log("3. Call tradingPool.deposit() to deposit assets");
        console.log("4. Check pool metrics with tradingPool.getPoolMetrics()");
        console.log("5. Add custom assets with any decimals: tradingPool.addAsset(asset, decimals, threshold, priceFeed)");
        console.log("6. Create additional trading strategies using cloneFactory.quickCreateClone(name, symbol, asset, decimals, nativeThreshold, pulleyThreshold, customThreshold)");
        console.log("7. Check clone count with cloneFactory.getCloneCount()");
        console.log("8. Each clone creates a new trading pool + controller pair");
        console.log("9. Users can create their own trading strategies with custom parameters and asset configurations");
        console.log("");
        
        console.log("Deployment completed successfully!");
    }
    
}