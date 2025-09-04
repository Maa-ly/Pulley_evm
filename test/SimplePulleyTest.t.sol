//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/Token/PulleyToken.sol";
import "../src/PulleyController.sol";
import "../src/Pool/PuLTradingPool.sol";

import {PermissionManager} from "../src/PermissionManager.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockBlocklockSender.sol";

/**
 * @title SimplePulleyTest
 * @notice Test the simplified Pulley architecture
 */
contract SimplePulleyTest is Test {
    
    // Contracts
    PulleyToken public pulleyToken;
    PulleyController public controller;
    PulTradingPool public tradingPool;

    PermissionManager public permissionManager;
    
    // Mock contracts
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockBlocklockSender public blocklockSender;
    
    // Test addresses
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public aiTrader = address(0x3);
    
    // Constants
    uint256 public constant INITIAL_SUPPLY = 1000000 * 1e6; // 1M tokens with 6 decimals
    uint256 public constant THRESHOLD = 10000 * 1e18; // 10,000 USD
    
    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);
        blocklockSender = new MockBlocklockSender();
        
        // Deploy permission manager
        permissionManager = new PermissionManager();
        
        // Setup supported assets
        address[] memory supportedAssets = new address[](2);
        supportedAssets[0] = address(usdc);
        supportedAssets[1] = address(usdt);
        
        // Deploy PulleyToken (floating stablecoin)
        pulleyToken = new PulleyToken(
            "Pulley Token",
            "PULL",
            address(permissionManager),
            supportedAssets
        );
        

        
        // Deploy TradingPool
        tradingPool = new PulTradingPool();
        
        // Deploy Controller
        controller = new PulleyController();
        
        // Configure contracts
        _configureContracts();
        
        // Setup permissions (simplified - just make test contract owner)
        // In production, use proper permission system
        
        // Mint tokens to users
        usdc.mint(user1, INITIAL_SUPPLY);
        usdc.mint(user2, INITIAL_SUPPLY);
        usdt.mint(user1, INITIAL_SUPPLY);
        usdt.mint(user2, INITIAL_SUPPLY);
    }
    
    function _configureContracts() internal {
        // Grant permissions to test contract for setup
        permissionManager.grantPermission(address(this), PulleyToken.setContracts.selector);
        permissionManager.grantPermission(address(this), PulTradingPool.updateController.selector);
        permissionManager.grantPermission(address(this), PulTradingPool.updatePulleyToken.selector);
        permissionManager.grantPermission(address(this), PulTradingPool.addAsset.selector);
        permissionManager.grantPermission(address(this), PulTradingPool.updateThreshold.selector);
        permissionManager.grantPermission(address(this), PulleyController.setAITrader.selector);
        
        // Set contracts
        pulleyToken.setContracts(address(0), address(controller), address(tradingPool));
        tradingPool.updateController(address(controller));
        tradingPool.updatePulleyToken(address(pulleyToken));
        controller.setAITrader(aiTrader);
        
        // Initialize contracts
        tradingPool.initialize(
            "Pulley Pool Token",
            "PPT",
            address(permissionManager),
            address(controller),
            address(pulleyToken)
        );
        
        // Prepare supported assets for controller initialization
        address[] memory supportedAssets = new address[](2);
        supportedAssets[0] = address(usdc);
        supportedAssets[1] = address(usdt);
        
        controller.initialize(
            address(permissionManager),
            address(tradingPool),
            address(0), // No separate insurance pool
            address(pulleyToken),
            address(0), // AI Trader set later
            supportedAssets
        );
        
        // Add assets to trading pool
        tradingPool.addAsset(address(usdc), 6, 1000 * 1e6, address(0));
        tradingPool.addAsset(address(usdt), 6, 1000 * 1e6, address(0));
        
        // Set threshold
        tradingPool.updateThreshold(THRESHOLD);
        
        // Grant permissions for runtime operations
        permissionManager.grantPermission(address(controller), PulTradingPool.recordProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordLoss.selector);
        permissionManager.grantPermission(address(aiTrader), PulleyController.reportTradingResult.selector);
        permissionManager.grantPermission(address(tradingPool), PulleyController.receiveFunds.selector);
    }
    
    // ============ Basic Functionality Tests ============
    
    function testPulleyTokenMinting() public {
        uint256 mintAmount = 1000 * 1e6; // 1000 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), mintAmount);
        
        uint256 tokensMinted = pulleyToken.mint(address(usdc), mintAmount);
        
        assertGt(tokensMinted, 0);
        assertEq(pulleyToken.balanceOf(user1), tokensMinted);
        
        // Check price (should not be 1:1)
        uint256 price = pulleyToken.getCurrentPrice();
        console.log("Pulley Token Price:", price);
        
        vm.stopPrank();
    }
    
    function testTradingPoolDeposit() public {
        uint256 depositAmount = 5000 * 1e6; // 5000 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), depositAmount);
        
        uint256 poolTokens = tradingPool.deposit(address(usdc), depositAmount);
        
        assertGt(poolTokens, 0);
        assertEq(tradingPool.balanceOf(user1), poolTokens);
        
        // Check pool metrics
        (uint256 totalValue, uint256 deposited, , , ) = tradingPool.getPoolMetrics();
        assertEq(deposited, 5000 * 1e18); // Should be in 18 decimals
        
        vm.stopPrank();
    }
    
    function testThresholdMechanism() public {
        // Deposit enough to trigger threshold
        uint256 depositAmount = 12000 * 1e6; // 12,000 USDC (above 10,000 threshold)
        
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), depositAmount);
        
        // This should trigger the threshold
        tradingPool.deposit(address(usdc), depositAmount);
        
        vm.stopPrank();
        
        // Check that funds were sent to controller
        (uint256 totalValue, uint256 deposited, , , ) = tradingPool.getPoolMetrics();
        assertEq(deposited, 0); // Should be reset after threshold
        
        // Check controller received funds
        (uint256 insuranceFunds, uint256 tradingFunds, , ) = controller.getSystemMetrics();
        assertGt(insuranceFunds, 0);
        assertGt(tradingFunds, 0);
        
        // Verify 15%/85% split
        uint256 total = insuranceFunds + tradingFunds;
        uint256 expectedInsurance = total * 15 / 100;
        uint256 expectedTrading = total * 85 / 100;
        
        assertApproxEqRel(insuranceFunds, expectedInsurance, 0.01e18); // 1% tolerance
        assertApproxEqRel(tradingFunds, expectedTrading, 0.01e18);
    }
    
    function testProfitDistribution() public {
        // First trigger threshold
        _triggerThreshold();
        
        // Simulate AI trading profit
        bytes32 requestId = bytes32(uint256(1));
        int256 profit = 1000 * 1e18; // 1000 USD profit
        
        vm.prank(aiTrader);
        controller.reportTradingResult(requestId, profit);
        
        // Check metrics
        ( , , uint256 totalProfits, ) = controller.getSystemMetrics();
        assertEq(totalProfits, uint256(profit));
    }
    
    function testLossHandling() public {
        // First trigger threshold
        _triggerThreshold();
        
        // Simulate AI trading loss
        bytes32 requestId = bytes32(uint256(1));
        int256 loss = -500 * 1e18; // 500 USD loss
        
        vm.prank(aiTrader);
        controller.reportTradingResult(requestId, loss);
        
        // Check metrics
        ( , , , uint256 totalLosses) = controller.getSystemMetrics();
        assertEq(totalLosses, 500 * 1e18);
    }
    
    function testPulleyTokenGrowth() public {
        // Mint some tokens
        uint256 mintAmount = 10000 * 1e6; // 10,000 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), mintAmount);
        pulleyToken.mint(address(usdc), mintAmount);
        vm.stopPrank();
        
        uint256 initialSupply = pulleyToken.totalSupply();
        uint256 initialPrice = pulleyToken.getCurrentPrice();
        
        // Simulate utilization
        pulleyToken.updateUtilization(5000); // 50% utilization (in basis points)
        
        // Fast forward time
        vm.warp(block.timestamp + 1 days);
        
        // Trigger growth
        pulleyToken.updateGrowth();
        
        uint256 newSupply = pulleyToken.totalSupply();
        uint256 newPrice = pulleyToken.getCurrentPrice();
        
        // Supply should have grown
        assertGt(newSupply, initialSupply);
        
        // Price should have increased (floating, not 1:1)
        assertGt(newPrice, initialPrice);
        
        console.log("Initial Price:", initialPrice);
        console.log("New Price:", newPrice);
        console.log("Price Growth:", ((newPrice - initialPrice) * 100) / initialPrice, "%");
    }
    
    function testFullSystemFlow() public {
        // 1. User mints Pulley tokens (floating stablecoin)
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), 5000 * 1e6);
        uint256 pulleyTokens = pulleyToken.mint(address(usdc), 5000 * 1e6);
        vm.stopPrank();
        
        console.log("Pulley Tokens Minted:", pulleyTokens);
        console.log("Initial Price:", pulleyToken.getCurrentPrice());
        
        // 2. User deposits in trading pool
        vm.startPrank(user2);
        usdc.approve(address(tradingPool), 12000 * 1e6);
        uint256 poolTokens = tradingPool.deposit(address(usdc), 12000 * 1e6);
        vm.stopPrank();
        
        console.log("Pool Tokens Minted:", poolTokens);
        
        // 3. Check allocations after threshold
        (uint256 insuranceFunds, uint256 tradingFunds, , ) = controller.getSystemMetrics();
        console.log("Insurance Funds:", insuranceFunds);
        console.log("Trading Funds:", tradingFunds);
        
        // 4. Simulate profit
        bytes32 requestId = bytes32(uint256(1));
        vm.prank(aiTrader);
        controller.reportTradingResult(requestId, 2000 * 1e18); // 2000 USD profit
        
        // 5. Check final metrics
        ( , , uint256 totalProfits, ) = controller.getSystemMetrics();
        console.log("Total Profits:", totalProfits);
        
        // 6. Check Pulley token growth
        vm.warp(block.timestamp + 1 days);
        pulleyToken.updateGrowth();
        
        uint256 finalPrice = pulleyToken.getCurrentPrice();
        console.log("Final Price:", finalPrice);
    }
    
    // ============ Helper Functions ============
    
    function _triggerThreshold() internal {
        uint256 depositAmount = 12000 * 1e6; // Above threshold
        
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), depositAmount);
        tradingPool.deposit(address(usdc), depositAmount);
        vm.stopPrank();
    }
}
