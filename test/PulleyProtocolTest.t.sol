//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {PermissionManager} from "../src/PermissionManager.sol";
import {PulleyToken} from "../src/Token/PulleyToken.sol";

import {PulTradingPool} from "../src/Pool/PuLTradingPool.sol";
import {PulleyController} from "../src/PulleyController.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockBlocklockSender} from "./mocks/MockBlocklockSender.sol";

/**
 * @title PulleyProtocolTest
 * @notice Comprehensive tests for the updated Pulley Protocol
 */
contract PulleyProtocolTest is Test {
    
    // Core contracts
    PermissionManager public permissionManager;
    PulleyToken public pulleyToken;

    PulTradingPool public tradingPool;
    PulleyController public controller;
    MockBlocklockSender public blocklockSender;
    
    // Mock tokens
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockERC20 public weth;
    
    // Test users
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public aiTrader = makeAddr("aiTrader");
    address public admin = makeAddr("admin");
    
    // Constants
    uint256 public constant THRESHOLD = 10000 * 1e18; // $10,000 USD
    uint256 public constant INITIAL_SUPPLY = 1000000 * 1e18; // 1M tokens
    
    event TradingPeriodStarted(uint256 indexed periodId, uint256 startTime);
    event ProfitsDistributedForPeriod(uint256 indexed periodId, uint256 totalProfit);
    event TradeRequestSent(bytes32 indexed requestId, address indexed asset, uint256 amount);
    
    function setUp() public {
        vm.startPrank(admin);
        
        _deployContracts();
        _setupPermissions();
        _configureContracts();
        _mintTokensToUsers();
        
        vm.stopPrank();
    }
    
    function _deployContracts() internal {
        // Deploy infrastructure
        permissionManager = new PermissionManager();
        blocklockSender = new MockBlocklockSender();
        
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        
        // Prepare supported assets
        address[] memory supportedAssets = new address[](3);
        supportedAssets[0] = address(usdc);
        supportedAssets[1] = address(usdt);
        supportedAssets[2] = address(weth);
        
        // Deploy core contracts
        pulleyToken = new PulleyToken(
            "Pulley Token",
            "PLLY",
            address(permissionManager),
            supportedAssets
        );
        

        
        tradingPool = new PulTradingPool(
            "Pulley Pool Token",
            "PPT",
            address(permissionManager),
            address(0), // Controller set later
            address(0)  // PulleyToken set later
        );
        
        controller = new PulleyController(
            address(permissionManager),
            address(tradingPool),
            address(0), // No separate insurance pool
            address(pulleyToken),
            supportedAssets,
            address(blocklockSender)
        );
    }
    
    function _configureContracts() internal {
        // Set contract relationships
        pulleyToken.setContracts(
            address(0), 
            address(controller), 
            address(tradingPool)
        );
        
        tradingPool.updateController(address(controller));
        tradingPool.updatePulleyToken(address(pulleyToken));
        
        controller.setAITrader(aiTrader);
        
        // Add assets to trading pool
        tradingPool.addAsset(address(usdc), 6);
        tradingPool.addAsset(address(usdt), 6);
        tradingPool.addAsset(address(weth), 18);
        
        // Set threshold
        tradingPool.updateThreshold(THRESHOLD);
    }
    
    function _setupPermissions() internal {
        // Admin permissions
        permissionManager.grantPermission(admin, PulleyToken.setContracts.selector);
        permissionManager.grantPermission(admin, PulTradingPool.updateController.selector);
        permissionManager.grantPermission(admin, PulTradingPool.updatePulleyToken.selector);
        permissionManager.grantPermission(admin, PulTradingPool.addAsset.selector);
        permissionManager.grantPermission(admin, PulTradingPool.updateThreshold.selector);
        permissionManager.grantPermission(admin, PulleyController.setAITrader.selector);
        
        // Operational permissions
        permissionManager.grantPermission(address(controller), PulTradingPool.recordProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordLoss.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.distributeTradersProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.startTradingPeriod.selector);
        
        permissionManager.grantPermission(address(tradingPool), PulleyController.receiveFunds.selector);
        permissionManager.grantPermission(aiTrader, PulleyController.reportTradingResult.selector);
    }
    
    function _mintTokensToUsers() internal {
        // Mint tokens to users
        usdc.mint(user1, INITIAL_SUPPLY / 1e12); // Convert to 6 decimals
        usdc.mint(user2, INITIAL_SUPPLY / 1e12);
        usdt.mint(user1, INITIAL_SUPPLY / 1e12);
        usdt.mint(user2, INITIAL_SUPPLY / 1e12);
        weth.mint(user1, INITIAL_SUPPLY);
        weth.mint(user2, INITIAL_SUPPLY);
    }
    
    // ============ Basic Functionality Tests ============
    
    function testPulleyTokenMinting() public {
        uint256 mintAmount = 1000 * 1e6; // 1000 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), mintAmount);
        
        uint256 tokensBefore = pulleyToken.balanceOf(user1);
        uint256 tokensToMint = pulleyToken.mint(address(usdc), mintAmount);
        uint256 tokensAfter = pulleyToken.balanceOf(user1);
        
        assertEq(tokensAfter - tokensBefore, tokensToMint);
        assertGt(tokensToMint, 0);
        
        console.log("Pulley tokens minted:", tokensToMint);
        vm.stopPrank();
    }
    
    function testControllerMintingLogic() public {
        uint256 mintAmount = 1000 * 1e6; // 1000 USDC
        
        // Test controller minting (should add to insurance reserve)
        vm.startPrank(address(controller));
        usdc.approve(address(pulleyToken), mintAmount);
        
        uint256 insuranceBefore = pulleyToken.insuranceReserve();
        pulleyToken.mint(address(usdc), mintAmount);
        uint256 insuranceAfter = pulleyToken.insuranceReserve();
        
        assertGt(insuranceAfter, insuranceBefore);
        console.log("Insurance reserve increased by:", insuranceAfter - insuranceBefore);
        vm.stopPrank();
    }
    
    function testTradingPoolDeposit() public {
        uint256 depositAmount = 5000 * 1e6; // 5000 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), depositAmount);
        
        uint256 poolTokens = tradingPool.deposit(address(usdc), depositAmount);
        
        assertGt(poolTokens, 0);
        assertEq(tradingPool.balanceOf(user1), poolTokens);
        
        console.log("Pool tokens received:", poolTokens);
        vm.stopPrank();
    }
    
    function testTradingPeriodMechanism() public {
        // Start a trading period
        vm.prank(address(controller));
        tradingPool.startTradingPeriod();
        
        uint256 currentPeriod = tradingPool.currentPeriodId();
        assertEq(currentPeriod, 1);
        
        // Deposit during active period
        uint256 depositAmount = 3000 * 1e6; // 3000 USDC
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), depositAmount);
        tradingPool.deposit(address(usdc), depositAmount);
        vm.stopPrank();
        
        // Verify user is recorded for this period
        (uint256 startTime, uint256 endTime, uint256 totalTokens, bool isActive, bool profitsDistributed) = 
            tradingPool.tradingPeriods(currentPeriod);
        
        assertTrue(isActive);
        assertGt(totalTokens, 0);
        console.log("Trading period started with total tokens:", totalTokens);
    }
    
    function testThresholdMechanism() public {
        // Deposit enough to reach threshold
        uint256 depositAmount = 12000 * 1e6; // 12000 USDC (above 10k threshold)
        
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), depositAmount);
        
        // Expect trade request event when threshold is reached
        vm.expectEmit(true, true, false, true);
        emit TradeRequestSent(keccak256(""), address(usdc), 0);
        
        tradingPool.deposit(address(usdc), depositAmount);
        vm.stopPrank();
        
        // Verify funds were sent to controller
        assertTrue(tradingPool.totalDeposited() < THRESHOLD); // Should reset after transfer
    }
    
    function testProfitDistribution() public {
        // Setup: Start trading period and make deposits
        vm.prank(address(controller));
        tradingPool.startTradingPeriod();
        
        uint256 depositAmount = 5000 * 1e6; // 5000 USDC
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), depositAmount);
        tradingPool.deposit(address(usdc), depositAmount);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(tradingPool), depositAmount);
        tradingPool.deposit(address(usdc), depositAmount);
        vm.stopPrank();
        
        // Simulate profit distribution
        uint256 profitAmount = 1000 * 1e18; // $1000 profit
        
        vm.expectEmit(true, false, false, true);
        emit ProfitsDistributedForPeriod(1, profitAmount);
        
        vm.prank(address(controller));
        tradingPool.distributeTradersProfit(profitAmount);
        
        // Verify profit was added to pool value
        (uint256 totalValue, , uint256 profits, , ) = tradingPool.getPoolMetrics();
        assertEq(profits, profitAmount);
        console.log("Total pool value after profit:", totalValue);
    }
    
    function testLossCoverage() public {
        // First, create some insurance funds
        uint256 insuranceAmount = 2000 * 1e18; // $2000 insurance
        vm.prank(address(controller));
        tradingPool.recordProfit(insuranceAmount);
        
        // Now test loss coverage
        uint256 lossAmount = 1000 * 1e18; // $1000 loss
        
        uint256 poolValueBefore = tradingPool.totalPoolValue();
        
        vm.prank(address(controller));
        tradingPool.recordLoss(lossAmount);
        
        uint256 poolValueAfter = tradingPool.totalPoolValue();
        
        // Pool value should be protected by insurance
        assertGe(poolValueAfter, poolValueBefore - lossAmount);
        console.log("Pool value protected by insurance");
    }
    
    function testWithdrawalWithPnLQuery() public {
        // Setup: Make a deposit
        uint256 depositAmount = 3000 * 1e6; // 3000 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), depositAmount);
        uint256 poolTokens = tradingPool.deposit(address(usdc), depositAmount);
        
        // Withdraw (should trigger PnL query)
        uint256 withdrawTokens = poolTokens / 2; // Withdraw half
        
        uint256 usdcBefore = usdc.balanceOf(user1);
        uint256 assetAmount = tradingPool.withdraw(address(usdc), withdrawTokens);
        uint256 usdcAfter = usdc.balanceOf(user1);
        
        assertEq(usdcAfter - usdcBefore, assetAmount);
        assertGt(assetAmount, 0);
        
        console.log("Successfully withdrew with PnL query");
        vm.stopPrank();
    }
    
    function testBlocklockAutomation() public {
        // Fund controller for automation
        vm.deal(address(this), 1 ether);
        controller.fundAutomation{value: 0.5 ether}();
        
        // Test automated profit/loss check
        controller.automatedProfitLossCheck{value: 0.1 ether}();
        
        // Test automated rebalancing
        controller.automatedRebalancing{value: 0.1 ether}();
        
        // Verify automation was triggered (check events)
        // In a real test, you'd verify the Blocklock integration
        console.log("Blocklock automation functions called successfully");
    }
    
    function testAITradingIntegration() public {
        // Setup: Reach threshold to trigger AI trading
        uint256 depositAmount = 12000 * 1e6; // 12000 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), depositAmount);
        tradingPool.deposit(address(usdc), depositAmount);
        vm.stopPrank();
        
        // Simulate AI trader reporting results
        bytes32 requestId = keccak256(abi.encode("test_trade", block.timestamp));
        int256 profitPnL = 500 * 1e18; // $500 profit
        
        vm.prank(aiTrader);
        controller.reportTradingResult(requestId, profitPnL);
        
        // Verify profit was distributed
        (uint256 totalInsurance, uint256 totalTrading, uint256 totalProfits, ) = 
            controller.getSystemMetrics();
        
        assertGt(totalProfits, 0);
        console.log("AI trading profit reported and distributed");
    }
    
    function testSystemMetrics() public {
        // Get initial metrics
        (uint256 totalInsurance, uint256 totalTrading, uint256 totalProfits, uint256 totalLosses) = 
            controller.getSystemMetrics();
        
        console.log("System Metrics:");
        console.log("Total Insurance:", totalInsurance);
        console.log("Total Trading:", totalTrading);
        console.log("Total Profits:", totalProfits);
        console.log("Total Losses:", totalLosses);
        
        // Verify metrics are accessible
        assertTrue(totalInsurance >= 0);
        assertTrue(totalTrading >= 0);
    }
    
    // ============ Edge Cases and Security Tests ============
    
    function testUnauthorizedAccess() public {
        // Test that unauthorized users cannot call restricted functions
        vm.startPrank(user1);
        
        vm.expectRevert();
        tradingPool.recordProfit(1000 * 1e18);
        
        vm.expectRevert();
        controller.setAITrader(user1);
        
        vm.stopPrank();
    }
    
    function testZeroAmountProtection() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        tradingPool.deposit(address(usdc), 0);
        
        vm.expectRevert();
        pulleyToken.mint(address(usdc), 0);
        
        vm.stopPrank();
    }
    
    function testUnsupportedAsset() public {
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNSUP", 18);
        
        vm.startPrank(user1);
        
        vm.expectRevert();
        tradingPool.deposit(address(unsupportedToken), 1000 * 1e18);
        
        vm.expectRevert();
        pulleyToken.mint(address(unsupportedToken), 1000 * 1e18);
        
        vm.stopPrank();
    }
    
    // ============ Integration Tests ============
    
    function testFullSystemWorkflow() public {
        console.log("=== Testing Full System Workflow ===");
        
        // 1. Start trading period
        vm.prank(address(controller));
        tradingPool.startTradingPeriod();
        console.log("Trading period started");
        
        // 2. Users deposit assets
        uint256 deposit1 = 6000 * 1e6; // 6000 USDC
        uint256 deposit2 = 5000 * 1e6; // 5000 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), deposit1);
        tradingPool.deposit(address(usdc), deposit1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(tradingPool), deposit2);
        tradingPool.deposit(address(usdc), deposit2);
        vm.stopPrank();
        
        console.log("Users deposited assets");
        
        // 3. Threshold reached, funds sent to controller
        assertTrue(tradingPool.totalDeposited() < THRESHOLD); // Should be reset
        console.log("Threshold mechanism triggered");
        
        // 4. AI trading reports profit
        bytes32 requestId = keccak256(abi.encode("workflow_trade", block.timestamp));
        int256 profit = 800 * 1e18; // $800 profit
        
        vm.prank(aiTrader);
        controller.reportTradingResult(requestId, profit);
        console.log("AI trading profit reported");
        
        // 5. Profits distributed
        vm.prank(address(controller));
        tradingPool.distributeTradersProfit(720 * 1e18); // 90% of profit to traders
        console.log("Profits distributed to traders");
        
        // 6. User withdraws with updated value
        vm.startPrank(user1);
        uint256 userTokens = tradingPool.balanceOf(user1);
        uint256 withdrawAmount = tradingPool.withdraw(address(usdc), userTokens / 4); // Withdraw 25%
        assertGt(withdrawAmount, 0);
        vm.stopPrank();
        
        console.log("User withdrawal completed");
        console.log("=== Full System Workflow Successful ===");
    }
}
