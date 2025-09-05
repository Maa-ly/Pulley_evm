//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {PulleyToken} from "../src/Token/PulleyToken.sol";
import {PulleyController} from "../src/PulleyController.sol";
import {PulTradingPool} from "../src/Pool/PuLTradingPool.sol";
import {PermissionManager} from "../src/PermissionManager.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {MockSToken} from "../src/mocks/MockSToken.sol";
import {Events} from "../src/libraries/Events.sol";

/**
 * @title PulleyTokenUnitTest
 * @notice Comprehensive unit tests for PulleyToken contract
 * @dev Tests all functions, edge cases, and error conditions
 */
contract PulleyTokenUnitTest is Test {
    
    // ============ Core Contracts ============
    PulleyToken public pulleyToken;
    PulleyController public controller;
    PulTradingPool public tradingPool;
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
    uint256 public constant MINT_AMOUNT = 1000 * 1e6;
    uint256 public constant LARGE_MINT = 10000 * 1e6;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant GROWTH_INTERVAL = 1 days;
    
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
        
        // Set up contract references
        pulleyToken.setContracts(address(0), address(controller), address(tradingPool));
        
        // Set up permissions
        permissionManager.grantPermission(address(controller), PulleyToken.updateUtilization.selector);
        permissionManager.grantPermission(address(controller), PulleyToken.coverLoss.selector);
        permissionManager.grantPermission(address(controller), PulleyToken.addProfits.selector);
        permissionManager.grantPermission(address(controller), PulleyToken.updateAssetSupport.selector);
        permissionManager.grantPermission(address(controller), PulleyToken.setContracts.selector);
        permissionManager.grantPermission(address(controller), PulleyToken.updateGrowthParameters.selector);
    }
    
    // ============ Initialization Tests ============
    
    function testPulleyTokenInitialization() public {
        assertEq(pulleyToken.permissionManager(), address(permissionManager));
        assertEq(pulleyToken.controller(), address(controller));
        assertEq(pulleyToken.tradingPool(), address(tradingPool));
        assertEq(pulleyToken.name(), "Pulley Token");
        assertEq(pulleyToken.symbol(), "PUL");
        assertEq(pulleyToken.decimals(), 18);
    }
    
    function testPulleyTokenInitializationWithSupportedAssets() public {
        // Check that supported assets were set
        assertTrue(pulleyToken.isAssetSupported(address(usdc)));
        assertTrue(pulleyToken.isAssetSupported(address(usdt)));
        assertTrue(pulleyToken.isAssetSupported(address(sToken)));
        
        // Check backing assets array
        address[] memory backingAssets = pulleyToken.getSupportedAssets();
        assertEq(backingAssets.length, 3);
        assertEq(backingAssets[0], address(usdc));
        assertEq(backingAssets[1], address(usdt));
        assertEq(backingAssets[2], address(sToken));
    }
    
    // ============ Minting Tests ============
    
    function testMintSuccess() public {
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), MINT_AMOUNT);
        
        // Expect events
        vm.expectEmit(true, true, true, true);
        emit Events.Minted(user1, 0, MINT_AMOUNT);
        
        // Mint tokens
        uint256 tokensMinted = pulleyToken.mint(address(usdc), MINT_AMOUNT);
        
        // Check balances
        assertGt(tokensMinted, 0);
        assertEq(pulleyToken.balanceOf(user1), tokensMinted);
        assertEq(pulleyToken.getBackingInfo(address(usdc)), MINT_AMOUNT);
        assertEq(usdc.balanceOf(address(pulleyToken)), MINT_AMOUNT);
        
        vm.stopPrank();
    }
    
    function testMintFromController() public {
        // Controller minting should go to insurance reserve
        usdc.approve(address(pulleyToken), MINT_AMOUNT);
        
        vm.prank(address(controller));
        uint256 tokensMinted = pulleyToken.mint(address(usdc), MINT_AMOUNT);
        
        // Check that tokens were minted to controller and insurance reserve increased
        assertGt(tokensMinted, 0);
        assertEq(pulleyToken.balanceOf(address(controller)), tokensMinted);
        
        // Check growth metrics
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertEq(reserve, tokensMinted);
    }
    
    function testMintZeroAmount() public {
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), 0);
        
        vm.expectRevert();
        pulleyToken.mint(address(usdc), 0);
        
        vm.stopPrank();
    }
    
    function testMintUnsupportedAsset() public {
        address unsupportedAsset = makeAddr("unsupported");
        
        vm.startPrank(user1);
        vm.expectRevert();
        pulleyToken.mint(unsupportedAsset, MINT_AMOUNT);
        vm.stopPrank();
    }
    
    function testMintInsufficientBalance() public {
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), 1000000 * 1e6); // Approve more than user has
        
        vm.expectRevert();
        pulleyToken.mint(address(usdc), 1000000 * 1e6);
        
        vm.stopPrank();
    }
    
    function testMintInsufficientAllowance() public {
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), 100 * 1e6); // Approve less than mint amount
        
        vm.expectRevert();
        pulleyToken.mint(address(usdc), MINT_AMOUNT);
        
        vm.stopPrank();
    }
    
    // ============ Burning Tests ============
    
    function testBurnSuccess() public {
        // First mint
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), MINT_AMOUNT);
        uint256 tokensMinted = pulleyToken.mint(address(usdc), MINT_AMOUNT);
        
        // Then burn
        uint256 backingReturned = pulleyToken.burn(address(usdc), tokensMinted);
        
        // Check balances
        assertEq(backingReturned, MINT_AMOUNT);
        assertEq(pulleyToken.balanceOf(user1), 0);
        assertEq(usdc.balanceOf(user1), 100000 * 1e6); // Back to original
        assertEq(usdc.balanceOf(address(pulleyToken)), 0);
        
        vm.stopPrank();
    }
    
    function testBurnPartial() public {
        // First mint
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), MINT_AMOUNT);
        uint256 tokensMinted = pulleyToken.mint(address(usdc), MINT_AMOUNT);
        
        // Burn half
        uint256 halfTokens = tokensMinted / 2;
        uint256 backingReturned = pulleyToken.burn(address(usdc), halfTokens);
        
        // Check balances
        assertEq(backingReturned, MINT_AMOUNT / 2);
        assertEq(pulleyToken.balanceOf(user1), halfTokens);
        assertEq(usdc.balanceOf(user1), 100000 * 1e6 - (MINT_AMOUNT / 2));
        
        vm.stopPrank();
    }
    
    function testBurnZeroAmount() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        pulleyToken.burn(address(usdc), 0);
        
        vm.stopPrank();
    }
    
    function testBurnInsufficientBalance() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        pulleyToken.burn(address(usdc), 1000 * 1e18); // More than user has
        
        vm.stopPrank();
    }
    
    function testBurnUnsupportedAsset() public {
        address unsupportedAsset = makeAddr("unsupported");
        
        vm.startPrank(user1);
        vm.expectRevert();
        pulleyToken.burn(unsupportedAsset, 1000 * 1e18);
        vm.stopPrank();
    }
    
    // ============ Growth Mechanism Tests ============
    
    function testGrowthUpdate() public {
        // First mint some tokens to create supply
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), LARGE_MINT);
        pulleyToken.mint(address(usdc), LARGE_MINT);
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
        assertGt(currentGrowthRate, 0); // Growth rate should be positive
    }
    
    function testGrowthUpdateBeforeInterval() public {
        // First mint some tokens
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), LARGE_MINT);
        pulleyToken.mint(address(usdc), LARGE_MINT);
        vm.stopPrank();
        
        // Try to update growth before interval
        pulleyToken.updateGrowth();
        
        // Check that no growth was applied
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertEq(currentPrice, 1e18); // Price should be unchanged
        assertEq(reserve, 0); // Reserve should be unchanged
    }
    
    function testGrowthUpdateWithZeroSupply() public {
        // Try to update growth with zero supply
        pulleyToken.updateGrowth();
        
        // Should not revert but also not apply growth
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertEq(currentPrice, 1e18);
        assertEq(reserve, 0);
    }
    
    function testGrowthCalculation() public {
        // First mint some tokens
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), LARGE_MINT);
        pulleyToken.mint(address(usdc), LARGE_MINT);
        vm.stopPrank();
        
        // Set utilization rate
        vm.prank(address(controller));
        pulleyToken.updateUtilization(5000); // 50% utilization
        
        // Fast forward time
        vm.warp(block.timestamp + 1 days);
        
        // Update growth
        pulleyToken.updateGrowth();
        
        // Check growth metrics
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertEq(currentUtilization, 5000);
        assertGt(currentGrowthRate, 100); // Should be higher than base rate due to utilization
    }
    
    // ============ Price Calculation Tests ============
    
    function testGetCurrentPriceInitial() public {
        uint256 price = pulleyToken.getCurrentPrice();
        assertEq(price, 1e18); // Should start at 1 USD
    }
    
    function testGetCurrentPriceWithGrowth() public {
        // First mint some tokens
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), LARGE_MINT);
        pulleyToken.mint(address(usdc), LARGE_MINT);
        vm.stopPrank();
        
        // Fast forward time and trigger growth
        vm.warp(block.timestamp + 1 days);
        pulleyToken.updateGrowth();
        
        // Check that price increased
        uint256 price = pulleyToken.getCurrentPrice();
        assertGt(price, 1e18);
    }
    
    function testGetCurrentPriceWithUtilization() public {
        // First mint some tokens
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), LARGE_MINT);
        pulleyToken.mint(address(usdc), LARGE_MINT);
        vm.stopPrank();
        
        // Set high utilization
        vm.prank(address(controller));
        pulleyToken.updateUtilization(8000); // 80% utilization
        
        // Check that price includes utilization premium
        uint256 price = pulleyToken.getCurrentPrice();
        assertGt(price, 1e18);
    }
    
    // ============ Authorized Functions Tests ============
    
    function testUpdateUtilization() public {
        uint256 newUtilization = 5000; // 50%
        
        vm.prank(address(controller));
        pulleyToken.updateUtilization(newUtilization);
        
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertEq(currentUtilization, newUtilization);
    }
    
    function testUpdateUtilizationUnauthorized() public {
        uint256 newUtilization = 5000;
        
        vm.startPrank(user1);
        vm.expectRevert();
        pulleyToken.updateUtilization(newUtilization);
        vm.stopPrank();
    }
    
    function testCoverLoss() public {
        // First mint some tokens to create insurance reserve
        usdc.approve(address(pulleyToken), LARGE_MINT);
        vm.prank(address(controller));
        uint256 tokensMinted = pulleyToken.mint(address(usdc), LARGE_MINT);
        
        // Cover loss
        uint256 lossAmount = 100 * 1e18;
        vm.prank(address(controller));
        pulleyToken.coverLoss(lossAmount);
        
        // Check that reserve decreased
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertEq(reserve, tokensMinted - lossAmount);
    }
    
    function testCoverLossInsufficientReserve() public {
        uint256 lossAmount = 1000 * 1e18;
        
        vm.prank(address(controller));
        vm.expectRevert();
        pulleyToken.coverLoss(lossAmount);
    }
    
    function testCoverLossUnauthorized() public {
        uint256 lossAmount = 100 * 1e18;
        
        vm.startPrank(user1);
        vm.expectRevert();
        pulleyToken.coverLoss(lossAmount);
        vm.stopPrank();
    }
    
    function testAddProfits() public {
        uint256 profitAmount = 1000 * 1e18;
        
        vm.prank(address(controller));
        pulleyToken.addProfits(profitAmount);
        
        // Check that reserve increased
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertEq(reserve, profitAmount);
    }
    
    function testAddProfitsUnauthorized() public {
        uint256 profitAmount = 1000 * 1e18;
        
        vm.startPrank(user1);
        vm.expectRevert();
        pulleyToken.addProfits(profitAmount);
        vm.stopPrank();
    }
    
    function testAddProfitsZeroAmount() public {
        vm.prank(address(controller));
        vm.expectRevert();
        pulleyToken.addProfits(0);
    }
    
    // ============ Administrative Functions Tests ============
    
    function testSetContracts() public {
        address newController = makeAddr("newController");
        address newTradingPool = makeAddr("newTradingPool");
        
        vm.prank(address(controller));
        pulleyToken.setContracts(address(0), newController, newTradingPool);
        
        assertEq(pulleyToken.controller(), newController);
        assertEq(pulleyToken.tradingPool(), newTradingPool);
    }
    
    function testSetContractsUnauthorized() public {
        address newController = makeAddr("newController");
        
        vm.startPrank(user1);
        vm.expectRevert();
        pulleyToken.setContracts(address(0), newController, address(0));
        vm.stopPrank();
    }
    
    function testUpdateAssetSupport() public {
        address newAsset = makeAddr("newAsset");
        
        // Add new asset
        vm.prank(address(controller));
        pulleyToken.updateAssetSupport(newAsset, true);
        
        assertTrue(pulleyToken.isAssetSupported(newAsset));
        
        // Check backing assets array
        address[] memory backingAssets = pulleyToken.getSupportedAssets();
        assertEq(backingAssets.length, 4); // 3 original + 1 new
        
        // Remove asset
        vm.prank(address(controller));
        pulleyToken.updateAssetSupport(newAsset, false);
        
        assertFalse(pulleyToken.isAssetSupported(newAsset));
        
        // Check backing assets array
        backingAssets = pulleyToken.getSupportedAssets();
        assertEq(backingAssets.length, 3); // Back to original
    }
    
    function testUpdateAssetSupportUnauthorized() public {
        address newAsset = makeAddr("newAsset");
        
        vm.startPrank(user1);
        vm.expectRevert();
        pulleyToken.updateAssetSupport(newAsset, true);
        vm.stopPrank();
    }
    
    function testUpdateGrowthParameters() public {
        uint256 newBaseGrowthRate = 200; // 2%
        uint256 newUtilizationMultiplier = 100; // 1%
        uint256 newMaxGrowthRate = 2000; // 20%
        
        vm.prank(address(controller));
        pulleyToken.updateGrowthParameters(
            newBaseGrowthRate,
            newUtilizationMultiplier,
            newMaxGrowthRate
        );
        
        // Check that parameters were updated
        // Note: These are internal variables, so we test through growth calculation
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), LARGE_MINT);
        pulleyToken.mint(address(usdc), LARGE_MINT);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 1 days);
        pulleyToken.updateGrowth();
        
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        assertGt(currentGrowthRate, 0);
    }
    
    function testUpdateGrowthParametersUnauthorized() public {
        vm.startPrank(user1);
        vm.expectRevert();
        pulleyToken.updateGrowthParameters(200, 100, 2000);
        vm.stopPrank();
    }
    
    // ============ View Functions Tests ============
    
    function testGetBackingInfo() public {
        // First mint some tokens
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), MINT_AMOUNT);
        pulleyToken.mint(address(usdc), MINT_AMOUNT);
        vm.stopPrank();
        
        uint256 backing = pulleyToken.getBackingInfo(address(usdc));
        assertEq(backing, MINT_AMOUNT);
    }
    
    function testGetSupportedAssets() public {
        address[] memory supportedAssets = pulleyToken.getSupportedAssets();
        assertEq(supportedAssets.length, 3);
        assertEq(supportedAssets[0], address(usdc));
        assertEq(supportedAssets[1], address(usdt));
        assertEq(supportedAssets[2], address(sToken));
    }
    
    function testGetGrowthMetrics() public {
        (uint256 currentPrice, uint256 currentGrowthRate, uint256 currentUtilization, uint256 reserve) = 
            pulleyToken.getGrowthMetrics();
        
        assertEq(currentPrice, 1e18); // Initial price
        assertEq(currentGrowthRate, 100); // Base growth rate
        assertEq(currentUtilization, 0); // Initial utilization
        assertEq(reserve, 0); // Initial reserve
    }
    
    function testIsAssetSupported() public {
        assertTrue(pulleyToken.isAssetSupported(address(usdc)));
        assertTrue(pulleyToken.isAssetSupported(address(usdt)));
        assertTrue(pulleyToken.isAssetSupported(address(sToken)));
        
        address unsupportedAsset = makeAddr("unsupported");
        assertFalse(pulleyToken.isAssetSupported(unsupportedAsset));
    }
    
    // ============ Edge Cases and Error Tests ============
    
    function testMintWithReentrancy() public {
        // This is a placeholder for reentrancy tests
        // In a real scenario, we'd need a malicious contract to test this
        assertTrue(true);
    }
    
    function testBurnWithReentrancy() public {
        // This is a placeholder for reentrancy tests
        // In a real scenario, we'd need a malicious contract to test this
        assertTrue(true);
    }
    
    function testMultipleAssetsMinting() public {
        uint256 mintAmount = 1000 * 1e6;
        
        // Mint with USDC
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), mintAmount);
        uint256 usdcTokens = pulleyToken.mint(address(usdc), mintAmount);
        vm.stopPrank();
        
        // Mint with USDT
        vm.startPrank(user1);
        usdt.approve(address(pulleyToken), mintAmount);
        uint256 usdtTokens = pulleyToken.mint(address(usdt), mintAmount);
        vm.stopPrank();
        
        // Mint with sToken
        vm.startPrank(user1);
        sToken.approve(address(pulleyToken), mintAmount);
        uint256 sTokenTokens = pulleyToken.mint(address(sToken), mintAmount);
        vm.stopPrank();
        
        // Check balances
        assertEq(pulleyToken.balanceOf(user1), usdcTokens + usdtTokens + sTokenTokens);
        assertEq(pulleyToken.getBackingInfo(address(usdc)), mintAmount);
        assertEq(pulleyToken.getBackingInfo(address(usdt)), mintAmount);
        assertEq(pulleyToken.getBackingInfo(address(sToken)), mintAmount);
    }
    
    // ============ Gas Usage Tests ============
    
    function testGasUsageMint() public {
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), MINT_AMOUNT);
        
        uint256 gasStart = gasleft();
        pulleyToken.mint(address(usdc), MINT_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used for mint:", gasUsed);
        assertLt(gasUsed, 300000); // Should be reasonable
        
        vm.stopPrank();
    }
    
    function testGasUsageBurn() public {
        // First mint
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), MINT_AMOUNT);
        uint256 tokensMinted = pulleyToken.mint(address(usdc), MINT_AMOUNT);
        
        // Then burn
        uint256 gasStart = gasleft();
        pulleyToken.burn(address(usdc), tokensMinted);
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used for burn:", gasUsed);
        assertLt(gasUsed, 250000); // Should be reasonable
        
        vm.stopPrank();
    }
    
    function testGasUsageUpdateGrowth() public {
        // First mint some tokens
        vm.startPrank(user1);
        usdc.approve(address(pulleyToken), LARGE_MINT);
        pulleyToken.mint(address(usdc), LARGE_MINT);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + 1 days);
        
        uint256 gasStart = gasleft();
        pulleyToken.updateGrowth();
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used for updateGrowth:", gasUsed);
        assertLt(gasUsed, 200000); // Should be reasonable
    }
}
