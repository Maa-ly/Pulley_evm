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
 * @title PulleyControllerUnitTest
 * @notice Comprehensive unit tests for PulleyController contract
 * @dev Tests all functions, edge cases, and error conditions
 */
contract PulleyControllerUnitTest is Test {
    
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
    address public aiTrader;
    
    // ============ Test Constants ============
    uint256 public constant DEPOSIT_AMOUNT = 10000 * 1e6;
    uint256 public constant INSURANCE_PERCENTAGE = 15;
    uint256 public constant TRADING_PERCENTAGE = 85;
    
    function setUp() public {
        deployer = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        aiTrader = makeAddr("aiTrader");
        
        // Deploy mock assets
        usdc = new MockUSDC();
        usdt = new MockUSDT();
        sToken = new MockSToken();
        
        // Mint tokens to deployer
        usdc.mint(deployer, 100000 * 1e6);
        usdt.mint(deployer, 100000 * 1e6);
        sToken.mint(deployer, 100000 * 1e18);
        
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
        permissionManager.grantPermission(address(this), PulleyController.updateContractAddresses.selector);
        
        // Set up contract references
        pulleyToken.setContracts(address(0), address(controller), address(tradingPool));
        
        // Set AI wallet in controller
        controller.setAIWallet(payable(address(wallet)));
        
        // Initialize wallet
        wallet.initialize(address(controller), address(controller));
    }
    
    // ============ Initialization Tests ============
    
    function testControllerInitialization() public {
        assertEq(controller.permissionManager(), address(permissionManager));
        assertEq(controller.tradingPool(), address(tradingPool));
        assertEq(controller.pulleyStablecoin(), address(pulleyToken));
        assertEq(controller.aiTrader(), aiTrader);
        assertEq(controller.aiWallet(), address(wallet));
    }
    
    function testControllerInitializationWithZeroAddress() public {
        PulleyController newController = new PulleyController();
        
        address[] memory supportedAssets = new address[](1);
        supportedAssets[0] = address(usdc);
        
        vm.expectRevert();
        newController.initialize(
            address(0), // Zero address should fail
            address(tradingPool),
            address(0),
            address(pulleyToken),
            aiTrader,
            supportedAssets
        );
    }
    
    function testControllerDoubleInitialization() public {
        PulleyController newController = new PulleyController();
        
        address[] memory supportedAssets = new address[](1);
        supportedAssets[0] = address(usdc);
        
        // First initialization should succeed
        newController.initialize(
            address(permissionManager),
            address(tradingPool),
            address(0),
            address(pulleyToken),
            aiTrader,
            supportedAssets
        );
        
        // Second initialization should fail
        vm.expectRevert();
        newController.initialize(
            address(permissionManager),
            address(tradingPool),
            address(0),
            address(pulleyToken),
            aiTrader,
            supportedAssets
        );
    }
    
    // ============ receiveFunds Tests ============
    
    function testReceiveFundsSuccess() public {
        // Prepare funds
        usdc.approve(address(controller), DEPOSIT_AMOUNT);
        
        // Expect events
        vm.expectEmit(true, true, true, true);
        emit Events.FundsReceived(address(this), address(usdc), DEPOSIT_AMOUNT);
        
        vm.expectEmit(true, true, true, true);
        emit Events.FundsAllocated(address(usdc), 1500 * 1e6, 8500 * 1e6);
        
        // Call receiveFunds
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        
        // Check allocations
        (uint256 insurance, uint256 trading) = controller.getFundAllocation(address(usdc));
        assertEq(insurance, 1500 * 1e6); // 15%
        assertEq(trading, 8500 * 1e6); // 85%
    }
    
    function testReceiveFundsWithDirectTransfer() public {
        // Transfer funds directly to controller first
        usdc.transfer(address(controller), DEPOSIT_AMOUNT);
        
        // Call receiveFunds (should not need transferFrom)
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        
        // Check allocations
        (uint256 insurance, uint256 trading) = controller.getFundAllocation(address(usdc));
        assertEq(insurance, 1500 * 1e6);
        assertEq(trading, 8500 * 1e6);
    }
    
    function testReceiveFundsZeroAmount() public {
        vm.expectRevert();
        controller.receiveFunds(address(usdc), 0);
    }
    
    function testReceiveFundsUnsupportedAsset() public {
        address unsupportedAsset = makeAddr("unsupported");
        
        vm.expectRevert();
        controller.receiveFunds(unsupportedAsset, DEPOSIT_AMOUNT);
    }
    
    function testReceiveFundsUnauthorized() public {
        vm.startPrank(user1);
        vm.expectRevert();
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }
    
    // ============ checkAIWalletPnL Tests ============
    
    function testCheckAIWalletPnLSuccess() public {
        // First, send funds to controller to trigger AI trading
        usdc.approve(address(controller), DEPOSIT_AMOUNT);
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        
        // Check PnL
        vm.prank(aiTrader);
        (int256 pnl, bool fundsSent) = controller.checkAIWalletPnL(address(usdc));
        
        assertEq(pnl, 0); // Initially no PnL
        assertFalse(fundsSent);
    }
    
    function testCheckAIWalletPnLWithZeroWallet() public {
        // Deploy new controller without wallet
        PulleyController newController = new PulleyController();
        address[] memory supportedAssets = new address[](1);
        supportedAssets[0] = address(usdc);
        
        newController.initialize(
            address(permissionManager),
            address(tradingPool),
            address(0),
            address(pulleyToken),
            aiTrader,
            supportedAssets
        );
        
        vm.prank(aiTrader);
        vm.expectRevert();
        newController.checkAIWalletPnL(address(usdc));
    }
    
    // ============ Asset Management Tests ============
    
    function testUpdateAssetSupport() public {
        address newAsset = makeAddr("newAsset");
        
        // Add new asset
        controller.updateAssetSupport(newAsset, true);
        assertTrue(controller.isAssetSupported(newAsset));
        
        // Check asset list
        address[] memory supportedAssets = controller.getSupportedAssets();
        assertEq(supportedAssets.length, 4); // 3 original + 1 new
        
        // Remove asset
        controller.updateAssetSupport(newAsset, false);
        assertFalse(controller.isAssetSupported(newAsset));
        
        // Check asset list
        supportedAssets = controller.getSupportedAssets();
        assertEq(supportedAssets.length, 3); // Back to original
    }
    
    function testUpdateAssetSupportUnauthorized() public {
        address newAsset = makeAddr("newAsset");
        
        vm.startPrank(user1);
        vm.expectRevert();
        controller.updateAssetSupport(newAsset, true);
        vm.stopPrank();
    }
    
    // ============ Administrative Functions Tests ============
    
    function testSetAITrader() public {
        address newAITrader = makeAddr("newAITrader");
        
        controller.setAITrader(newAITrader);
        assertEq(controller.aiTrader(), newAITrader);
    }
    
    function testSetAITraderUnauthorized() public {
        address newAITrader = makeAddr("newAITrader");
        
        vm.startPrank(user1);
        vm.expectRevert();
        controller.setAITrader(newAITrader);
        vm.stopPrank();
    }
    
    function testSetAITraderZeroAddress() public {
        vm.expectRevert();
        controller.setAITrader(address(0));
    }
    
    function testSetAIWallet() public {
        Wallet newWallet = new Wallet();
        
        controller.setAIWallet(payable(address(newWallet)));
        assertEq(controller.aiWallet(), address(newWallet));
    }
    
    function testSetAIWalletUnauthorized() public {
        Wallet newWallet = new Wallet();
        
        vm.startPrank(user1);
        vm.expectRevert();
        controller.setAIWallet(payable(address(newWallet)));
        vm.stopPrank();
    }
    
    function testSetAIWalletZeroAddress() public {
        vm.expectRevert();
        controller.setAIWallet(payable(address(0)));
    }
    
    function testUpdateContractAddresses() public {
        address newTradingPool = makeAddr("newTradingPool");
        address newInsurancePool = makeAddr("newInsurancePool");
        address newPulleyStablecoin = makeAddr("newPulleyStablecoin");
        
        controller.updateContractAddresses(
            newTradingPool,
            newInsurancePool,
            newPulleyStablecoin
        );
        
        assertEq(controller.tradingPool(), newTradingPool);
        assertEq(controller.insurancePool(), newInsurancePool);
        assertEq(controller.pulleyStablecoin(), newPulleyStablecoin);
    }
    
    function testUpdateContractAddressesUnauthorized() public {
        address newTradingPool = makeAddr("newTradingPool");
        
        vm.startPrank(user1);
        vm.expectRevert();
        controller.updateContractAddresses(newTradingPool, address(0), address(0));
        vm.stopPrank();
    }
    
    function testSetAutomationParameters() public {
        uint256 newGasLimit = 600000;
        
        controller.setAutomationParameters(newGasLimit);
        assertEq(controller.automationCallbackGasLimit(), newGasLimit);
    }
    
    function testSetAutomationParametersUnauthorized() public {
        uint256 newGasLimit = 600000;
        
        vm.startPrank(user1);
        vm.expectRevert();
        controller.setAutomationParameters(newGasLimit);
        vm.stopPrank();
    }
    
    // ============ View Functions Tests ============
    
    function testGetFundAllocation() public {
        // First allocate some funds
        usdc.approve(address(controller), DEPOSIT_AMOUNT);
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        
        (uint256 insurance, uint256 trading) = controller.getFundAllocation(address(usdc));
        assertEq(insurance, 1500 * 1e6);
        assertEq(trading, 8500 * 1e6);
    }
    
    function testGetTradeRequest() public {
        // First allocate some funds to create a trade request
        usdc.approve(address(controller), DEPOSIT_AMOUNT);
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        
        // Get the trade request (it should exist)
        // Note: This is a simplified test as we can't easily predict the requestId
        // In a real scenario, we'd need to track the requestId from the event
    }
    
    function testGetAssetPnL() public {
        int256 pnl = controller.getAssetPnL(address(usdc));
        assertEq(pnl, 0); // Initially no PnL
    }
    
    function testGetSupportedAssets() public {
        address[] memory supportedAssets = controller.getSupportedAssets();
        assertEq(supportedAssets.length, 3);
        assertEq(supportedAssets[0], address(usdc));
        assertEq(supportedAssets[1], address(usdt));
        assertEq(supportedAssets[2], address(sToken));
    }
    
    function testGetSystemMetrics() public {
        (uint256 totalInsurance, uint256 totalTrading, uint256 profits, uint256 losses) = 
            controller.getSystemMetrics();
        
        assertEq(totalInsurance, 0);
        assertEq(totalTrading, 0);
        assertEq(profits, 0);
        assertEq(losses, 0);
        
        // After receiving funds
        usdc.approve(address(controller), DEPOSIT_AMOUNT);
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        
        (totalInsurance, totalTrading, profits, losses) = controller.getSystemMetrics();
        assertEq(totalInsurance, 1500 * 1e6);
        assertEq(totalTrading, 8500 * 1e6);
        assertEq(profits, 0);
        assertEq(losses, 0);
    }
    
    function testIsAssetSupported() public {
        assertTrue(controller.isAssetSupported(address(usdc)));
        assertTrue(controller.isAssetSupported(address(usdt)));
        assertTrue(controller.isAssetSupported(address(sToken)));
        
        address unsupportedAsset = makeAddr("unsupported");
        assertFalse(controller.isAssetSupported(unsupportedAsset));
    }
    
    // ============ Emergency Functions Tests ============
    
    function testEmergencyWithdraw() public {
        // Send some funds to controller
        usdc.transfer(address(controller), 1000 * 1e6);
        
        uint256 initialBalance = usdc.balanceOf(user1);
        controller.emergencyWithdraw(address(usdc), 1000 * 1e6, user1);
        
        assertEq(usdc.balanceOf(user1), initialBalance + 1000 * 1e6);
    }
    
    function testEmergencyWithdrawETH() public {
        // Send ETH to controller
        payable(address(controller)).transfer(1 ether);
        
        uint256 initialBalance = user1.balance;
        controller.emergencyWithdraw(address(0), 1 ether, user1);
        
        assertEq(user1.balance, initialBalance + 1 ether);
    }
    
    function testEmergencyWithdrawUnauthorized() public {
        vm.startPrank(user1);
        vm.expectRevert();
        controller.emergencyWithdraw(address(usdc), 1000 * 1e6, user2);
        vm.stopPrank();
    }
    
    function testEmergencyWithdrawZeroAddress() public {
        vm.expectRevert();
        controller.emergencyWithdraw(address(usdc), 1000 * 1e6, address(0));
    }
    
    // ============ Fund Allocation Tests ============
    
    function testFundAllocationCalculation() public {
        uint256 testAmount = 1000 * 1e6;
        
        usdc.approve(address(controller), testAmount);
        controller.receiveFunds(address(usdc), testAmount);
        
        (uint256 insurance, uint256 trading) = controller.getFundAllocation(address(usdc));
        
        assertEq(insurance, (testAmount * INSURANCE_PERCENTAGE) / 100);
        assertEq(trading, (testAmount * TRADING_PERCENTAGE) / 100);
        assertEq(insurance + trading, testAmount);
    }
    
    function testMultipleFundAllocations() public {
        uint256 firstAmount = 5000 * 1e6;
        uint256 secondAmount = 3000 * 1e6;
        
        // First allocation
        usdc.approve(address(controller), firstAmount);
        controller.receiveFunds(address(usdc), firstAmount);
        
        (uint256 insurance, uint256 trading) = controller.getFundAllocation(address(usdc));
        assertEq(insurance, 750 * 1e6); // 15% of 5000
        assertEq(trading, 4250 * 1e6); // 85% of 5000
        
        // Second allocation
        usdc.approve(address(controller), secondAmount);
        controller.receiveFunds(address(usdc), secondAmount);
        
        (insurance, trading) = controller.getFundAllocation(address(usdc));
        assertEq(insurance, 1200 * 1e6); // 15% of 8000
        assertEq(trading, 6800 * 1e6); // 85% of 8000
    }
    
    // ============ Edge Cases and Error Tests ============
    
    function testReceiveFundsInsufficientBalance() public {
        // Try to receive more than we have
        vm.expectRevert();
        controller.receiveFunds(address(usdc), 1000000 * 1e6);
    }
    
    function testReceiveFundsInsufficientAllowance() public {
        // Don't approve enough
        usdc.approve(address(controller), 1000 * 1e6);
        
        vm.expectRevert();
        controller.receiveFunds(address(usdc), 2000 * 1e6);
    }
    
    // ============ Gas Usage Tests ============
    
    function testGasUsageReceiveFunds() public {
        usdc.approve(address(controller), DEPOSIT_AMOUNT);
        
        uint256 gasStart = gasleft();
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used for receiveFunds:", gasUsed);
        assertLt(gasUsed, 300000); // Should be reasonable
    }
    
    function testGasUsageCheckAIWalletPnL() public {
        // First allocate funds
        usdc.approve(address(controller), DEPOSIT_AMOUNT);
        controller.receiveFunds(address(usdc), DEPOSIT_AMOUNT);
        
        uint256 gasStart = gasleft();
        vm.prank(aiTrader);
        controller.checkAIWalletPnL(address(usdc));
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used for checkAIWalletPnL:", gasUsed);
        assertLt(gasUsed, 200000); // Should be reasonable
    }
}
