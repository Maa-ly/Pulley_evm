//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {PulTradingPool} from "../src/Pool/PuLTradingPool.sol";
import {PulleyController} from "../src/PulleyController.sol";
import {Wallet} from "../src/wallet.sol";
import {PulleyToken} from "../src/Token/PulleyToken.sol";
import {ClonePuLTrade} from "../src/clonePUlleytrade/clonePuLTrade.sol";
import {PermissionManager} from "../src/PermissionManager.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title Complete System Test
 * @notice End-to-end tests for the complete Pulley Protocol system
 */
contract CompleteSystemTest is Test {
    
    // ============ Test Contracts ============
    
    PulTradingPool public poolImplementation;
    PulleyController public controllerImplementation;
    Wallet public walletImplementation;
    PulleyToken public pulleyToken;
    ClonePuLTrade public cloneFactory;
    PermissionManager public permissionManager;
    
    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public weth;
    
    // ============ Test Addresses ============
    
    address public owner = makeAddr("owner");
    address public aiSigner = makeAddr("aiSigner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    
    // ============ Test Constants ============
    
    uint256 public constant USDC_THRESHOLD = 1000e6; // 1,000 USDC
    uint256 public constant WETH_THRESHOLD = 1e18; // 1 WETH
    uint256 public constant PULLEY_THRESHOLD = 5000e18; // 5,000 PULLEY
    
    // ============ Setup ============
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy core contracts
        permissionManager = new PermissionManager();
        // Setup supported assets for PulleyToken
        address[] memory supportedAssets = new address[](1);
        supportedAssets[0] = address(usdc);
        
        pulleyToken = new PulleyToken("Pulley Token", "PULLEY", address(permissionManager), supportedAssets);
        poolImplementation = new PulTradingPool();
        controllerImplementation = new PulleyController();
        walletImplementation = new Wallet();
        
        // Deploy clone factory
        cloneFactory = new ClonePuLTrade(
            address(poolImplementation),
            address(controllerImplementation),
            address(walletImplementation),
            address(pulleyToken),
            address(permissionManager),
            owner
        );
        
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        
        vm.stopPrank();
        
        // Mint tokens to users
        _mintTokensToUsers();
    }
    
    function _mintTokensToUsers() internal {
        // Mint USDC
        usdc.mint(user1, 10000e6);
        usdc.mint(user2, 10000e6);
        usdc.mint(user3, 10000e6);
        
        // Mint WETH
        weth.mint(user1, 100e18);
        weth.mint(user2, 100e18);
        weth.mint(user3, 100e18);
        
        // Mint PULLEY
        pulleyToken.mint(user1, 100000e18);
        pulleyToken.mint(user2, 100000e18);
        pulleyToken.mint(user3, 100000e18);
        
        // Approve spending
        vm.prank(user1);
        usdc.approve(address(0), type(uint256).max); // Will be set to actual clone address
        vm.prank(user1);
        weth.approve(address(0), type(uint256).max);
        vm.prank(user1);
        pulleyToken.approve(address(0), type(uint256).max);
        
        vm.prank(user2);
        usdc.approve(address(0), type(uint256).max);
        vm.prank(user2);
        weth.approve(address(0), type(uint256).max);
        vm.prank(user2);
        pulleyToken.approve(address(0), type(uint256).max);
        
        vm.prank(user3);
        usdc.approve(address(0), type(uint256).max);
        vm.prank(user3);
        weth.approve(address(0), type(uint256).max);
        vm.prank(user3);
        pulleyToken.approve(address(0), type(uint256).max);
    }
    
    // ============ Clone Creation Tests ============
    
    function testCreateClone() public {
        console.log("=== Testing Clone Creation ===");
        
        // Create a clone
        (address clone, address controller, address wallet) = cloneFactory.quickCreateClone(
            "Test Pool",
            "TP",
            address(usdc),
            WETH_THRESHOLD,
            PULLEY_THRESHOLD,
            USDC_THRESHOLD
        );
        
        // Verify clone was created
        assertTrue(clone != address(0));
        assertTrue(controller != address(0));
        assertTrue(wallet != address(0));
        assertTrue(cloneFactory.isClone(clone));
        
        // Verify clone configuration
        DataTypes.PoolCloneConfig memory config = cloneFactory.getCloneConfig(clone);
        assertEq(config.poolName, "Test Pool");
        assertEq(config.poolSymbol, "TP");
        assertEq(config.customAsset, address(usdc));
        assertEq(config.nativeThreshold, WETH_THRESHOLD);
        assertEq(config.pulleyThreshold, PULLEY_THRESHOLD);
        assertEq(config.customThreshold, USDC_THRESHOLD);
        
        console.log("Clone created successfully:", clone);
        console.log("Controller:", controller);
        console.log("Wallet:", wallet);
    }
    
    function testMultipleClones() public {
        console.log("=== Testing Multiple Clones ===");
        
        // Create first clone
        (address clone1, , ) = cloneFactory.quickCreateClone(
            "Pool 1",
            "P1",
            address(usdc),
            WETH_THRESHOLD,
            PULLEY_THRESHOLD,
            USDC_THRESHOLD
        );
        
        // Create second clone with different asset
        (address clone2, , ) = cloneFactory.quickCreateClone(
            "Pool 2",
            "P2",
            address(weth),
            WETH_THRESHOLD * 2,
            PULLEY_THRESHOLD * 2,
            USDC_THRESHOLD * 2
        );
        
        assertTrue(clone1 != clone2);
        assertTrue(cloneFactory.isClone(clone1));
        assertTrue(cloneFactory.isClone(clone2));
        assertEq(cloneFactory.getCloneCount(), 2);
        
        console.log("Multiple clones created successfully");
    }
    
    // ============ Period-Based Trading Tests ============
    
    function testPeriodRestrictions() public {
        console.log("=== Testing Period Restrictions ===");
        
        // Create a clone
        (address clone, , ) = cloneFactory.quickCreateClone(
            "Test Pool",
            "TP",
            address(usdc),
            WETH_THRESHOLD,
            PULLEY_THRESHOLD,
            USDC_THRESHOLD
        );
        
        PulTradingPool pool = PulTradingPool(clone);
        
        // Update approvals to point to the actual clone
        vm.prank(user1);
        usdc.approve(clone, type(uint256).max);
        vm.prank(user2);
        usdc.approve(clone, type(uint256).max);
        vm.prank(user3);
        usdc.approve(clone, type(uint256).max);
        
        // First user deposits
        vm.prank(user1);
        pool.deposit(address(usdc), 600e6); // 600 USDC
        
        // Check period not started yet
        uint256[] memory activePeriods = pool.getActivePeriods(address(usdc));
        assertEq(activePeriods.length, 0);
        
        // Second user deposits, reaching threshold
        vm.prank(user2);
        pool.deposit(address(usdc), 500e6); // 500 USDC, total: 1100 USDC (reaches threshold)
        
        // Check period started
        activePeriods = pool.getActivePeriods(address(usdc));
        assertTrue(activePeriods.length > 0);
        assertEq(activePeriods[0], 1);
        
        // Third user can still join (continuous periods)
        vm.prank(user3);
        pool.deposit(address(usdc), 100e6);
        
        console.log("Period restrictions working correctly");
    }
    
    function testAssetSpecificPeriods() public {
        console.log("=== Testing Asset-Specific Periods ===");
        
        // Create a clone
        (address clone, , ) = cloneFactory.quickCreateClone(
            "Test Pool",
            "TP",
            address(usdc),
            WETH_THRESHOLD,
            PULLEY_THRESHOLD,
            USDC_THRESHOLD
        );
        
        PulTradingPool pool = PulTradingPool(clone);
        
        // Update approvals
        vm.prank(user1);
        usdc.approve(clone, type(uint256).max);
        vm.prank(user1);
        weth.approve(clone, type(uint256).max);
        vm.prank(user2);
        usdc.approve(clone, type(uint256).max);
        vm.prank(user2);
        weth.approve(clone, type(uint256).max);
        
        // Start USDC period
        vm.prank(user1);
        pool.deposit(address(usdc), 1200e6); // Reaches USDC threshold
        
        uint256[] memory usdcActivePeriods = pool.getActivePeriods(address(usdc));
        assertTrue(usdcActivePeriods.length > 0);
        assertEq(usdcActivePeriods[0], 1);
        
        // Start WETH period (different asset, should work)
        vm.prank(user2);
        pool.deposit(address(weth), 2e18); // Reaches WETH threshold
        
        uint256[] memory wethActivePeriods = pool.getActivePeriods(address(weth));
        assertTrue(wethActivePeriods.length > 0);
        assertEq(wethActivePeriods[0], 1);
        
        // Both periods should be active independently
        assertTrue(usdcActivePeriods.length > 0);
        assertTrue(wethActivePeriods.length > 0);
        
        console.log("Asset-specific periods working correctly");
    }
    
    // ============ Profit Distribution Tests ============
    
    function testFairProfitDistribution() public {
        console.log("=== Testing Fair Profit Distribution ===");
        
        // Create a clone
        (address clone, address controller, ) = cloneFactory.quickCreateClone(
            "Test Pool",
            "TP",
            address(usdc),
            WETH_THRESHOLD,
            PULLEY_THRESHOLD,
            USDC_THRESHOLD
        );
        
        PulTradingPool pool = PulTradingPool(clone);
        
        // Update approvals
        vm.prank(user1);
        usdc.approve(clone, type(uint256).max);
        vm.prank(user2);
        usdc.approve(clone, type(uint256).max);
        
        // Setup: Users deposit to reach threshold
        vm.prank(user1);
        pool.deposit(address(usdc), 600e6); // 600 USD contribution
        
        vm.prank(user2);
        pool.deposit(address(usdc), 400e6); // 400 USD contribution, reaches threshold
        
        // Verify period started
        uint256[] memory activePeriods = pool.getActivePeriods(address(usdc));
        assertTrue(activePeriods.length > 0);
        assertEq(activePeriods[0], 1);
        
        // Simulate profit distribution
        uint256 profitAmount = 200e18; // 200 USD profit
        
        // Grant permission to controller
        vm.prank(owner);
        permissionManager.grantPermission(
            controller,
            pool.distributePeriodProfit.selector
        );
        
        vm.prank(controller);
        pool.distributePeriodProfit(address(usdc), profitAmount, 1);
        
        // Check period ended
        activePeriods = pool.getActivePeriods(address(usdc));
        assertEq(activePeriods.length, 0);
        
        // Check individual profits
        (uint256 user1Profit, ) = pool.calculateUserPnL(user1, address(usdc), 1);
        (uint256 user2Profit, ) = pool.calculateUserPnL(user2, address(usdc), 1);
        
        // Expected profits:
        // User1: 600/1000 * 200 = 120 USD profit
        // User2: 400/1000 * 200 = 80 USD profit
        assertEq(user1Profit, 120e18);
        assertEq(user2Profit, 80e18);
        
        console.log("User1 profit:", user1Profit / 1e18);
        console.log("User2 profit:", user2Profit / 1e18);
        console.log("Fair profit distribution working correctly");
    }
    
    // ============ Integration Tests ============
    
    function testCompleteFlow() public {
        console.log("=== Testing Complete Flow ===");
        
        // Create a clone
        (address clone, address controller, address wallet) = cloneFactory.quickCreateClone(
            "Complete Test Pool",
            "CTP",
            address(usdc),
            WETH_THRESHOLD,
            PULLEY_THRESHOLD,
            USDC_THRESHOLD
        );
        
        PulTradingPool pool = PulTradingPool(clone);
        
        // Update approvals
        vm.prank(user1);
        usdc.approve(clone, type(uint256).max);
        vm.prank(user2);
        usdc.approve(clone, type(uint256).max);
        vm.prank(user3);
        usdc.approve(clone, type(uint256).max);
        
        // Phase 1: Users deposit
        vm.prank(user1);
        pool.deposit(address(usdc), 300e6); // 300 USD
        
        vm.prank(user2);
        pool.deposit(address(usdc), 400e6); // 400 USD
        
        vm.prank(user3);
        pool.deposit(address(usdc), 500e6); // 500 USD, reaches threshold
        
        // Phase 2: Trading period active, new users can still join (continuous periods)
        uint256[] memory activePeriods = pool.getActivePeriods(address(usdc));
        assertTrue(activePeriods.length > 0);
        
        address user4 = makeAddr("user4");
        usdc.mint(user4, 1000e6);
        vm.prank(user4);
        usdc.approve(clone, type(uint256).max);
        
        // User4 can join (continuous periods)
        vm.prank(user4);
        pool.deposit(address(usdc), 100e6);
        
        // Phase 3: Trading completes with profit
        uint256 totalProfit = 240e18; // 240 USD profit (20% return)
        
        // Grant permission to controller
        vm.prank(owner);
        permissionManager.grantPermission(
            controller,
            pool.distributePeriodProfit.selector
        );
        
        vm.prank(controller);
        pool.distributePeriodProfit(address(usdc), totalProfit, 1);
        
        // Phase 4: Users claim profits
        // Expected profits:
        // User1: 300/1200 * 240 = 60 USD
        // User2: 400/1200 * 240 = 80 USD  
        // User3: 500/1200 * 240 = 100 USD
        
        (uint256 user1Profit, ) = pool.calculateUserPnL(user1, address(usdc), 1);
        (uint256 user2Profit, ) = pool.calculateUserPnL(user2, address(usdc), 1);
        (uint256 user3Profit, ) = pool.calculateUserPnL(user3, address(usdc), 1);
        
        assertEq(user1Profit, 60e18);
        assertEq(user2Profit, 80e18);
        assertEq(user3Profit, 100e18);
        
        console.log("User1 profit:", user1Profit / 1e18);
        console.log("User2 profit:", user2Profit / 1e18);
        console.log("User3 profit:", user3Profit / 1e18);
        
        // Phase 5: Period ended
        activePeriods = pool.getActivePeriods(address(usdc));
        assertEq(activePeriods.length, 0);
        
        // User4 can now join
        vm.prank(user4);
        pool.deposit(address(usdc), 100e6);
        
        assertGt(pool.balanceOf(user4), 0);
        
        console.log("Complete flow test passed");
    }
    
    // ============ Error Handling Tests ============
    
    function testInvalidCloneConfiguration() public {
        console.log("=== Testing Invalid Clone Configuration ===");
        
        // Test with zero threshold
        vm.expectRevert();
        cloneFactory.quickCreateClone(
            "Invalid Pool",
            "IP",
            address(usdc),
            0, // Invalid threshold
            PULLEY_THRESHOLD,
            USDC_THRESHOLD
        );
        
        // Test with zero address custom asset
        vm.expectRevert();
        cloneFactory.quickCreateClone(
            "Invalid Pool",
            "IP",
            address(0), // Invalid custom asset
            WETH_THRESHOLD,
            PULLEY_THRESHOLD,
            USDC_THRESHOLD
        );
        
        console.log("Invalid configuration handling working correctly");
    }
    
    function testUnauthorizedAccess() public {
        console.log("=== Testing Unauthorized Access ===");
        
        // Create a clone
        (address clone, , ) = cloneFactory.quickCreateClone(
            "Test Pool",
            "TP",
            address(usdc),
            WETH_THRESHOLD,
            PULLEY_THRESHOLD,
            USDC_THRESHOLD
        );
        
        PulTradingPool pool = PulTradingPool(clone);
        
        // Try to call admin function without permission
        vm.expectRevert();
        vm.prank(user1);
        pool.addAsset(address(usdc), 6, USDC_THRESHOLD, address(0));
        
        console.log("Unauthorized access handling working correctly");
    }
}
