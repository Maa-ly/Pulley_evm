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
        _configureContracts();
        
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

        tradingPool = new PulTradingPool();
        console.log("TradingPool:", address(tradingPool));
        
        controller = new PulleyController();
        console.log("Controller:", address(controller));
        
        // Deploy Clone Factory (needs implementations to be deployed first)
        cloneFactory = new ClonePuLTrade(
            address(tradingPool),
            address(controller),
            address(wallet),
            address(pulleyToken),
            address(permissionManager),
            msg.sender // Owner
        );
        console.log("Clone Factory:", address(cloneFactory));
    }

    function _configureContracts() internal {
        console.log("Configuring contracts...");

        // Initialize Wallet
        wallet.initialize(address(controller), address(controller)); // Controller is the AI signer
        console.log("Wallet initialized");

        // Initialize Trading Pool
        tradingPool.initialize(
            "Pulley Trading Pool",
            "PULTP",
            address(permissionManager),
            address(controller),
            address(pulleyToken)
        );
        console.log("Trading Pool initialized");

        // Initialize Controller
        controller.initialize(
            address(permissionManager),
            address(tradingPool),
            address(0), // No insurance pool for now
            address(pulleyToken),
            address(0), // No AI trader for now
            supportedAssets
        );
        console.log("Controller initialized");

        // Set up contract references
        pulleyToken.setContracts(address(0), address(controller), address(tradingPool));
        console.log("PulleyToken contract references set");

        // Add supported assets to trading pool
        tradingPool.addAsset(
            address(usdc),
            6, // USDC has 6 decimals
            1000 * 1e18, // 1000 USD threshold
            address(0) // No price feed for mock tokens
        );
        console.log("USDC added to trading pool");

        tradingPool.addAsset(
            address(usdt),
            6, // USDT has 6 decimals
            1000 * 1e18, // 1000 USD threshold
            address(0) // No price feed for mock tokens
        );
        console.log("USDT added to trading pool");

        tradingPool.addAsset(
            address(sToken),
            18, // sToken has 18 decimals
            1000 * 1e18, // 1000 USD threshold
            address(0) // No price feed for mock tokens
        );
        console.log("sToken added to trading pool");

        // Set AI wallet in controller
        controller.setAIWallet(payable(address(wallet)));
        console.log("AI wallet set in controller");
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
        console.log("Network: Kairos Testnet");
        console.log("Deployer:", msg.sender);
        console.log("");
        
        console.log("=== CORE CONTRACTS ===");
        console.log("PermissionManager:", address(permissionManager));
        console.log("Wallet:", address(wallet));
        console.log("PulleyToken:", address(pulleyToken));
        console.log("TradingPool:", address(tradingPool));
        console.log("Controller:", address(controller));
        console.log("Clone Factory:", address(cloneFactory));
        console.log("");
        
        console.log("=== MOCK TOKENS ===");
        console.log("USDC:", address(usdc));
        console.log("USDT:", address(usdt));
        console.log("sToken:", address(sToken));
        console.log("");
        
        console.log("=== CONFIGURATION ===");
        console.log("Supported Assets Count:", supportedAssets.length);
        console.log("USDC Threshold: 1000 USD");
        console.log("USDT Threshold: 1000 USD");
        console.log("sToken Threshold: 1000 USD");
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
        console.log("2. Approve trading pool to spend tokens");
        console.log("3. Call tradingPool.deposit() to deposit assets");
        console.log("4. Check pool metrics with tradingPool.getPoolMetrics()");
        console.log("5. Create clone pools using cloneFactory.quickCreateClone()");
        console.log("6. Check clone count with cloneFactory.getCloneCount()");
        console.log("");
        
        console.log("Deployment completed successfully!");
    }
    
}