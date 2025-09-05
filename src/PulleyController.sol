//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPermissionManager} from "./Permission/interface/IPermissionManager.sol";
import {AbstractBlocklockReceiver} from "blocklock-solidity/AbstractBlocklockReceiver.sol";
import {TypesLib} from "blocklock-solidity/libraries/TypesLib.sol";
import {BLS} from "blocklock-solidity/libraries/BLS.sol";
import "./Token/PulleyToken.sol";
import "./wallet.sol";

/**
 * @title PulleyController
 * @author Core-Connect Team
 * @notice Central controller for fund allocation and AI trading integration
 * @dev Manages fund flow: 15% to insurance, 85% to AI trading with automated execution
 */
contract PulleyController is ReentrancyGuard, AbstractBlocklockReceiver {
    using SafeERC20 for IERC20;
    
    // ============ State Variables ============
    
    address public permissionManager;
    address public tradingPool;
    address public insurancePool;
    address public pulleyStablecoin;
    address public aiTrader; // External AI trading system
    address payable public aiWallet; // AI trading wallet contract
    
    // Fund allocation percentages
    uint256 public constant INSURANCE_PERCENTAGE = 15; // 15%
    uint256 public constant TRADING_PERCENTAGE = 85; // 85%
    uint256 public constant PERCENTAGE_BASE = 100;
    
    // Profit distribution percentages
    uint256 public constant INSURANCE_PROFIT_SHARE = 10; // 10%
    uint256 public constant TRADING_PROFIT_SHARE = 90; // 90%
    
    // Asset management
    mapping(address => uint256) public insuranceAllocations;
    mapping(address => uint256) public tradingAllocations;
    mapping(address => bool) public supportedAssets;
    address[] public assetList;
    
    // AI Trading tracking
    mapping(bytes32 => TradeRequest) public activeTradeRequests;
    mapping(address => uint256) public assetProfitLoss; // Track P&L per asset
    
    uint256 public totalInsuranceFunds;
    uint256 public totalTradingFunds;
    uint256 public totalProfits;
    uint256 public totalLosses;
    
    // Blocklock automation
    uint256 public automationCallbackGasLimit = 500000;
    
    // ============ Structs ============
    
    struct TradeRequest {
        bytes32 requestId;
        address asset;
        uint256 amount;
        uint256 timestamp;
        bool isActive;
        int256 resultPnL; // Positive for profit, negative for loss
        bool isCompleted;
    }
    
    struct FundAllocation {
        address asset;
        uint256 totalAmount;
        uint256 insuranceAmount;
        uint256 tradingAmount;
    }
    
    // ============ Events & Errors ============
    // Events and errors are now imported from libraries
    
    // ============ Modifiers ============
    
    modifier onlyAuthorized() {
        if (permissionManager != address(0)) {
            require(
                IPermissionManager(permissionManager).hasPermissions(msg.sender, msg.sig),
                "PulleyController: not authorized"
            );
        } else {
            require(msg.sender == tradingPool, "PulleyController: only trading pool");
        }
        _;
    }
    
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert Errors.PulleyController__ZeroAmount();
        _;
    }
    
    modifier validAddress(address addr) {
        if (addr == address(0)) revert Errors.PulleyController__ZeroAddress();
        _;
    }
    
    // ============ Constructor ============
    
    constructor() AbstractBlocklockReceiver(address(0)) {
        // Constructor is minimal - initialization happens in initialize()
    }
    
    // ============ Initializer ============
    
    /**
     * @notice Initialize the controller with configuration
     * @param _permissionManager Permission manager address
     * @param _tradingPool Trading pool address
     * @param _insurancePool Insurance pool address (not used)
     * @param _pulleyStablecoin PulleyToken address
     * @param _aiTrader AI trader address (not used)
     * @param _supportedAssets Array of supported asset addresses
     */
    function initialize(
        address _permissionManager,
        address _tradingPool,
        address _insurancePool,
        address _pulleyStablecoin,
        address _aiTrader,
        address[] memory _supportedAssets
    ) external {
        if (permissionManager != address(0)) revert Errors.Clone__InitializationFailed();
        if (_permissionManager == address(0) || _tradingPool == address(0)) {
            revert Errors.PulleyController__ZeroAddress();
        }
        
        permissionManager = _permissionManager;
        tradingPool = _tradingPool;
        insurancePool = _insurancePool;
        pulleyStablecoin = _pulleyStablecoin;
        aiTrader = _aiTrader;
        
        // Initialize supported assets
        for (uint256 i = 0; i < _supportedAssets.length; i++) {
            supportedAssets[_supportedAssets[i]] = true;
            assetList.push(_supportedAssets[i]);
            emit Events.AssetSupportUpdated(_supportedAssets[i], true);
        }
    }
    
    // ============ Main Functions ============
    
    /**
     * @notice Receive funds from trading pool and allocate them
     * @param asset Asset received
     * @param amount Amount received
     */
    function receiveFunds(address asset, uint256 amount) 
        external 
        moreThanZero(amount) 
        nonReentrant 
    {
        if (!supportedAssets[asset]) revert Errors.PulleyController__UnsupportedAsset();
        
        // Check if funds are already in the controller (from direct transfer)
        uint256 currentBalance = IERC20(asset).balanceOf(address(this));
        if (currentBalance >= amount) {
            // Funds already transferred, no need to transferFrom
        } else {
            // Transfer funds from trading pool
            IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }
        
        // Calculate allocation
        FundAllocation memory allocation = _calculateAllocation(asset, amount);
        
        // Update allocations
        insuranceAllocations[asset] += allocation.insuranceAmount;
        tradingAllocations[asset] += allocation.tradingAmount;
        totalInsuranceFunds += allocation.insuranceAmount;
        totalTradingFunds += allocation.tradingAmount;
        
        // Send insurance portion to insurance pool
        if (allocation.insuranceAmount > 0) {
            // Approve PulleyToken to spend the asset
            IERC20(asset).approve(pulleyStablecoin, allocation.insuranceAmount);
            
            // mint insurance token on pulley
            PulleyToken(pulleyStablecoin).mint(asset, allocation.insuranceAmount);
            // add a set controller addesss after deploying and replace msg.sender with controller
        }
        
        // Trigger automated AI trading for trading portion
        if (allocation.tradingAmount > 0) {
            _initiateAITrading(asset, allocation.tradingAmount);
        }
        
        emit Events.FundsReceived(msg.sender, asset, amount);
        emit Events.FundsAllocated(asset, allocation.insuranceAmount, allocation.tradingAmount);
    }
    
   
    
    /**
     * @notice Internal function to report trading results
     * @param requestId Trading request ID
     * @param pnl Profit and loss result (positive for profit, negative for loss)
     */
    function _reportTradingResult(bytes32 requestId, int256 pnl) 
        internal 
    {
        TradeRequest storage request = activeTradeRequests[requestId];
        if (!request.isActive) revert Errors.PulleyController__TradeNotFound();
        
        // Update trade request
        request.resultPnL = pnl;
        request.isCompleted = true;
        request.isActive = false;
        
        // Update asset P&L tracking
        if (pnl >= 0) {
            assetProfitLoss[request.asset] += uint256(pnl);
        } else {
            assetProfitLoss[request.asset] -= uint256(-pnl);
        }
        
        if (pnl > 0) {
            // Profit case
            uint256 profit = uint256(pnl);
            totalProfits += profit;
            _distributeProfits(request.asset, profit);
            emit Events.TradeCompleted(requestId, request.asset, pnl, true);
        } else if (pnl < 0) {
            // Loss case
            uint256 loss = uint256(-pnl);
            totalLosses += loss;
            _handleTradingLoss(request.asset, loss);
            emit Events.TradeCompleted(requestId, request.asset, pnl, false);
        }
    }
    
    /**
     * @notice Check AI wallet PnL and handle funds (public function)
     * @param asset Asset to check
     * @return pnl Current profit/loss
     * @return fundsSent Whether funds were sent from wallet
     */
    function checkAIWalletPnL(address asset) 
        external 
      
        nonReentrant 
        returns (int256 pnl, bool fundsSent) 
    {
        if (aiWallet == address(0)) revert Errors.PulleyController__ZeroAddress();
        
        // Get session info from wallet to check PnL
        (uint256 sessionId, uint256 initialBalance, uint256 currentBalance, int256 walletPnL) = 
            Wallet(aiWallet).getSessionInfo(asset);
        
        pnl = walletPnL;
        fundsSent = false;
        
        // If there's profit, call sendFunds to retrieve it
        if (pnl > 0 && currentBalance > 0) {
            // Generate signature for sendFunds (controller is the AI signer)
            bytes32 messageHash = keccak256(abi.encodePacked(
                aiWallet,
                asset,
                currentBalance,
                Wallet(aiWallet).nonces(asset),
                block.chainid
            ));
            
            bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
            bytes memory signature = abi.encodePacked(ethSignedMessageHash);
            
            // Call wallet's sendFunds function
            Wallet(aiWallet).sendFunds(asset, currentBalance, signature);
            fundsSent = true;
        }
        
        // If there's PnL (profit or loss), report it to the system
        if (pnl != 0) {
            // Generate request ID for this check
            bytes32 requestId = keccak256(abi.encodePacked(
                aiWallet,
                asset,
                sessionId,
                block.timestamp
            ));
            
            // Report the PnL result
            _reportTradingResult(requestId, pnl);
        }
        
        emit Events.AIWalletPnLChecked(asset, pnl, fundsSent);
    }
    
    // ============ Automated Functions (Blocklock Integration) ============
    
    /**
     * @notice Automated profit/loss checking using Blocklock
     * @dev This function is called automatically based on time conditions
     */
    function automatedProfitLossCheck() external payable {
        // TODO: Implement Blocklock automation
        // For now, just emit an event
        emit Events.AutomationTriggered("profit_loss_check", block.timestamp);
    }
    
    /**
     * @notice Automated rebalancing using Blocklock
     */
    function automatedRebalancing() external payable {
        // TODO: Implement Blocklock automation
        // For now, just emit an event
        emit Events.AutomationTriggered("rebalancing", block.timestamp);
    }
    
    /**
     * @notice Handle Blocklock callback for automated actions
     * @param decryptionKey The decryption key
     */
    function _onBlocklockReceived(uint256 /* _requestId */, bytes calldata decryptionKey) internal override {
        // Decode the automated action
        // In a real implementation, you would decrypt the ciphertext here
        
        // Trigger appropriate automated action based on the decrypted data
        _executeAutomatedAction(bytes32(decryptionKey));
    }
    
    // ============ Internal Functions ============
    
    /**
     * @notice Calculate fund allocation
     * @param asset Asset to allocate
     * @param totalAmount Total amount to allocate
     * @return allocation Calculated allocation
     */
    function _calculateAllocation(address asset, uint256 totalAmount) 
        internal 
        pure 
        returns (FundAllocation memory allocation) 
    {
        allocation.asset = asset;
        allocation.totalAmount = totalAmount;
        allocation.insuranceAmount = (totalAmount * INSURANCE_PERCENTAGE) / PERCENTAGE_BASE;
        allocation.tradingAmount = totalAmount - allocation.insuranceAmount;
    }
    
    /**
     * @notice Initiate AI trading
     * @param asset Asset to trade
     * @param amount Amount to trade
     */
    function _initiateAITrading(address asset, uint256 amount) internal {
        bytes32 requestId = keccak256(abi.encode(asset, amount, block.timestamp, block.number));
        
        // Store trade request
        activeTradeRequests[requestId] = TradeRequest({
            requestId: requestId,
            asset: asset,
            amount: amount,
            timestamp: block.timestamp,
            isActive: true,
            resultPnL: 0,
            isCompleted: false
        });

        // Send funds to AI wallet if wallet is set
        if (aiWallet != address(0)) {
            // Call AI wallet's receiveFunds function
            Wallet(aiWallet).receiveFunds(address(this), asset, amount);
            
            emit Events.TradeRequestSent(requestId, asset, amount, 0);
        } else {
            emit Events.TradeRequestSent(requestId, asset, amount, 0);
        }
        
        // The AI wallet now tracks the funds and can report back profits/losses
    }
    
    /**
     * @notice Distribute profits between insurance and trading pool
     * @param asset Asset that generated profit
     * @param profitAmount Profit amount
     */
    function _distributeProfits(address asset, uint256 profitAmount) internal {
        uint256 insuranceShare = (profitAmount * INSURANCE_PROFIT_SHARE) / PERCENTAGE_BASE;
        uint256 tradingShare = profitAmount - insuranceShare;
        
        // Send insurance share to insurance pool
        if (insuranceShare > 0) {
            // In a real implementation, this would transfer assets or mint tokens
            // For now, we track the allocation
            insuranceAllocations[asset] += insuranceShare;
             (bool success, ) = tradingPool.call(
                abi.encodeWithSignature("recordTradingProfit(uint256)", insuranceShare )
            ); //@dev fix to call distribute profit rather
            require(success, "PulleyController: Failed to report profit");
        }
        
        // Send trading share back to trading pool
        if (tradingShare > 0) {
            // Report profit back to trading pool
            (bool success, ) = tradingPool.call(
                abi.encodeWithSignature("distributeTradersProfit(uint256)", tradingShare)
            ); //@dev fix to call distribute profit rather
            require(success, "PulleyController: Failed to report profit");
        }
        
        emit Events.ProfitDistributedByController(address(0), insuranceShare, tradingShare, 0);
    }
    
    /**
     * @notice Handle trading losses
     * @param asset Asset that incurred loss
     * @param lossAmount Loss amount
     */
    function _handleTradingLoss(address asset, uint256 lossAmount) internal {
        bool coveredByInsurance = false;
        
        // Check if insurance can cover the loss
        if (insuranceAllocations[asset] >= lossAmount) {
            // Full coverage: distribute insurance back to participants
            insuranceAllocations[asset] -= lossAmount;
            totalInsuranceFunds -= lossAmount;
            coveredByInsurance = true;
            
            // Burn corresponding PulleyToken insurance reserve
            PulleyToken(pulleyStablecoin).coverLoss(lossAmount);
            
            // Distribute insurance back to trading pool participants for this period
            (bool success, ) = tradingPool.call(
                abi.encodeWithSignature("distributeInsuranceRefund(address,uint256)", asset, lossAmount)
            );
            require(success, "PulleyController: Failed to distribute insurance refund");
            
        } else {
            // Partial or no coverage - report loss to trading pool
            uint256 uncoveredLoss = lossAmount;
            uint256 insuranceUsed = 0;
            
            if (insuranceAllocations[asset] > 0) {
                insuranceUsed = insuranceAllocations[asset];
                uncoveredLoss -= insuranceAllocations[asset];
                totalInsuranceFunds -= insuranceAllocations[asset];
                insuranceAllocations[asset] = 0;
                
                // Burn corresponding PulleyToken insurance reserve for used portion
                PulleyToken(pulleyStablecoin).coverLoss(insuranceUsed);
                
                // Distribute insurance back to participants for the covered portion
                (bool success, ) = tradingPool.call(
                    abi.encodeWithSignature("distributeInsuranceRefund(address,uint256)", asset, insuranceUsed)
                );
                require(success, "PulleyController: Failed to distribute insurance refund");
            }
            
            // Report uncovered loss to trading pool
            if (uncoveredLoss > 0) {
                (bool success, ) = tradingPool.call(
                    abi.encodeWithSignature("recordTradingLoss(uint256)", uncoveredLoss)
                );
                require(success, "PulleyController: Failed to report loss");
            }
        }
        
        emit Events.LossCoveredByController(address(0), lossAmount, coveredByInsurance);
    }
    
    /**
     * @notice Execute automated action based on decryption key
     * @param decryptionKey Decryption key from Blocklock
     */
    function _executeAutomatedAction(bytes32 decryptionKey) internal {
        // In a real implementation, this would decode the action from the decryption key
        // For now, we'll implement basic automated actions
        
        // Example: Automated rebalancing
        if (uint256(decryptionKey) % 2 == 0) {
            _performAutomatedRebalancing();
        } else {
            _performAutomatedProfitCheck();
        }
    }
    
    /**
     * @notice Perform automated rebalancing
     */
    function _performAutomatedRebalancing() internal {
        // Rebalance insurance and trading allocations if needed
        for (uint256 i = 0; i < assetList.length; i++) {
            address asset = assetList[i];
            uint256 totalAssetBalance = IERC20(asset).balanceOf(address(this));
            
            if (totalAssetBalance > 0) {
                uint256 targetInsurance = (totalAssetBalance * INSURANCE_PERCENTAGE) / PERCENTAGE_BASE;
                uint256 currentInsurance = insuranceAllocations[asset];
                
                if (currentInsurance < targetInsurance) {
                    uint256 needed = targetInsurance - currentInsurance;
                    if (needed <= tradingAllocations[asset]) {
                        tradingAllocations[asset] -= needed;
                        insuranceAllocations[asset] += needed;
                    }
                }
            }
        }
        
        emit Events.AutomationTriggered("rebalancing_executed", block.timestamp);
    }
    
    /**
     * @notice Perform automated profit check
     */
    function _performAutomatedProfitCheck() internal {
        // Check all active trades for completion
        // In a real implementation, this would query the AI trading system
        
        emit Events.AutomationTriggered("profit_check_executed", block.timestamp);
    }
    
    // ============ Administrative Functions ============
    
    /**
     * @notice Set AI trader address
     * @param _aiTrader New AI trader address
     */
    function setAITrader(address _aiTrader) external onlyAuthorized validAddress(_aiTrader) {
        address oldTrader = aiTrader;
        aiTrader = _aiTrader;
        emit Events.AITraderUpdated(oldTrader, _aiTrader);
    }
    
    /**
     * @notice Set AI wallet address (only authorized)
     * @param _aiWallet New AI wallet address
     */
    function setAIWallet(address payable _aiWallet) external onlyAuthorized validAddress(_aiWallet) {
        aiWallet = _aiWallet;
        emit Events.AIWalletUpdated(aiWallet, _aiWallet);
    }
    
    /**
     * @notice Update asset support
     * @param asset Asset address
     * @param supported Whether asset is supported
     */
    function updateAssetSupport(address asset, bool supported) external onlyAuthorized {
        if (supported && !supportedAssets[asset]) {
            supportedAssets[asset] = true;
            assetList.push(asset);
        } else if (!supported && supportedAssets[asset]) {
            supportedAssets[asset] = false;
            // Remove from asset list
            for (uint256 i = 0; i < assetList.length; i++) {
                if (assetList[i] == asset) {
                    assetList[i] = assetList[assetList.length - 1];
                    assetList.pop();
                    break;
                }
            }
        }
        
        emit Events.AssetSupportUpdated(asset, supported);
    }
    
    /**
     * @notice Update contract addresses
     * @param _tradingPool New trading pool address
     * @param _insurancePool New insurance pool address
     * @param _pulleyStablecoin New stablecoin address
     */
    function updateContractAddresses(
        address _tradingPool,
        address _insurancePool,
        address _pulleyStablecoin
    ) external onlyAuthorized {
        if (_tradingPool != address(0)) tradingPool = _tradingPool;
        if (_insurancePool != address(0)) insurancePool = _insurancePool;
        if (_pulleyStablecoin != address(0)) pulleyStablecoin = _pulleyStablecoin;
    }
    
    /**
     * @notice Set automation parameters
     * @param _callbackGasLimit New callback gas limit
     */
    function setAutomationParameters(uint256 _callbackGasLimit) external onlyAuthorized {
        automationCallbackGasLimit = _callbackGasLimit;
    }
    
    /**
     * @notice Fund contract for Blocklock automation
     */
    function fundAutomation() external payable {
        require(msg.value > 0, "PulleyController: Must send ETH");
        // ETH is stored in contract for Blocklock operations
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get fund allocation for an asset
     * @param asset Asset address
     * @return insuranceAmount Insurance allocation
     * @return tradingAmount Trading allocation
     */
    function getFundAllocation(address asset) 
        external 
        view 
        returns (uint256 insuranceAmount, uint256 tradingAmount) 
    {
        return (insuranceAllocations[asset], tradingAllocations[asset]);
    }
    
    /**
     * @notice Get trade request information
     * @param requestId Request ID
     * @return request Trade request details
     */
    function getTradeRequest(bytes32 requestId) 
        external 
        view 
        returns (TradeRequest memory request) 
    {
        return activeTradeRequests[requestId];
    }
    
    /**
     * @notice Get asset profit/loss
     * @param asset Asset address
     * @return pnl Current profit/loss for the asset
     */
    function getAssetPnL(address asset) external view returns (int256 pnl) {
        return int256(assetProfitLoss[asset]);
    }
    
    /**
     * @notice Get supported assets
     * @return assets Array of supported asset addresses
     */
    function getSupportedAssets() external view returns (address[] memory assets) {
        return assetList;
    }
    
    /**
     * @notice Get system metrics
     * @return totalInsurance Total insurance funds
     * @return totalTrading Total trading funds
     * @return totalProfitsAmount Total profits
     * @return totalLossesAmount Total losses
     */
    function getSystemMetrics() 
        external 
        view 
        returns (
            uint256 totalInsurance,
            uint256 totalTrading,
            uint256 totalProfitsAmount,
            uint256 totalLossesAmount
        ) 
    {
        return (totalInsuranceFunds, totalTradingFunds, totalProfits, totalLosses);
    }
    
    /**
     * @notice Check if asset is supported
     * @param asset Asset address
     * @return supported Whether asset is supported
     */
    function isAssetSupported(address asset) external view returns (bool supported) {
        return supportedAssets[asset];
    }
    
    // ============ Emergency Functions ============
    
    /**
     * @notice Emergency withdraw (admin only)
     * @param asset Asset to withdraw (address(0) for ETH)
     * @param amount Amount to withdraw
     * @param to Recipient address
     */
    function emergencyWithdraw(address asset, uint256 amount, address to) 
        external 
        onlyAuthorized 
        validAddress(to) 
    {
        if (asset == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }
    
    // ============ Receive Function ============
    // Receive function is inherited from AbstractBlocklockReceiver
}
