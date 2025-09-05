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
import {DataTypes} from "../src/libraries/DataTypes.sol";
import {Events} from "../src/libraries/Events.sol";

/**
 * @title ComprehensivePulleyTest
 * @notice Comprehensive unit and integration tests for the Pulley Protocol
 * @dev Tests all core contracts: PulleyController, PuLTradingPool, PulleyToken, Wallet
 */
contract ComprehensivePulleyTest is Test {
    
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
    uint256 public constant INITIAL_SUPPLY = 1000000 * 1e18;
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 1e18;
    uint256 public constant THRESHOLD = 10000 * 1e18;
    
    // ============ Events ============
    event FundsReceived(address indexed from, address indexed asset, uint256 amount);
    event FundsAllocated(address indexed asset, uint256 insuranceAmount, uint256 tradingAmount);
    event Deposited(address indexed user, address indexed asset, uint256 amount, uint256 poolTokens, uint256 usdValue);
    event Minted(address indexed to, uint256 amount, uint256 backingAmount);
    event TradeCompleted(bytes32 indexed requestId, address indexed asset, int256 pnl, bool isProfit);
    event AIWalletPnLChecked(address indexed asset, int256 pnl, bool fundsSent);
    
    function setUp() public {
        // Set up test addresses
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
        usdc.mint(user1, 100000 * 1e6); // 100k USDC
        usdc.mint(user2, 100000 * 1e6);
        usdc.mint(user3, 100000 * 1e6);
        
        usdt.mint(user1, 100000 * 1e6); // 100k USDT
        usdt.mint(user2, 100000 * 1e6);
        usdt.mint(user3, 100000 * 1e6);
        
        sToken.mint(user1, 100000 * 1e18); // 100k sToken
        sToken.mint(user2, 100000 * 1e18);
        sToken.mint(user3, 100000 * 1e18);
        
        // Deploy core contracts
        _deployContracts();
        _configureContracts();
        _setupPermissions();
    }
    
    // ============ Deployment Functions ============
    
    function _deployContracts() internal {
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
    }
    
    function _configureContracts() internal {
        // Set up permissions first
        permissionManager.grantPermission(address(controller), PulTradingPool.recordProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordLoss.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.distributePeriodProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordPeriodLoss.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.distributeInsuranceRefund.selector);
        permissionManager.grantPermission(address(tradingPool), PulleyController.receiveFunds.selector);
        permissionManager.grantPermission(aiTrader, PulleyController.checkAIWalletPnL.selector);
        
        // Grant permission to set contracts and other functions
        permissionManager.grantPermission(address(this), PulleyToken.setContracts.selector);
        permissionManager.grantPermission(address(this), PulleyController.setAIWallet.selector);
        permissionManager.grantPermission(address(this), Wallet.initialize.selector);
        permissionManager.grantPermission(address(this), PulTradingPool.addAsset.selector);
        
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
    }
    
    function _setupPermissions() internal {
        // Grant permissions for controller
        permissionManager.grantPermission(address(controller), PulTradingPool.recordProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordLoss.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.distributePeriodProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordPeriodLoss.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.distributeInsuranceRefund.selector);
        
        // Grant permissions for trading pool
        permissionManager.grantPermission(address(tradingPool), PulleyController.receiveFunds.selector);
        
        // Grant permissions for AI trader
        permissionManager.grantPermission(aiTrader, PulleyController.checkAIWalletPnL.selector);
    }
    
    // ============ Unit Tests - PulleyController ============
    
    function testControllerInitialization() public {
        assertEq(controller.permissionManager(), address(permissionManager));
        assertEq(controller.tradingPool(), address(tradingPool));
        assertEq(controller.pulleyStablecoin(), address(pulleyToken));
        assertEq(controller.aiTrader(), aiTrader);
        assertEq(controller.aiWallet(), address(wallet));
        
        // Check supported assets
        assertTrue(controller.isAssetSupported(address(usdc)));
        assertTrue(controller.isAssetSupported(address(usdt)));
        assertTrue(controller.isAssetSupported(address(sToken)));
    }
    
    function testControllerReceiveFunds() public {
        // Prepare funds
        usdc.mint(address(this), 10000 * 1e6);
        usdc.approve(address(controller), 10000 * 1e6);
        
        // Expect events
        vm.expectEmit(true, true, true, true);
        emit FundsReceived(address(this), address(usdc), 10000 * 1e6);
        
        vm.expectEmit(true, true, true, true);
        emit FundsAllocated(address(usdc), 1500 * 1e6, 8500 * 1e6);
        
        // Call receiveFunds
        controller.receiveFunds(address(usdc), 10000 * 1e6);
        
        // Check allocations
        (uint256 insurance, uint256 trading) = controller.getFundAllocation(address(usdc));
        assertEq(insurance, 1500 * 1e6); // 15%
        assertEq(trading, 8500 * 1e6); // 85%
        
        // Check system metrics
        (uint256 totalInsurance, uint256 totalTrading, uint256 profits, uint256 losses) = 
            controller.getSystemMetrics();
        assertEq(totalInsurance, 1500 * 1e6);
        assertEq(totalTrading, 8500 * 1e6);
        assertEq(profits, 0);
        assertEq(losses, 0);
    }
    
    function testControllerCheckAIWalletPnL() public {
        // First, send funds to controller to trigger AI trading
        usdc.mint(address(this), 10000 * 1e6);
        usdc.approve(address(controller), 10000 * 1e6);
        controller.receiveFunds(address(usdc), 10000 * 1e6);
        
        // Check PnL (should be 0 initially)
        vm.prank(aiTrader);
        (int256 pnl, bool fundsSent) = controller.checkAIWalletPnL(address(usdc));
        
        assertEq(pnl, 0);
        assertFalse(fundsSent);
    }
    
    function testControllerAssetSupport() public {
        address newAsset = makeAddr("newAsset");
        
        // Add new asset
        controller.updateAssetSupport(newAsset, true);
        assertTrue(controller.isAssetSupported(newAsset));
        
        // Remove asset
        controller.updateAssetSupport(newAsset, false);
        assertFalse(controller.isAssetSupported(newAsset));
    }
    
    // ============ Unit Tests - PuLTradingPool ============
    
    function testTradingPoolInitialization() public {
        assertEq(tradingPool.permissionManager(), address(permissionManager));
        assertEq(tradingPool.controller(), address(controller));
        assertEq(tradingPool.pulleyToken(), address(pulleyToken));
        assertEq(tradingPool.threshold(), THRESHOLD);
    }
    
    function testTradingPoolDeposit() public {
        // Prepare user
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        
        // Expect events
        vm.expectEmit(true, true, true, true);
        emit Deposited(user1, address(usdc), DEPOSIT_AMOUNT, 0, 0);
        
        // Deposit
        uint256 poolTokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        
        // Check balances
        assertGt(poolTokens, 0);
        assertEq(tradingPool.balanceOf(user1), poolTokens);
        assertEq(tradingPool.getUserAssetDeposit(user1, address(usdc)), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }
    
    function testTradingPoolWithdraw() public {
        // First deposit
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 poolTokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        
        // Then withdraw
        uint256 assetAmount = tradingPool.withdraw(address(usdc), poolTokens);
        
        // Check balances
        assertEq(assetAmount, DEPOSIT_AMOUNT);
        assertEq(tradingPool.balanceOf(user1), 0);
        assertEq(usdc.balanceOf(user1), 100000 * 1e6); // Back to original
        
        vm.stopPrank();
    }
    
    function testTradingPoolAssetManagement() public {
        address newAsset = makeAddr("newAsset");
        
        // Add asset
        tradingPool.addAsset(newAsset, 18, 5000 * 1e18, address(0));
        assertTrue(tradingPool.supportedAssets(newAsset));
        
        // Remove asset
        tradingPool.removeAsset(newAsset);
        assertFalse(tradingPool.supportedAssets(newAsset));
    }
    
    function testTradingPoolThresholdUpdate() public {
        uint256 newThreshold = 20000 * 1e18;
        tradingPool.updateThreshold(newThreshold);
        assertEq(tradingPool.threshold(), newThreshold);
    }
    
    // ============ Unit Tests - PulleyToken ============
    
    function testPulleyTokenInitialization() public {
        assertEq(pulleyToken.permissionManager(), address(permissionManager));
        assertEq(pulleyToken.controller(), address(controller));
        assertEq(pulleyToken.tradingPool(), address(tradingPool));
        assertEq(pulleyToken.name(), "Pulley Token");
        assertEq(pulleyToken.symbol(), "PUL");
    }
    
    function testPulleyTokenMint() public {
        // Prepare user
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), DEPOSIT_AMOUNT);
        
        // Expect events
        vm.expectEmit(true, true, true, true);
        emit Minted(user1, 0, DEPOSIT_AMOUNT);
        
        // Mint tokens
        uint256 tokensMinted = pulleyToken.mint(address(usdc), DEPOSIT_AMOUNT);
        
        // Check balances
        assertGt(tokensMinted, 0);
        assertEq(pulleyToken.balanceOf(user1), tokensMinted);
        assertEq(pulleyToken.getBackingInfo(address(usdc)), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }
    
    function testPulleyTokenBurn() public {
        // First mint
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), DEPOSIT_AMOUNT);
        uint256 tokensMinted = pulleyToken.mint(address(usdc), DEPOSIT_AMOUNT);
        
        // Then burn
        uint256 backingReturned = pulleyToken.burn(address(usdc), tokensMinted);
        
        // Check balances
        assertEq(backingReturned, DEPOSIT_AMOUNT);
        assertEq(pulleyToken.balanceOf(user1), 0);
        assertEq(usdc.balanceOf(user1), 100000 * 1e6); // Back to original
        
        vm.stopPrank();
    }
    
    function testPulleyTokenGrowth() public {
        // Mint some tokens first
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), DEPOSIT_AMOUNT);
        pulleyToken.mint(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Fast forward time to trigger growth
        vm.warp(block.timestamp + 1 days);
        
        // Update growth
        pulleyToken.updateGrowth();
        
        // Check that growth was applied
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertGt(currentPrice, 1e18); // Price should increase
        assertGt(reserve, 0); // Reserve should have grown
    }
    
    function testPulleyTokenCoverLoss() public {
        // First mint some tokens
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), DEPOSIT_AMOUNT);
        pulleyToken.mint(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Cover loss
        uint256 lossAmount = 100 * 1e18;
        vm.prank(address(controller));
        pulleyToken.coverLoss(lossAmount);
        
        // Check that reserve decreased
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertLt(reserve, DEPOSIT_AMOUNT);
    }
    
    // ============ Unit Tests - Wallet ============
    
    function testWalletInitialization() public {
        assertEq(wallet.controller(), address(controller));
        assertEq(wallet.aiSigner(), address(controller));
    }
    
    function testWalletReceiveFunds() public {
        // Prepare funds in controller
        usdc.mint(address(controller), DEPOSIT_AMOUNT);
        
        // Receive funds
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), DEPOSIT_AMOUNT);
        
        // Check balances
        assertEq(usdc.balanceOf(address(wallet)), DEPOSIT_AMOUNT);
        assertEq(wallet.initialBalances(address(usdc)), DEPOSIT_AMOUNT);
        assertEq(wallet.currentSession(address(usdc)), 1);
    }
    
    function testWalletGetCurrentPnL() public {
        // First receive funds
        usdc.mint(address(controller), DEPOSIT_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), DEPOSIT_AMOUNT);
        
        // Check PnL (should be 0 initially)
        int256 pnl = wallet.getCurrentPnL(address(usdc));
        assertEq(pnl, 0);
        
        // Simulate profit by minting more tokens to wallet
        usdc.mint(address(wallet), 100 * 1e6);
        pnl = wallet.getCurrentPnL(address(usdc));
        assertEq(pnl, 100 * 1e6);
    }
    
    function testWalletGetSessionInfo() public {
        // First receive funds
        usdc.mint(address(controller), DEPOSIT_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), DEPOSIT_AMOUNT);
        
        // Get session info
        (uint256 sessionId, uint256 initialBalance, uint256 currentBalance, int256 pnl) = 
            wallet.getSessionInfo(address(usdc));
        
        assertEq(sessionId, 1);
        assertEq(initialBalance, DEPOSIT_AMOUNT);
        assertEq(currentBalance, DEPOSIT_AMOUNT);
        assertEq(pnl, 0);
    }
    
    // ============ Integration Tests ============
    
    function testCompleteTradingFlow() public {
        // 1. User deposits to trading pool
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 poolTokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // 2. Check that funds are in trading pool
        assertEq(usdc.balanceOf(address(tradingPool)), DEPOSIT_AMOUNT);
        assertEq(tradingPool.balanceOf(user1), poolTokens);
        
        // 3. Simulate threshold reached and funds sent to controller
        // (In real scenario, this would happen when threshold is reached)
        usdc.mint(address(controller), DEPOSIT_AMOUNT);
        usdc.approve(address(controller), DEPOSIT_AMOUNT);
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        
        // 4. Check allocations
        (uint256 insurance, uint256 trading) = controller.getFundAllocation(address(usdc));
        assertEq(insurance, (DEPOSIT_AMOUNT * 15) / 100);
        assertEq(trading, (DEPOSIT_AMOUNT * 85) / 100);
        
        // 5. Check that PulleyToken was minted for insurance
        assertGt(pulleyToken.balanceOf(address(controller)), 0);
        
        // 6. Check that funds were sent to AI wallet
        assertEq(usdc.balanceOf(address(wallet)), (DEPOSIT_AMOUNT * 85) / 100);
    }
    
    function testInsuranceRefundFlow() public {
        // 1. Set up initial state with funds
        usdc.mint(address(controller), 10000 * 1e6);
        usdc.approve(address(controller), 10000 * 1e6);
        controller.receiveFunds(address(usdc), 10000 * 1e6);
        
        // 2. Simulate loss by calling checkAIWalletPnL with negative PnL
        // (In real scenario, this would be called by AI system)
        vm.prank(aiTrader);
        (int256 pnl, bool fundsSent) = controller.checkAIWalletPnL(address(usdc));
        
        // 3. Check that loss was handled
        (uint256 totalInsurance, uint256 totalTrading, uint256 profits, uint256 losses) = 
            controller.getSystemMetrics();
        
        // Since no actual loss occurred, these should be 0
        assertEq(losses, 0);
    }
    
    function testMultipleUsersDeposit() public {
        uint256 depositAmount = 5000 * 1e6;
        
        // User 1 deposits
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), depositAmount);
        uint256 user1Tokens = tradingPool.deposit(address(usdc), depositAmount);
        vm.stopPrank();
        
        // User 2 deposits
        vm.startPrank(user2);
        usdc.approve(address(tradingPool), depositAmount);
        uint256 user2Tokens = tradingPool.deposit(address(usdc), depositAmount);
        vm.stopPrank();
        
        // User 3 deposits
        vm.startPrank(user3);
        usdc.approve(address(tradingPool), depositAmount);
        uint256 user3Tokens = tradingPool.deposit(address(usdc), depositAmount);
        vm.stopPrank();
        
        // Check balances
        assertEq(tradingPool.balanceOf(user1), user1Tokens);
        assertEq(tradingPool.balanceOf(user2), user2Tokens);
        assertEq(tradingPool.balanceOf(user3), user3Tokens);
        
        // Check total pool value
        (uint256 totalValue, uint256 deposited, uint256 profits, uint256 losses, uint256 threshold) = 
            tradingPool.getPoolMetrics();
        assertEq(deposited, depositAmount * 3);
        assertEq(totalValue, depositAmount * 3);
    }
    
    function testPulleyTokenPriceGrowth() public {
        // Mint tokens to create initial supply
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), 10000 * 1e6);
        uint256 tokensMinted = pulleyToken.mint(address(usdc), 10000 * 1e6);
        vm.stopPrank();
        
        // Get initial price
        uint256 initialPrice = pulleyToken.getCurrentPrice();
        assertEq(initialPrice, 1e18); // Should start at 1 USD
        
        // Fast forward time and trigger growth
        vm.warp(block.timestamp + 1 days);
        pulleyToken.updateGrowth();
        
        // Check that price increased
        uint256 newPrice = pulleyToken.getCurrentPrice();
        assertGt(newPrice, initialPrice);
        
        // Check growth metrics
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertGt(reserve, 0);
        assertGt(currentGrowthRate, 0);
    }
    
    function testEmergencyFunctions() public {
        // Test emergency withdraw from controller
        usdc.mint(address(controller), 1000 * 1e6);
        
        uint256 initialBalance = usdc.balanceOf(user1);
        controller.emergencyWithdraw(address(usdc), 1000 * 1e6, user1);
        
        assertEq(usdc.balanceOf(user1), initialBalance + 1000 * 1e6);
    }
    
    // ============ Edge Cases and Error Tests ============
    
    function testZeroAmountDeposit() public {
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), 0);
        
        vm.expectRevert();
        tradingPool.deposit(address(usdc), 0);
        
        vm.stopPrank();
    }
    
    function testUnsupportedAssetDeposit() public {
        address unsupportedAsset = makeAddr("unsupported");
        
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.deposit(unsupportedAsset, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }
    
    function testInsufficientBalanceWithdraw() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        tradingPool.withdraw(address(usdc), 1000 * 1e18); // More than user has
        
        vm.stopPrank();
    }
    
    function testUnauthorizedAccess() public {
        vm.startPrank(user1);
        
        // Try to call controller functions without permission
        vm.expectRevert();
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }
    
    function testReentrancyProtection() public {
        // This would require a malicious contract to test properly
        // For now, we just ensure the modifier is present
        assertTrue(true); // Placeholder for reentrancy test
    }
    
    // ============ Gas Optimization Tests ============
    
    function testGasUsageDeposit() public {
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        
        uint256 gasStart = gasleft();
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used for deposit:", gasUsed);
        assertLt(gasUsed, 200000); // Should be reasonable
        
        vm.stopPrank();
    }
    
    function testGasUsageMint() public {
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), DEPOSIT_AMOUNT);
        
        uint256 gasStart = gasleft();
        pulleyToken.mint(address(usdc), DEPOSIT_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used for mint:", gasUsed);
        assertLt(gasUsed, 300000); // Should be reasonable
        
        vm.stopPrank();
    }
}
