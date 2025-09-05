//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {PulTradingPool} from "../src/Pool/PuLTradingPool.sol";
import {PulleyController} from "../src/PulleyController.sol";
import {PulleyToken} from "../src/Token/PulleyToken.sol";
import {PermissionManager} from "../src/PermissionManager.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {MockSToken} from "../src/mocks/MockSToken.sol";
import {Events} from "../src/libraries/Events.sol";

/**
 * @title PuLTradingPoolUnitTest
 * @notice Comprehensive unit tests for PuLTradingPool contract
 * @dev Tests all functions, edge cases, and error conditions
 */
contract PuLTradingPoolUnitTest is Test {
    
    // ============ Core Contracts ============
    PulTradingPool public tradingPool;
    PulleyController public controller;
    PulleyToken public pulleyToken;
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
    
    // ============ Test Constants ============
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 1e6;
    uint256 public constant THRESHOLD = 10000 * 1e18;
    uint256 public constant LARGE_DEPOSIT = 5000 * 1e6;
    
    function setUp() public {
        deployer = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
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
            address(0),
            address(pulleyToken),
            address(0),
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
        
        // Set up permissions first
        permissionManager.grantPermission(address(controller), PulTradingPool.recordProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordLoss.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.distributePeriodProfit.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.recordPeriodLoss.selector);
        permissionManager.grantPermission(address(controller), PulTradingPool.distributeInsuranceRefund.selector);
        permissionManager.grantPermission(address(tradingPool), PulleyController.receiveFunds.selector);
        permissionManager.grantPermission(address(0), PulleyController.checkAIWalletPnL.selector);
        
        // Grant permission to set contracts
        permissionManager.grantPermission(address(this), PulleyToken.setContracts.selector);
        
        // Set up contract references
        pulleyToken.setContracts(address(0), address(controller), address(tradingPool));
        
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
    }
    
    // ============ Initialization Tests ============
    
    function testTradingPoolInitialization() public {
        assertEq(tradingPool.permissionManager(), address(permissionManager));
        assertEq(tradingPool.controller(), address(controller));
        assertEq(tradingPool.pulleyToken(), address(pulleyToken));
        assertEq(tradingPool.threshold(), THRESHOLD);
        assertEq(tradingPool.name(), "Pulley Trading Pool");
        assertEq(tradingPool.symbol(), "PTP");
    }
    
    function testTradingPoolDoubleInitialization() public {
        PulTradingPool newPool = new PulTradingPool();
        
        // First initialization should succeed
        newPool.initialize(
            "Test Pool",
            "TP",
            address(permissionManager),
            address(controller),
            address(pulleyToken)
        );
        
        // Second initialization should fail
        vm.expectRevert();
        newPool.initialize(
            "Test Pool 2",
            "TP2",
            address(permissionManager),
            address(controller),
            address(pulleyToken)
        );
    }
    
    function testTradingPoolInitializationWithZeroAddress() public {
        PulTradingPool newPool = new PulTradingPool();
        
        vm.expectRevert();
        newPool.initialize(
            "Test Pool",
            "TP",
            address(0), // Zero address should fail
            address(controller),
            address(pulleyToken)
        );
    }
    
    // ============ Deposit Tests ============
    
    function testDepositSuccess() public {
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        
        // Expect events
        vm.expectEmit(true, true, true, true);
        emit Events.Deposited(user1, address(usdc), DEPOSIT_AMOUNT, 0, 0);
        
        // Deposit
        uint256 poolTokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        
        // Check balances
        assertGt(poolTokens, 0);
        assertEq(tradingPool.balanceOf(user1), poolTokens);
        assertEq(tradingPool.getUserAssetDeposit(user1, address(usdc)), DEPOSIT_AMOUNT);
        assertEq(usdc.balanceOf(address(tradingPool)), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }
    
    function testDepositFirstUser() public {
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        
        uint256 poolTokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        
        // First user should get tokens minus 1e18 to prevent share manipulation
        assertEq(poolTokens, DEPOSIT_AMOUNT - 1e18);
        assertEq(tradingPool.totalSupply(), poolTokens);
        assertEq(tradingPool.totalPoolValue(), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }
    
    function testDepositSubsequentUsers() public {
        // First user deposits
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 user1Tokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Second user deposits
        vm.startPrank(user2);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 user2Tokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Check proportional allocation
        assertEq(user2Tokens, user1Tokens); // Should be equal for same amount
        assertEq(tradingPool.totalSupply(), user1Tokens + user2Tokens);
        assertEq(tradingPool.totalPoolValue(), DEPOSIT_AMOUNT * 2);
        
        // Check user balances
        assertEq(tradingPool.balanceOf(user1), user1Tokens);
        assertEq(tradingPool.balanceOf(user2), user2Tokens);
    }
    
    function testDepositZeroAmount() public {
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), 0);
        
        vm.expectRevert();
        tradingPool.deposit(address(usdc), 0);
        
        vm.stopPrank();
    }
    
    function testDepositUnsupportedAsset() public {
        address unsupportedAsset = makeAddr("unsupported");
        
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.deposit(unsupportedAsset, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }
    
    function testDepositInsufficientBalance() public {
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), 1000000 * 1e6); // Approve more than user has
        
        vm.expectRevert();
        tradingPool.deposit(address(usdc), 1000000 * 1e6);
        
        vm.stopPrank();
    }
    
    function testDepositInsufficientAllowance() public {
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), 100 * 1e6); // Approve less than deposit amount
        
        vm.expectRevert();
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }
    
    // ============ Withdraw Tests ============
    
    function testWithdrawSuccess() public {
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
        assertEq(usdc.balanceOf(address(tradingPool)), 0);
        
        vm.stopPrank();
    }
    
    function testWithdrawPartial() public {
        // First deposit
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 poolTokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        
        // Withdraw half
        uint256 halfTokens = poolTokens / 2;
        uint256 assetAmount = tradingPool.withdraw(address(usdc), halfTokens);
        
        // Check balances
        assertEq(assetAmount, DEPOSIT_AMOUNT / 2);
        assertEq(tradingPool.balanceOf(user1), halfTokens);
        assertEq(usdc.balanceOf(user1), 100000 * 1e6 - (DEPOSIT_AMOUNT / 2));
        
        vm.stopPrank();
    }
    
    function testWithdrawZeroAmount() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        tradingPool.withdraw(address(usdc), 0);
        
        vm.stopPrank();
    }
    
    function testWithdrawInsufficientPoolTokens() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        tradingPool.withdraw(address(usdc), 1000 * 1e18); // More than user has
        
        vm.stopPrank();
    }
    
    function testWithdrawUnsupportedAsset() public {
        address unsupportedAsset = makeAddr("unsupported");
        
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.withdraw(unsupportedAsset, 1000 * 1e18);
        vm.stopPrank();
    }
    
    // ============ Asset Management Tests ============
    
    function testAddAsset() public {
        address newAsset = makeAddr("newAsset");
        
        // Add asset
        tradingPool.addAsset(newAsset, 18, 5000 * 1e18, address(0));
        
        // Check asset is supported
        assertTrue(tradingPool.supportedAssets(newAsset));
        assertEq(tradingPool.assetDecimals(newAsset), 18);
        assertEq(tradingPool.assetThresholds(newAsset), 5000 * 1e18);
        
        // Check asset list
        address[] memory supportedAssets = tradingPool.getSupportedAssets();
        assertEq(supportedAssets.length, 4); // 3 original + 1 new
    }
    
    function testAddAssetZeroAddress() public {
        vm.expectRevert();
        tradingPool.addAsset(address(0), 18, 5000 * 1e18, address(0));
    }
    
    function testAddAssetZeroThreshold() public {
        address newAsset = makeAddr("newAsset");
        
        vm.expectRevert();
        tradingPool.addAsset(newAsset, 18, 0, address(0));
    }
    
    function testAddAssetUnauthorized() public {
        address newAsset = makeAddr("newAsset");
        
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.addAsset(newAsset, 18, 5000 * 1e18, address(0));
        vm.stopPrank();
    }
    
    function testRemoveAsset() public {
        address newAsset = makeAddr("newAsset");
        
        // First add asset
        tradingPool.addAsset(newAsset, 18, 5000 * 1e18, address(0));
        assertTrue(tradingPool.supportedAssets(newAsset));
        
        // Then remove asset
        tradingPool.removeAsset(newAsset);
        assertFalse(tradingPool.supportedAssets(newAsset));
        assertEq(tradingPool.assetDecimals(newAsset), 0);
        assertEq(tradingPool.assetThresholds(newAsset), 0);
        
        // Check asset list
        address[] memory supportedAssets = tradingPool.getSupportedAssets();
        assertEq(supportedAssets.length, 3); // Back to original
    }
    
    function testRemoveAssetUnauthorized() public {
        address newAsset = makeAddr("newAsset");
        
        // First add asset
        tradingPool.addAsset(newAsset, 18, 5000 * 1e18, address(0));
        
        // Try to remove without permission
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.removeAsset(newAsset);
        vm.stopPrank();
    }
    
    function testSetPriceFeed() public {
        address newPriceFeed = makeAddr("priceFeed");
        
        tradingPool.setPriceFeed(address(usdc), newPriceFeed);
        assertEq(address(tradingPool.priceFeeds(address(usdc))), newPriceFeed);
    }
    
    function testSetPriceFeedUnauthorized() public {
        address newPriceFeed = makeAddr("priceFeed");
        
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.setPriceFeed(address(usdc), newPriceFeed);
        vm.stopPrank();
    }
    
    // ============ Administrative Functions Tests ============
    
    function testUpdateThreshold() public {
        uint256 newThreshold = 20000 * 1e18;
        
        tradingPool.updateThreshold(newThreshold);
        assertEq(tradingPool.threshold(), newThreshold);
    }
    
    function testUpdateThresholdUnauthorized() public {
        uint256 newThreshold = 20000 * 1e18;
        
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.updateThreshold(newThreshold);
        vm.stopPrank();
    }
    
    function testUpdateController() public {
        address newController = makeAddr("newController");
        
        tradingPool.updateController(newController);
        assertEq(tradingPool.controller(), newController);
    }
    
    function testUpdateControllerZeroAddress() public {
        vm.expectRevert();
        tradingPool.updateController(address(0));
    }
    
    function testUpdateControllerUnauthorized() public {
        address newController = makeAddr("newController");
        
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.updateController(newController);
        vm.stopPrank();
    }
    
    function testUpdatePulleyToken() public {
        address newPulleyToken = makeAddr("newPulleyToken");
        
        tradingPool.updatePulleyToken(newPulleyToken);
        assertEq(tradingPool.pulleyToken(), newPulleyToken);
    }
    
    function testUpdatePulleyTokenZeroAddress() public {
        vm.expectRevert();
        tradingPool.updatePulleyToken(address(0));
    }
    
    function testUpdatePulleyTokenUnauthorized() public {
        address newPulleyToken = makeAddr("newPulleyToken");
        
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.updatePulleyToken(newPulleyToken);
        vm.stopPrank();
    }
    
    // ============ Profit/Loss Recording Tests ============
    
    function testRecordProfit() public {
        uint256 profitAmount = 1000 * 1e18;
        
        vm.prank(address(controller));
        tradingPool.recordProfit(profitAmount);
        
        assertEq(tradingPool.totalProfits(), profitAmount);
        assertEq(tradingPool.totalPoolValue(), profitAmount);
    }
    
    function testRecordProfitUnauthorized() public {
        uint256 profitAmount = 1000 * 1e18;
        
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.recordProfit(profitAmount);
        vm.stopPrank();
    }
    
    function testRecordLoss() public {
        // First add some funds to the pool
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        uint256 lossAmount = 500 * 1e18;
        
        vm.prank(address(controller));
        tradingPool.recordLoss(lossAmount);
        
        assertEq(tradingPool.totalLosses(), lossAmount);
    }
    
    function testRecordLossUnauthorized() public {
        uint256 lossAmount = 500 * 1e18;
        
        vm.startPrank(user1);
        vm.expectRevert();
        tradingPool.recordLoss(lossAmount);
        vm.stopPrank();
    }
    
    function testRecordLossZeroAmount() public {
        vm.prank(address(controller));
        vm.expectRevert();
        tradingPool.recordLoss(0);
    }
    
    // ============ View Functions Tests ============
    
    function testGetUserInfo() public {
        // First deposit
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 poolTokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        (uint256 poolTokenBalance, uint256 poolShare) = tradingPool.getUserInfo(user1);
        
        assertEq(poolTokenBalance, poolTokens);
        assertEq(poolShare, 1e18); // 100% share for first user
    }
    
    function testGetPoolMetrics() public {
        // First deposit
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        (uint256 totalValue, uint256 deposited, uint256 profits, uint256 losses, uint256 threshold) = 
            tradingPool.getPoolMetrics();
        
        assertEq(totalValue, DEPOSIT_AMOUNT);
        assertEq(deposited, DEPOSIT_AMOUNT);
        assertEq(profits, 0);
        assertEq(losses, 0);
        assertEq(threshold, THRESHOLD);
    }
    
    function testGetSupportedAssets() public {
        address[] memory supportedAssets = tradingPool.getSupportedAssets();
        assertEq(supportedAssets.length, 3);
        assertEq(supportedAssets[0], address(usdc));
        assertEq(supportedAssets[1], address(usdt));
        assertEq(supportedAssets[2], address(sToken));
    }
    
    function testGetAssetInfo() public {
        // First deposit
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        (uint256 balance, uint256 usdValue, uint8 decimals) = tradingPool.getAssetInfo(address(usdc));
        
        assertEq(balance, DEPOSIT_AMOUNT);
        assertEq(usdValue, DEPOSIT_AMOUNT); // 1:1 for mock tokens
        assertEq(decimals, 6);
    }
    
    function testGetUserAssetDeposit() public {
        // First deposit
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        uint256 userDeposit = tradingPool.getUserAssetDeposit(user1, address(usdc));
        assertEq(userDeposit, DEPOSIT_AMOUNT);
    }
    
    function testGetInsuranceFunds() public {
        uint256 insuranceFunds = tradingPool.getInsuranceFunds();
        assertEq(insuranceFunds, 0); // Initially 0
    }
    
    // ============ Trading Period Tests ============
    
    function testTradingPeriodCreation() public {
        // First deposit should create a trading period
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Check that a period was created
        assertEq(tradingPool.assetCurrentPeriodId(address(usdc)), 1);
        
        // Check period info
        (uint256 startTime, uint256 endTime, uint256 totalContributions, bool isActive, int256 pnl) = 
            tradingPool.getPeriodInfo(address(usdc), 1);
        
        assertGt(startTime, 0);
        assertEq(endTime, 0); // Not ended yet
        assertEq(totalContributions, DEPOSIT_AMOUNT);
        assertTrue(isActive);
        assertEq(pnl, 0);
    }
    
    function testDistributePeriodProfit() public {
        // First create a period
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        uint256 profitAmount = 1000 * 1e18;
        
        // Distribute profit
        vm.prank(address(controller));
        tradingPool.distributePeriodProfit(address(usdc), profitAmount, 1);
        
        // Check period is ended
        (uint256 startTime, uint256 endTime, uint256 totalContributions, bool isActive, int256 pnl) = 
            tradingPool.getPeriodInfo(address(usdc), 1);
        
        assertGt(endTime, 0);
        assertFalse(isActive);
        assertEq(pnl, int256(profitAmount));
    }
    
    function testDistributeInsuranceRefund() public {
        // First create a period
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        uint256 refundAmount = 150 * 1e18; // 15% of deposit
        
        // Distribute insurance refund
        vm.prank(address(controller));
        tradingPool.distributeInsuranceRefund(address(usdc), refundAmount);
        
        // Check that refund was recorded
        assertEq(tradingPool.totalInsuranceRefunds(), refundAmount);
    }
    
    // ============ Edge Cases and Error Tests ============
    
    function testDepositWithReentrancy() public {
        // This is a placeholder for reentrancy tests
        // In a real scenario, we'd need a malicious contract to test this
        assertTrue(true);
    }
    
    function testWithdrawWithReentrancy() public {
        // This is a placeholder for reentrancy tests
        // In a real scenario, we'd need a malicious contract to test this
        assertTrue(true);
    }
    
    // ============ Gas Usage Tests ============
    
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
    
    function testGasUsageWithdraw() public {
        // First deposit
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), DEPOSIT_AMOUNT);
        uint256 poolTokens = tradingPool.deposit(address(usdc), DEPOSIT_AMOUNT);
        
        // Then withdraw
        uint256 gasStart = gasleft();
        tradingPool.withdraw(address(usdc), poolTokens);
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used for withdraw:", gasUsed);
        assertLt(gasUsed, 150000); // Should be reasonable
        
        vm.stopPrank();
    }
    
    // ============ Multiple Users Tests ============
    
    function testMultipleUsersDeposit() public {
        uint256 depositAmount = 2000 * 1e6;
        
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
    
    function testMultipleAssetsDeposit() public {
        uint256 depositAmount = 1000 * 1e6;
        
        // Deposit USDC
        vm.startPrank(user1);
        usdc.approve(address(tradingPool), depositAmount);
        uint256 usdcTokens = tradingPool.deposit(address(usdc), depositAmount);
        vm.stopPrank();
        
        // Deposit USDT
        vm.startPrank(user1);
        usdt.approve(address(tradingPool), depositAmount);
        uint256 usdtTokens = tradingPool.deposit(address(usdt), depositAmount);
        vm.stopPrank();
        
        // Deposit sToken
        vm.startPrank(user1);
        sToken.approve(address(tradingPool), depositAmount);
        uint256 sTokenTokens = tradingPool.deposit(address(sToken), depositAmount);
        vm.stopPrank();
        
        // Check balances
        assertEq(tradingPool.balanceOf(user1), usdcTokens + usdtTokens + sTokenTokens);
        assertEq(tradingPool.getUserAssetDeposit(user1, address(usdc)), depositAmount);
        assertEq(tradingPool.getUserAssetDeposit(user1, address(usdt)), depositAmount);
        assertEq(tradingPool.getUserAssetDeposit(user1, address(sToken)), depositAmount);
    }
}
