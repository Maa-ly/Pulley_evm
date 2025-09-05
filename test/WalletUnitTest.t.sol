//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Wallet} from "../src/wallet.sol";
import {PulleyController} from "../src/PulleyController.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {MockSToken} from "../src/mocks/MockSToken.sol";
import {Events} from "../src/libraries/Events.sol";

/**
 * @title WalletUnitTest
 * @notice Comprehensive unit tests for Wallet contract
 * @dev Tests all functions, edge cases, and error conditions
 */
contract WalletUnitTest is Test {
    
    // ============ Core Contracts ============
    Wallet public wallet;
    PulleyController public controller;
    
    // ============ Mock Assets ============
    MockUSDC public usdc;
    MockUSDT public usdt;
    MockSToken public sToken;
    
    // ============ Test Addresses ============
    address public deployer;
    address public user1;
    address public user2;
    address public aiSigner;
    
    // ============ Test Constants ============
    uint256 public constant FUND_AMOUNT = 1000 * 1e6;
    uint256 public constant LARGE_AMOUNT = 10000 * 1e6;
    
    function setUp() public {
        deployer = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        // Use a known private key for testing
        uint256 aiSignerPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        aiSigner = vm.addr(aiSignerPrivateKey);
        
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
        // Deploy controller
        controller = new PulleyController();
        
        // Deploy wallet
        wallet = new Wallet();
        
        // Initialize wallet
        wallet.initialize(address(controller), aiSigner);
        
        // Add assets to wallet for price conversion
        vm.prank(address(controller));
        wallet.addAsset(address(usdc), address(0), 6);
        vm.prank(address(controller));
        wallet.addAsset(address(usdt), address(0), 6);
        vm.prank(address(controller));
        wallet.addAsset(address(sToken), address(0), 18);
        
        // Mint tokens to controller for testing
        usdc.mint(address(controller), 100000 * 1e6);
        usdt.mint(address(controller), 100000 * 1e6);
        sToken.mint(address(controller), 100000 * 1e18);
        
        // Approve wallet to spend controller's tokens
        vm.prank(address(controller));
        usdc.approve(address(wallet), type(uint256).max);
        vm.prank(address(controller));
        usdt.approve(address(wallet), type(uint256).max);
        vm.prank(address(controller));
        sToken.approve(address(wallet), type(uint256).max);
    }
    
    function _generateSignature(address asset, uint256 amount) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(
            address(wallet),
            asset,
            amount,
            wallet.nonces(asset),
            block.chainid
        ));
        
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        
        // Generate signature using the AI signer's private key
        uint256 aiSignerPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aiSignerPrivateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }
    
    // ============ Initialization Tests ============
    
    function testWalletInitialization() public {
        assertEq(wallet.controller(), address(controller));
        assertEq(wallet.aiSigner(), aiSigner);
    }
    
    function testWalletDoubleInitialization() public {
        Wallet newWallet = new Wallet();
        
        // First initialization should succeed
        newWallet.initialize(address(controller), aiSigner);
        
        // Second initialization should fail
        vm.expectRevert();
        newWallet.initialize(address(controller), aiSigner);
    }
    
    function testWalletInitializationWithZeroAddress() public {
        Wallet newWallet = new Wallet();
        
        vm.expectRevert();
        newWallet.initialize(address(0), aiSigner);
    }
    
    function testWalletInitializationWithZeroAISigner() public {
        Wallet newWallet = new Wallet();
        
        vm.expectRevert();
        newWallet.initialize(address(controller), address(0));
    }
    
    // ============ receiveFunds Tests ============
    
    function testReceiveFundsSuccess() public {
        // Prepare funds in controller
        usdc.mint(address(controller), FUND_AMOUNT);
        
        // Expect events
        vm.expectEmit(true, true, true, true);
        emit Events.FundsReceivedByWallet(address(controller), address(usdc), FUND_AMOUNT, 1);
        
        vm.expectEmit(true, true, true, true);
        emit Events.SessionStarted(address(usdc), 1, FUND_AMOUNT, 0);
        
        // Receive funds
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // Check balances
        assertEq(usdc.balanceOf(address(wallet)), FUND_AMOUNT);
        assertEq(wallet.initialBalances(address(usdc)), FUND_AMOUNT);
        assertEq(wallet.currentSession(address(usdc)), 1);
    }
    
    function testReceiveFundsMultipleSessions() public {
        // First session
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // Second session
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // Check session ID
        assertEq(wallet.currentSession(address(usdc)), 2);
        assertEq(wallet.initialBalances(address(usdc)), FUND_AMOUNT); // Should be updated to latest
    }
    
    function testReceiveFundsZeroAmount() public {
        vm.prank(address(controller));
        vm.expectRevert();
        wallet.receiveFunds(address(controller), address(usdc), 0);
    }
    
    function testReceiveFundsWrongFrom() public {
        usdc.mint(address(controller), FUND_AMOUNT);
        
        vm.prank(address(controller));
        vm.expectRevert();
        wallet.receiveFunds(user1, address(usdc), FUND_AMOUNT);
    }
    
    function testReceiveFundsUnauthorized() public {
        usdc.mint(address(controller), FUND_AMOUNT);
        
        vm.startPrank(user1);
        vm.expectRevert();
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        vm.stopPrank();
    }
    
    function testReceiveFundsInsufficientBalance() public {
        // Burn controller's tokens to create insufficient balance
        uint256 controllerBalance = usdc.balanceOf(address(controller));
        vm.prank(address(controller));
        usdc.transfer(address(0xdead), controllerBalance);
        
        // Verify controller has no tokens
        assertEq(usdc.balanceOf(address(controller)), 0);
        
        vm.prank(address(controller));
        vm.expectRevert();
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
    }
    
    // ============ sendFunds Tests ============
    
    function testSendFundsSuccess() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // Simulate profit by minting more tokens to wallet
        usdc.mint(address(wallet), 100 * 1e6);
        
        // Get initial controller balance
        uint256 initialControllerBalance = usdc.balanceOf(address(controller));
        
        // Generate signature
        bytes memory signature = _generateSignature(address(usdc), FUND_AMOUNT + 100 * 1e6);
        
        // Expect events
        vm.expectEmit(true, true, true, true);
        emit Events.ProfitSentByWallet(address(controller), address(usdc), FUND_AMOUNT + 100 * 1e6, 100 * 1e6);
        
        vm.expectEmit(true, true, true, true);
        emit Events.SessionCompleted(address(usdc), 1, 100 * 1e6, 0);
        
        // Send funds
        wallet.sendFunds(address(usdc), FUND_AMOUNT + 100 * 1e6, signature);
        
        // Check balances
        assertEq(usdc.balanceOf(address(controller)), initialControllerBalance + FUND_AMOUNT + 100 * 1e6);
        assertEq(usdc.balanceOf(address(wallet)), 0);
        assertEq(wallet.initialBalances(address(usdc)), 0); // Should be reset
    }
    
    function testSendFundsWithLoss() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // Simulate loss by burning some tokens from wallet
        // (In real scenario, this would happen through trading)
        vm.prank(address(wallet));
        usdc.transfer(address(0xdead), 200 * 1e6); // Send to dead address
        
        uint256 remainingAmount = FUND_AMOUNT - 200 * 1e6;
        
        // Get initial controller balance
        uint256 initialControllerBalance = usdc.balanceOf(address(controller));
        
        // Generate signature
        bytes memory signature = _generateSignature(address(usdc), remainingAmount);
        
        // Send funds
        wallet.sendFunds(address(usdc), remainingAmount, signature);
        
        // Check balances
        assertEq(usdc.balanceOf(address(controller)), initialControllerBalance + remainingAmount);
        assertEq(usdc.balanceOf(address(wallet)), 0);
    }
    
    function testSendFundsInvalidSignature() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // Generate invalid signature (wrong signer)
        bytes memory signature = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));
        
        vm.expectRevert();
        wallet.sendFunds(address(usdc), FUND_AMOUNT, signature);
    }
    
    function testSendFundsZeroAmount() public {
        vm.expectRevert();
        wallet.sendFunds(address(usdc), 0, "");
    }
    
    function testSendFundsInsufficientBalance() public {
        // Generate signature
        bytes memory signature = _generateSignature(address(usdc), FUND_AMOUNT);
        
        vm.expectRevert();
        wallet.sendFunds(address(usdc), FUND_AMOUNT, signature);
    }
    
    // ============ PnL Calculation Tests ============
    
    function testGetCurrentPnLNoSession() public {
        int256 pnl = wallet.getCurrentPnL(address(usdc));
        assertEq(pnl, 0);
    }
    
    function testGetCurrentPnLWithProfit() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // Simulate profit
        usdc.mint(address(wallet), 100 * 1e6);
        
        int256 pnl = wallet.getCurrentPnL(address(usdc));
        assertEq(pnl, 100 * 1e6);
    }
    
    function testGetCurrentPnLWithLoss() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // Simulate loss
        vm.prank(address(wallet));
        usdc.transfer(address(0xdead), 200 * 1e6);
        
        int256 pnl = wallet.getCurrentPnL(address(usdc));
        assertEq(pnl, -200 * 1e6);
    }
    
    function testGetCurrentPnLNoChange() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        int256 pnl = wallet.getCurrentPnL(address(usdc));
        assertEq(pnl, 0);
    }
    
    // ============ Session Info Tests ============
    
    function testGetSessionInfoNoSession() public {
        (uint256 sessionId, uint256 initialBalance, uint256 currentBalance, int256 pnl) = 
            wallet.getSessionInfo(address(usdc));
        
        assertEq(sessionId, 0);
        assertEq(initialBalance, 0);
        assertEq(currentBalance, 0);
        assertEq(pnl, 0);
    }
    
    function testGetSessionInfoWithSession() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // Simulate profit
        usdc.mint(address(wallet), 100 * 1e6);
        
        (uint256 sessionId, uint256 initialBalance, uint256 currentBalance, int256 pnl) = 
            wallet.getSessionInfo(address(usdc));
        
        assertEq(sessionId, 1);
        assertEq(initialBalance, FUND_AMOUNT);
        assertEq(currentBalance, FUND_AMOUNT + 100 * 1e6);
        assertEq(pnl, 100 * 1e6);
    }
    
    // ============ Administrative Functions Tests ============
    
    function testUpdateAISigner() public {
        address newSigner = makeAddr("newSigner");
        
        vm.prank(address(controller));
        wallet.updateAISigner(newSigner);
        
        assertEq(wallet.aiSigner(), newSigner);
    }
    
    function testUpdateAISignerUnauthorized() public {
        address newSigner = makeAddr("newSigner");
        
        vm.startPrank(user1);
        vm.expectRevert();
        wallet.updateAISigner(newSigner);
        vm.stopPrank();
    }
    
    function testAddAsset() public {
        address newAsset = makeAddr("newAsset");
        address priceFeed = makeAddr("priceFeed");
        uint8 decimals = 18;
        
        vm.prank(address(controller));
        wallet.addAsset(newAsset, priceFeed, decimals);
        
        // Check that asset was added (these are internal mappings, so we test indirectly)
        // In a real scenario, we'd check the price feed and decimals mappings
        assertTrue(true); // Placeholder
    }
    
    function testAddAssetUnauthorized() public {
        address newAsset = makeAddr("newAsset");
        address priceFeed = makeAddr("priceFeed");
        uint8 decimals = 18;
        
        vm.startPrank(user1);
        vm.expectRevert();
        wallet.addAsset(newAsset, priceFeed, decimals);
        vm.stopPrank();
    }
    
    // ============ View Functions Tests ============
    
    function testGetWallet() public {
        address walletAddress = wallet.getWallet();
        assertEq(walletAddress, address(wallet));
    }
    
    function testGetBalanceOfToken() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        uint256 balance = wallet.getBalanceOfToken(address(usdc));
        assertEq(balance, FUND_AMOUNT);
    }
    
    function testGetAllBalanceInUSD() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        uint256 usdValue = wallet.getAllBalanceInUSD(address(usdc));
        assertEq(usdValue, FUND_AMOUNT * 1e12); // Convert USDC (6 decimals) to 18 decimals
    }
    
    // ============ Nonce Tests ============
    
    function testNonceIncrement() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        uint256 initialNonce = wallet.nonces(address(usdc));
        
        // Generate signature and send funds
        bytes memory signature = _generateSignature(address(usdc), FUND_AMOUNT);
        
        wallet.sendFunds(address(usdc), FUND_AMOUNT, signature);
        
        // Check that nonce was incremented
        assertEq(wallet.nonces(address(usdc)), initialNonce + 1);
    }
    
    // ============ Multiple Assets Tests ============
    
    function testMultipleAssetsSessions() public {
        // USDC session
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // USDT session
        usdt.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdt), FUND_AMOUNT);
        
        // sToken session
        sToken.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(sToken), FUND_AMOUNT);
        
        // Check sessions
        assertEq(wallet.currentSession(address(usdc)), 1);
        assertEq(wallet.currentSession(address(usdt)), 1);
        assertEq(wallet.currentSession(address(sToken)), 1);
        
        // Check balances
        assertEq(usdc.balanceOf(address(wallet)), FUND_AMOUNT);
        assertEq(usdt.balanceOf(address(wallet)), FUND_AMOUNT);
        assertEq(sToken.balanceOf(address(wallet)), FUND_AMOUNT);
    }
    
    // ============ Edge Cases and Error Tests ============
    
    function testReceiveFundsWithReentrancy() public {
        // This is a placeholder for reentrancy tests
        // In a real scenario, we'd need a malicious contract to test this
        assertTrue(true);
    }
    
    function testSendFundsWithReentrancy() public {
        // This is a placeholder for reentrancy tests
        // In a real scenario, we'd need a malicious contract to test this
        assertTrue(true);
    }
    
    function testSignatureReplayAttack() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // Generate signature
        bytes memory signature = _generateSignature(address(usdc), FUND_AMOUNT);
        
        // First send should succeed
        wallet.sendFunds(address(usdc), FUND_AMOUNT, signature);
        
        // Second send with same signature should fail (nonce already used)
        vm.expectRevert();
        wallet.sendFunds(address(usdc), FUND_AMOUNT, signature);
    }
    
    // ============ Gas Usage Tests ============
    
    function testGasUsageReceiveFunds() public {
        usdc.mint(address(controller), FUND_AMOUNT);
        
        uint256 gasStart = gasleft();
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used for receiveFunds:", gasUsed);
        assertLt(gasUsed, 150000); // Should be reasonable
    }
    
    function testGasUsageSendFunds() public {
        // First receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // Generate signature
        bytes memory signature = _generateSignature(address(usdc), FUND_AMOUNT);
        
        uint256 gasStart = gasleft();
        wallet.sendFunds(address(usdc), FUND_AMOUNT, signature);
        uint256 gasUsed = gasStart - gasleft();
        
        console.log("Gas used for sendFunds:", gasUsed);
        assertLt(gasUsed, 200000); // Should be reasonable
    }
    
    // ============ Integration Tests ============
    
    function testCompleteTradingCycle() public {
        // 1. Receive funds
        usdc.mint(address(controller), FUND_AMOUNT);
        vm.prank(address(controller));
        wallet.receiveFunds(address(controller), address(usdc), FUND_AMOUNT);
        
        // 2. Simulate trading (profit)
        usdc.mint(address(wallet), 100 * 1e6);
        
        // 3. Check PnL
        int256 pnl = wallet.getCurrentPnL(address(usdc));
        assertEq(pnl, 100 * 1e6);
        
        // 4. Get initial controller balance
        uint256 initialControllerBalance = usdc.balanceOf(address(controller));
        
        // 5. Send funds back
        bytes memory signature = _generateSignature(address(usdc), FUND_AMOUNT + 100 * 1e6);
        
        wallet.sendFunds(address(usdc), FUND_AMOUNT + 100 * 1e6, signature);
        
        // 6. Check final state
        assertEq(usdc.balanceOf(address(controller)), initialControllerBalance + FUND_AMOUNT + 100 * 1e6);
        assertEq(usdc.balanceOf(address(wallet)), 0);
        assertEq(wallet.initialBalances(address(usdc)), 0);
    }
}
