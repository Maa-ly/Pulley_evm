//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {PulleyController} from "../src/PulleyController.sol";
import {PulTradingPool} from "../src/Pool/PuLTradingPool.sol";
import {PulleyToken} from "../src/Token/PulleyToken.sol";
import {Wallet} from "../src/wallet.sol";
import {PermissionManager} from "../src/PermissionManager.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {MockSToken} from "../src/mocks/MockSToken.sol";
import {Events} from "../src/libraries/Events.sol";

/**
 * @title PulleyIntegrationTest
 * @notice Comprehensive integration tests for the complete Pulley Protocol
 * @dev Tests end-to-end flows, cross-contract interactions, and system behavior
 */
contract PulleyIntegrationTest is Test {
    
    // ============ Core Contracts ============
    PulleyController public controller;
    PulTradingPool public tradingPool;
    PulleyToken public pulleyToken;
    Wallet public wallet;
    PermissionManager public permissionManager;
    
    // ============ Mock Assets ============
    MockUSDC public usdc;
    MockUSDT public usdt;
    MockSToken public sToken;
    
    // ============ Test Addresses ============
    address public deployer;
    address public user1;
    address public user2;
    address public user3;
    address public aiTrader;
    
    // ============ Test Constants ============
    uint256 public constant DEPOSIT_AMOUNT = 5000 * 1e6;
    uint256 public constant THRESHOLD = 10000 * 1e18;
    uint256 public constant LARGE_DEPOSIT = 15000 * 1e6;
    
    function setUp() public {
        deployer = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        aiTrader = makeAddr("aiTrader");
        
        // Deploy mock assets
        usdc = new MockUSDC();
        usdt = new MockUSDT();
        sToken = new MockSToken();
        
        // Mint tokens to users
        usdc.mint(user1, 100000 * 1e6);
        usdc.mint(user2, 100000 * 1e6);
        usdc.mint(user3, 100000 * 1e6);
        
        usdt.mint(user1, 100000 * 1e6);
        usdt.mint(user2, 100000 * 1e6);
        usdt.mint(user3, 100000 * 1e6);
        
        sToken.mint(user1, 100000 * 1e18);
        sToken.mint(user2, 100000 * 1e18);
        sToken.mint(user3, 100000 * 1e18);
        
        _deployAndConfigure();
    }
    
    function _deployAndConfigure() internal {
        // Deploy permission manager
        permissionManager = new PermissionManager();
        
        // Deploy wallet
        wallet = new Wallet();
        
        // Prepare supported assets
        address[] memory supportedAssets = new address[](3);
        supportedAssets[0] = address(usdc);
        supportedAssets[1] = address(usdt);
        supportedAssets[2] = address(sToken);
        
        // Deploy PulleyToken
        pulleyToken = new PulleyToken(
            "Pulley Token",
            "PUL",
            address(permissionManager),
            supportedAssets
        );
        
        // Deploy trading pool first
        tradingPool = new PulTradingPool();
        
        // Deploy controller
        controller = new PulleyController();
        controller.initialize(
            address(permissionManager),
            address(tradingPool), // Set trading pool directly
            address(0), // No insurance pool
            address(pulleyToken),
            aiTrader,
            supportedAssets
        );
        
        // Initialize trading pool
        tradingPool.initialize(
            "Pulley Trading Pool",
            "PTP",
            address(permissionManager),
            address(controller), // Set controller directly
            address(pulleyToken)
        );
        
        // Set up contract references
        pulleyToken.setContracts(address(0), address(controller), address(tradingPool));
        
        // Set AI wallet in controller
        controller.setAIWallet(payable(address(wallet)));
        
        // Initialize wallet
        wallet.initialize(address(controller), address(controller));
        
        // Add assets to trading pool
        tradingPool.addAsset(address(usdc), 6, THRESHOLD, address(0));
        tradingPool.addAsset(address(usdt), 6, THRESHOLD, address(0));
        tradingPool.addAsset(address(sToken), 18, THRESHOLD, address(0));
        
        // Set up permissions
        permissionManager.grantPermission(address(controller), PulTradingPool.recordProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordLoss.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.distributePeriodProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordPeriodLoss.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.distributeInsuranceRefund.selector);
        permissionManager.grantPermission(address(tradingPool), PulleyController.receiveFunds.selector);
        permissionManager.grantPermission(aiTrader, PulleyController.checkAIWalletPnL.selector);
        permissionManager.grantPermission(address(controller), PulleyToken.updateUtilization.selector);
        permissionManager.grantPermission(address(controller), PulleyToken.coverLoss.selector);
        permissionManager.grantPermission(address(controller), PulleyToken.addProfits.selector);
    }
    
    // ============ Complete Trading Flow Tests ============
    
    function testCompleteTradingFlowWithProfit() public {
        console.log("=== Testing Complete Trading Flow with Profit ===");
        
        // 1. Users deposit to trading pool
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 user1Tokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 user2Tokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        console.log("User1 pool tokens:", user1Tokens);
        console.log("User2 pool tokens:", user2Tokens);
        
        // 2. Check that funds are in trading pool
        assertEq(usdc.balanceOf(address(tradingPool)), DEPOSIT_AMOUNT * 2);
        assertEq(tradingPool.totalSupply(), user1Tokens + user2Tokens);
        
        // 3. Simulate threshold reached and funds sent to controller
        // (In real scenario, this would happen when threshold is reached)
        usdc.mint(address(controller), DEPOSIT_AMOUNT * 2);
        usdc.approve(address(controller), DEPOSIT_AMOUNT * 2);
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT * 2);
        
        // 4. Check allocations
        (uint256 insurance, uint256 trading) = controller.getFundAllocation(address(usdc));
        uint256 expectedInsurance = (DEPOSIT_AMOUNT * 2 * 15) / 100;
        uint256 expectedTrading = (DEPOSIT_AMOUNT * 2 * 85) / 100;
        
        assertEq(insurance, expectedInsurance);
        assertEq(trading, expectedTrading);
        
        console.log("Insurance allocation:", insurance);
        console.log("Trading allocation:", trading);
        
        // 5. Check that PulleyToken was minted for insurance
        assertGt(pulleyToken.balanceOf(address(controller)), 0);
        
        // 6. Check that funds were sent to AI wallet
        assertEq(usdc.balanceOf(address(wallet)), expectedTrading);
        
        // 7. Simulate AI trading profit
        usdc.mint(address(wallet), 1000 * 1e6); // 1000 USDC profit
        
        // 8. Check AI wallet PnL
        vm.prank(aiTrader);
        (int256 pnl, bool fundsSent) = controller.checkAIWalletPnL(address(usdc));
        
        assertEq(pnl, 1000 * 1e6);
        assertTrue(fundsSent);
        
        // 9. Check that profits were distributed
        (uint256 totalInsurance, uint256 totalTrading, uint256 profits, uint256 losses) = 
            controller.getSystemMetrics();
        
        assertGt(profits, 0);
        
        console.log("Total profits:", profits);
        console.log("Total losses:", losses);
    }
    
    function testCompleteTradingFlowWithLoss() public {
        console.log("=== Testing Complete Trading Flow with Loss ===");
        
        // 1. Users deposit to trading pool
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 user1Tokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 user2Tokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // 2. Send funds to controller
        usdc.mint(address(controller), DEPOSIT_AMOUNT * 2);
        usdc.approve(address(controller), DEPOSIT_AMOUNT * 2);
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT * 2);
        
        // 3. Send funds to AI wallet
        uint256 tradingAmount = (DEPOSIT_AMOUNT * 2 * 85) / 100;
        assertEq(usdc.balanceOf(address(wallet)), tradingAmount);
        
        // 4. Simulate AI trading loss
        usdc.transfer(address(0xdead), 500 * 1e6); // 500 USDC loss
        
        // 5. Check AI wallet PnL
        vm.prank(aiTrader);
        (int256 pnl, bool fundsSent) = controller.checkAIWalletPnL(address(usdc));
        
        assertEq(pnl, -500 * 1e6);
        assertFalse(fundsSent);
        
        // 6. Check that loss was recorded
        (uint256 totalInsurance, uint256 totalTrading, uint256 profits, uint256 losses) = 
            controller.getSystemMetrics();
        
        assertGt(losses, 0);
        
        console.log("Total losses:", losses);
    }
    
    function testMultipleAssetsTradingFlow() public {
        console.log("=== Testing Multiple Assets Trading Flow ===");
        
        // 1. Users deposit different assets
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 usdcTokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        
        usdt.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 usdtTokens = tradingPool.deposit(address(usdt), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(user2);
        sToken.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 sTokenTokens = tradingPool.deposit(address(sToken), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // 2. Send funds to controller for each asset
        usdc.mint(address(controller), DEPOSIT_AMOUNT);
        usdc.approve(address(controller), DEPOSIT_AMOUNT);
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        
        usdt.mint(address(controller), DEPOSIT_AMOUNT);
        usdt.approve(address(controller), DEPOSIT_AMOUNT);
        controller.receiveFunds(address(usdt), DEPOSIT_AMOUNT);
        
        sToken.mint(address(controller), DEPOSIT_AMOUNT);
        sToken.approve(address(controller), DEPOSIT_AMOUNT);
        controller.receiveFunds(address(sToken), DEPOSIT_AMOUNT);
        
        // 3. Check that all assets were allocated
        (uint256 usdcInsurance, uint256 usdcTrading) = controller.getFundAllocation(address(usdc));
        (uint256 usdtInsurance, uint256 usdtTrading) = controller.getFundAllocation(address(usdt));
        (uint256 sTokenInsurance, uint256 sTokenTrading) = controller.getFundAllocation(address(sToken));
        
        assertGt(usdcInsurance, 0);
        assertGt(usdcTrading, 0);
        assertGt(usdtInsurance, 0);
        assertGt(usdtTrading, 0);
        assertGt(sTokenInsurance, 0);
        assertGt(sTokenTrading, 0);
        
        console.log("USDC insurance:", usdcInsurance, "trading:", usdcTrading);
        console.log("USDT insurance:", usdtInsurance, "trading:", usdtTrading);
        console.log("sToken insurance:", sTokenInsurance, "trading:", sTokenTrading);
    }
    
    // ============ PulleyToken Integration Tests ============
    
    function testPulleyTokenGrowthIntegration() public {
        console.log("=== Testing PulleyToken Growth Integration ===");
        
        // 1. Mint some PulleyTokens
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), LARGE_DEPOSIT);
        uint256 tokensMinted = pulleyToken.mint(address(usdc), LARGE_DEPOSIT);
        vm.stopPrank();
        
        console.log("Tokens minted:", tokensMinted);
        
        // 2. Set utilization rate
        vm.prank(address(controller));
        pulleyToken.updateUtilization(5000); // 50% utilization
        
        // 3. Fast forward time to trigger growth
        vm.warp(block.timestamp + 1 days);
        
        // 4. Update growth
        pulleyToken.updateGrowth();
        
        // 5. Check growth metrics
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        
        assertGt(currentPrice, 1e18); // Price should increase
        assertGt(reserve, 0); // Reserve should have grown
        assertEq(currentUtilization, 5000);
        
        console.log("Current price:", currentPrice);
        console.log("Growth rate:", currentGrowthRate);
        console.log("Reserve:", reserve);
    }
    
    function testPulleyTokenLossCoverageIntegration() public {
        console.log("=== Testing PulleyToken Loss Coverage Integration ===");
        
        // 1. First create some insurance reserve
        usdc.approve(address(pulleyToken), LARGE_DEPOSIT);
        vm.prank(address(controller));
        uint256 tokensMinted = pulleyToken.mint(address(usdc), LARGE_DEPOSIT);
        
        // 2. Check initial reserve
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertEq(reserve, tokensMinted);
        
        // 3. Cover a loss
        uint256 lossAmount = 100 * 1e18;
        vm.prank(address(controller));
        pulleyToken.coverLoss(lossAmount);
        
        // 4. Check that reserve decreased
        (currentPrice, currentGrowthRate, currentUtilization, reserve) = 
            pulleyToken.getGrowthMetrics();
        assertEq(reserve, tokensMinted - lossAmount);
        
        console.log("Initial reserve:", tokensMinted);
        console.log("Loss amount:", lossAmount);
        console.log("Final reserve:", reserve);
    }
    
    // ============ Trading Pool Integration Tests ============
    
    function testTradingPoolPeriodManagement() public {
        console.log("=== Testing Trading Pool Period Management ===");
        
        // 1. Users deposit to create periods
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // 2. Check that periods were created
        assertEq(tradingPool.assetCurrentPeriodId(address(usdc)), 1);
        
        // 3. Get period info
        (uint256 startTime, uint256 endTime, uint256 totalContributions, bool isActive, int256 pnl) = 
            tradingPool.getPeriodInfo(address(usdc), 1);
        
        assertGt(startTime, 0);
        assertEq(endTime, 0); // Not ended yet
        assertEq(totalContributions, DEPOSIT_AMOUNT * 2);
        assertTrue(isActive);
        assertEq(pnl, 0);
        
        console.log("Period start time:", startTime);
        console.log("Total contributions:", totalContributions);
        console.log("Is active:", isActive);
    }
    
    function testTradingPoolProfitDistribution() public {
        console.log("=== Testing Trading Pool Profit Distribution ===");
        
        // 1. Create a period
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // 2. Distribute profit
        uint256 profitAmount = 1000 * 1e18;
        vm.prank(address(controller));
        tradingPool.distributePeriodProfit(address(usdc), profitAmount, 1);
        
        // 3. Check that period was ended
        (uint256 startTime, uint256 endTime, uint256 totalContributions, bool isActive, int256 pnl) = 
            tradingPool.getPeriodInfo(address(usdc), 1);
        
        assertGt(endTime, 0);
        assertFalse(isActive);
        assertEq(pnl, int256(profitAmount));
        
        console.log("Period end time:", endTime);
        console.log("Period PnL:", pnl);
    }
    
    function testTradingPoolInsuranceRefund() public {
        console.log("=== Testing Trading Pool Insurance Refund ===");
        
        // 1. Create a period
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // 2. Distribute insurance refund
        uint256 refundAmount = 150 * 1e18; // 15% of deposit
        vm.prank(address(controller));
        tradingPool.distributeInsuranceRefund(address(usdc), refundAmount);
        
        // 3. Check that refund was recorded
        assertEq(tradingPool.totalInsuranceRefunds(), refundAmount);
        
        console.log("Insurance refund amount:", refundAmount);
    }
    
    // ============ Wallet Integration Tests ============
    
    function testWalletTradingSessionIntegration() public {
        console.log("=== Testing Wallet Trading Session Integration ===");
        
        // 1. Send funds to wallet
        usdc.mint(address(controller), DEPOSIT_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), DEPOSIT_AMOUNT);
        
        // 2. Check session info
        (uint256 sessionId, uint256 initialBalance, uint256 currentBalance, int256 pnl) = 
            wallet.getSessionInfo(address(usdc));
        
        assertEq(sessionId, 1);
        assertEq(initialBalance, DEPOSIT_AMOUNT);
        assertEq(currentBalance, DEPOSIT_AMOUNT);
        assertEq(pnl, 0);
        
        // 3. Simulate trading profit
        usdc.mint(address(wallet), 500 * 1e6);
        
        // 4. Check updated PnL
        pnl = wallet.getCurrentPnL(address(usdc));
        assertEq(pnl, 500 * 1e6);
        
        console.log("Session ID:", sessionId);
        console.log("Initial balance:", initialBalance);
        console.log("Current balance:", currentBalance);
        console.log("PnL:", pnl);
    }
    
    // ============ System Stress Tests ============
    
    function testSystemWithMultipleUsers() public {
        console.log("=== Testing System with Multiple Users ===");
        
        uint256 depositAmount = 2000 * 1e6;
        
        // 1. Multiple users deposit
        for (uint256 i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            usdc.mint(user, 100000 * 1e6);
            
            vm.startPrank(user);
            usdc.approve(address(tradingPool), depositAmount);
            tradingPool.deposit(address(usdc), depositAmount);
            vm.stopPrank();
        }
        
        // 2. Check total pool value
        (uint256 totalValue, uint256 deposited, uint256 profits, uint256 losses, uint256 threshold) = 
            tradingPool.getPoolMetrics();
        
        assertEq(deposited, depositAmount * 5);
        assertEq(totalValue, depositAmount * 5);
        
        console.log("Total deposits:", deposited);
        console.log("Total pool value:", totalValue);
        console.log("Number of users: 5");
    }
    
    function testSystemWithLargeAmounts() public {
        console.log("=== Testing System with Large Amounts ===");
        
        uint256 largeAmount = 100000 * 1e6; // 100k USDC
        
        // 1. User deposits large amount
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), largeAmount);
        uint256 poolTokens = tradingPool.deposit(address(usdc), largeAmount);
        vm.stopPrank();
        
        // 2. Send to controller
        usdc.mint(address(controller), largeAmount);
        usdc.approve(address(controller), largeAmount);
        controller.receiveFunds(address(usdc), largeAmount);
        
        // 3. Check allocations
        (uint256 insurance, uint256 trading) = controller.getFundAllocation(address(usdc));
        uint256 expectedInsurance = (largeAmount * 15) / 100;
        uint256 expectedTrading = (largeAmount * 85) / 100;
        
        assertEq(insurance, expectedInsurance);
        assertEq(trading, expectedTrading);
        
        console.log("Large amount:", largeAmount);
        console.log("Insurance allocation:", insurance);
        console.log("Trading allocation:", trading);
    }
    
    // ============ Error Recovery Tests ============
    
    function testSystemRecoveryAfterError() public {
        console.log("=== Testing System Recovery After Error ===");
        
        // 1. Normal deposit
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // 2. Simulate error by trying invalid operation
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.deposit(address(usdc), 0); // Zero amount should fail
        vm.stopPrank();
        
        // 3. System should still work after error
        vm.startPrank(user2);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // 4. Check that system is still functional
        (uint256 totalValue, uint256 deposited, uint256 profits, uint256 losses, uint256 threshold) = 
            tradingPool.getPoolMetrics();
        
        assertEq(deposited, DEPOSIT_AMOUNT * 2);
        assertEq(totalValue, DEPOSIT_AMOUNT * 2);
        
        console.log("System recovered successfully");
        console.log("Total deposits after recovery:", deposited);
    }
    
    // ============ Gas Usage Tests ============
    
    function testGasUsageCompleteFlow() public {
        console.log("=== Testing Gas Usage for Complete Flow ===");
        
        // 1. Deposit
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        
        uint256 gasStart = gasleft();
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        uint256 depositGas = gasStart - gasleft();
        vm.stopPrank();
        
        // 2. Send to controller
        usdc.mint(address(controller), DEPOSIT_AMOUNT);
        usdc.approve(address(controller), DEPOSIT_AMOUNT);
        
        gasStart = gasleft();
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        uint256 controllerGas = gasStart - gasleft();
        
        // 3. Check AI wallet PnL
        gasStart = gasleft();
        vm.prank(aiTrader);
        controller.checkAIWalletPnL(address(usdc));
        uint256 pnlCheckGas = gasStart - gasleft();
        
        console.log("Deposit gas:", depositGas);
        console.log("Controller receive funds gas:", controllerGas);
        console.log("PnL check gas:", pnlCheckGas);
        console.log("Total gas:", depositGas + controllerGas + pnlCheckGas);
        
        // Assert reasonable gas usage
        assertLt(depositGas, 200000);
        assertLt(controllerGas, 300000);
        assertLt(pnlCheckGas, 200000);
    }
    
    // ============ Edge Cases Tests ============
    
    function testSystemWithZeroAmounts() public {
        console.log("=== Testing System with Zero Amounts ===");
        
        // All zero amount operations should fail gracefully
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), 0);
        
        vm.expectRevert();
        tradingPool.deposit(address(usdc), 0);
        
        vm.expectRevert();
        tradingPool.withdraw(address(usdc), 0);
        vm.stopPrank();
        
        vm.expectRevert();
        controller.receiveFunds(address(usdc), 0);
        
        console.log("Zero amount operations properly rejected");
    }
    
    function testSystemWithUnsupportedAssets() public {
        console.log("=== Testing System with Unsupported Assets ===");
        
        address unsupportedAsset = makeAddr("unsupported");
        
        // All operations with unsupported assets should fail
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.deposit(unsupportedAsset, DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.expectRevert();
        controller.receiveFunds(unsupportedAsset, DEPOSIT_AMOUNT);
        
        console.log("Unsupported asset operations properly rejected");
    }
}
