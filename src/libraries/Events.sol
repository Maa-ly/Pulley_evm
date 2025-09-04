//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title Events
 * @notice Library containing all events used across the Pulley Protocol
 */
library Events {
    
    // ============ Trading Pool Events ============
    event Deposited(address indexed user, address indexed asset, uint256 amount, uint256 poolTokens, uint256 usdValue);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount, uint256 poolTokensBurned);
    event ThresholdReached(address indexed asset, uint256 totalAmount, uint256 timestamp, uint256 periodId);
    event FundsSentToController(address indexed asset, uint256 totalUsdValue, uint256 periodId);
    event ProfitRecorded(address indexed asset, uint256 amount, uint256 periodId);
    event ProfitDistributed(address indexed asset, uint256 insuranceShare, uint256 poolShare, uint256 periodId);
    event LossRecorded(address indexed asset, uint256 amount, uint256 periodId);
    event LossCovered(address indexed asset, uint256 lossAmount, bool coveredByInsurance, uint256 coveredAmount);
    event AssetAdded(address indexed asset, uint8 decimals, uint256 threshold, address priceFeed);
    event AssetRemoved(address indexed asset);
    event ThresholdUpdated(uint256 newThreshold);
    event PriceFeedUpdated(address indexed asset, address indexed priceFeed);
    event AssetConfigUpdated(address indexed asset, uint256 newThreshold, address newPriceFeed);
    event ProfitWithdrawn(address indexed user, address indexed asset, uint256 assetAmount, uint256 usdValue, uint256 periodId);
    event ProfitReinvested(address indexed user, address indexed asset, uint256 profitAmount, uint256 newPoolTokens, uint256 periodId);
    event TradingPeriodStarted(address indexed asset, uint256 indexed periodId, uint256 startTime, uint256 threshold);
    event TradingPeriodEnded(address indexed asset, uint256 indexed periodId, uint256 endTime, int256 pnl);
    event UserJoinedPeriod(address indexed user, address indexed asset, uint256 indexed periodId, uint256 contribution);
    event CannotJoinActivePeriod(address indexed user, address indexed asset, uint256 activePeriodId);
    
    // ============ Controller Events ============
    event FundsReceived(address indexed from, address indexed asset, uint256 amount);
    event FundsAllocated(address indexed asset, uint256 insuranceAmount, uint256 tradingAmount);
    event TradeRequestSent(bytes32 indexed requestId, address indexed asset, uint256 amount, uint256 periodId);
    event TradeCompleted(bytes32 indexed requestId, address indexed asset, int256 pnl, bool isProfit);
    event ProfitDistributedByController(address indexed asset, uint256 insuranceShare, uint256 tradingShare, uint256 periodId);
    event LossCoveredByController(address indexed asset, uint256 lossAmount, bool coveredByInsurance);
    event AssetSupportUpdated(address indexed asset, bool supported);
    event AITraderUpdated(address indexed oldTrader, address indexed newTrader);
    event AIWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event AutomationTriggered(string action, uint256 timestamp);
    event PeriodProfitReported(address indexed asset, uint256 indexed periodId, int256 pnl, uint256 usdValue);
    
    // ============ Wallet Events ============
    event FundsReceivedByWallet(address indexed from, address indexed asset, uint256 amount, uint256 sessionId);
    event ProfitSentByWallet(address indexed to, address indexed asset, uint256 amount, int256 pnl);
    event SessionStarted(address indexed asset, uint256 indexed sessionId, uint256 initialBalance, uint256 periodId);
    event SessionCompleted(address indexed asset, uint256 indexed sessionId, int256 pnl, uint256 periodId);
    event AISignerUpdated(address indexed oldSigner, address indexed newSigner);
    event AssetAddedToWallet(address indexed asset, address priceFeed, uint8 decimals);
    
    // ============ PulleyToken Events ============
    event Minted(address indexed to, uint256 amount, uint256 backingValue);
    event Burned(address indexed from, uint256 amount, uint256 backingValue);
    event LossCoveredByToken(uint256 lossAmount, uint256 newInsuranceReserve);
    event ProfitsAddedToToken(uint256 profitAmount, uint256 newInsuranceReserve);
    event ContractsUpdated(address indexed controller, address indexed engine);
    event AssetSupportUpdatedInToken(address indexed asset, bool supported);
    
    // ============ Clone Events ============
    event PoolCloneCreated(address indexed clone, address indexed creator, string name);
    event CloneInitialized(address indexed clone, address nativeAsset, address pulleyToken, address customAsset);
    event CloneConfigUpdated(address indexed clone, address indexed asset, uint256 newThreshold);
    
    // ============ Permission Events ============
    event PermissionGranted(address indexed user, address indexed target, bytes4 indexed functionSelector);
    event PermissionRevoked(address indexed user, address indexed target, bytes4 indexed functionSelector);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}
