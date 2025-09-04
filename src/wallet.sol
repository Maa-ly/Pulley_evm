//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PriceConvertor} from "./lib/PriceConvertor.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {DataTypes} from "./libraries/DataTypes.sol";
import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";

/**
 * @title AI Trading Wallet
 * @notice Manages AI trading funds and tracks profit/loss for the controller
 * @dev Implements signature-based transfers for security
 */
contract Wallet is PriceConvertor, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // ============ State Variables ============
    
    address public controller;
    address public aiSigner; // AI system's authorized signer
    
    // Track initial balances per trading session
    mapping(address => uint256) public initialBalances;
    mapping(address => uint256) public currentSession;
    
    // Nonce for signature replay protection
    mapping(address => uint256) public nonces;
    
    // ============ Events ============
    
    event FundsReceived(address indexed from, address indexed asset, uint256 amount, uint256 sessionId);
    event ProfitSent(address indexed to, address indexed asset, uint256 amount, int256 pnl);
    event SessionStarted(uint256 indexed sessionId, address indexed asset, uint256 initialBalance);
    event TradingCompleted(uint256 indexed sessionId, address indexed asset, int256 pnl);
    
    // ============ Errors ============
    // Errors are now imported from libraries
    
    // ============ Modifiers ============
    
    modifier onlyController() {
        if (msg.sender != controller) revert Errors.Wallet__OnlyController();
        _;
    }
    
    modifier onlyAISigner() {
        if (msg.sender != aiSigner) revert Errors.Wallet__OnlyAISigner();
        _;
    }
    
    // ============ Constructor ============
    
    constructor() {
        // Constructor is minimal - initialization happens in initialize()
    }
    
    // ============ Initializer ============
    
    /**
     * @notice Initialize the wallet with configuration
     * @param _controller Controller address
     * @param _aiSigner AI signer address
     */
    function initialize(address _controller, address _aiSigner) external {
        if (controller != address(0)) revert Errors.Clone__InitializationFailed();
        if (_controller == address(0) || _aiSigner == address(0)) {
            revert Errors.Wallet__InvalidAmount();
        }
        
        controller = _controller;
        aiSigner = _aiSigner;
    }
    
    // ============ Core Functions ============
    
    /**
     * @notice Receive trading funds from controller and start new session
     * @param from Controller address (for verification)
     * @param asset Asset being deposited
     * @param amount Amount to deposit
     */
    function receiveFunds(address from, address asset, uint256 amount) external onlyController nonReentrant {
        if (from != controller) revert Errors.Wallet__OnlyController();
        if (amount == 0) revert Errors.Wallet__InvalidAmount();
        
        // Transfer funds from controller
        IERC20(asset).safeTransferFrom(from, address(this), amount);
        
        // Start new trading session
        uint256 sessionId = ++currentSession[asset];
        initialBalances[asset] = amount;
        
        emit Events.FundsReceivedByWallet(from, asset, amount, sessionId);
        emit Events.SessionStarted(asset, sessionId, amount, 0);
    }
    
    /**
     * @notice Send profits back to controller with signature verification
     * @param asset Asset to send
     * @param amount Amount to send
     * @param signature AI signer's signature
     */
    function sendFunds(
        address asset, 
        uint256 amount, 
        bytes calldata signature
    ) external nonReentrant {
        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            address(this),
            asset,
            amount,
            nonces[asset]++,
            block.chainid
        ));
        
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        address recoveredSigner = ECDSA.recover(ethSignedMessageHash, signature);
        
        if (recoveredSigner != aiSigner) revert Errors.Wallet__InvalidSignature();
        if (amount == 0) revert Errors.Wallet__InvalidAmount();
        
        uint256 currentBalance = IERC20(asset).balanceOf(address(this));
        if (currentBalance < amount) revert Errors.Wallet__InsufficientBalance();
        
        // Calculate P&L
        uint256 initialBalance = initialBalances[asset];
        int256 pnl = int256(currentBalance) - int256(initialBalance);
        
        // Send funds to controller
        IERC20(asset).safeTransfer(controller, amount);
        
        emit Events.ProfitSentByWallet(controller, asset, amount, pnl);
        emit Events.SessionCompleted(asset, currentSession[asset], pnl, 0);
        
        // Reset for next session
        initialBalances[asset] = 0;
    }
    
    /**
     * @notice Get current profit/loss for an asset
     * @param asset Asset to check
     * @return pnl Current profit (positive) or loss (negative)
     */
    function getCurrentPnL(address asset) external view returns (int256 pnl) {
        uint256 currentBalance = IERC20(asset).balanceOf(address(this));
        uint256 initialBalance = initialBalances[asset];
        
        if (initialBalance == 0) return 0;
        
        pnl = int256(currentBalance) - int256(initialBalance);
    }
    
    /**
     * @notice Get wallet address
     * @return Wallet contract address
     */
    function getWallet() external view returns (address) {
    return address(this);
}

    /**
     * @notice Get balance of specific token
     * @param token Token address
     * @return Token balance
     */
    function getBalanceOfToken(address token) external view returns (uint256) {
    return IERC20(token).balanceOf(address(this));
}

    /**
     * @notice Get all wallet balance in USD for an asset
     * @param asset Asset address
     * @return USD value of the asset balance
     */
    function getAllBalanceInUSD(address asset) external view returns (uint256) {
        uint256 balance = IERC20(asset).balanceOf(address(this));
        return _getAssetUsdValue(asset, balance);
    }
    
    /**
     * @notice Get trading session info
     * @param asset Asset address
     * @return sessionId Current session ID
     * @return initialBalance Initial balance for current session
     * @return currentBalance Current balance
     * @return pnl Current profit/loss
     */
    function getSessionInfo(address asset) external view returns (
        uint256 sessionId,
        uint256 initialBalance,
        uint256 currentBalance,
        int256 pnl
    ) {
        sessionId = currentSession[asset];
        initialBalance = initialBalances[asset];
        currentBalance = IERC20(asset).balanceOf(address(this));
        
        if (initialBalance > 0) {
            pnl = int256(currentBalance) - int256(initialBalance);
        }
    }
    
    /**
     * @notice Emergency function to update AI signer (only controller)
     * @param newSigner New AI signer address
     */
    function updateAISigner(address newSigner) external onlyController {
        aiSigner = newSigner;
    }
    
    /**
     * @notice Add price feed for asset (only controller)
     * @param asset Asset address
     * @param priceFeed Chainlink price feed address
     * @param decimals Asset decimals
     */
    function addAsset(address asset, address priceFeed, uint8 decimals) external onlyController {
        priceFeeds[asset] = AggregatorV3Interface(priceFeed);
        assetDecimals[asset] = decimals;
    }
    
    // ============ Receive Function ============

receive() external payable {}
}