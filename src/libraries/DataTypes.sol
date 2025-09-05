//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title DataTypes
 * @notice Library containing all data structures used across the Pulley Protocol
 */
library DataTypes {
    
    /**
     * @notice Trading period structure
     */
    struct TradingPeriod {
        uint256 startTime;
        uint256 endTime;
        uint256 totalPoolTokensAtStart;
        uint256 totalUsdValueAtStart;
        mapping(address => uint256) userTokensAtStart;
        mapping(address => uint256) userUsdContributionAtStart;
        mapping(address => uint256) userEstimatedProfit;
        mapping(address => uint256) userEstimatedLoss;
        mapping(address => bool) userProfitClaimed;
        bool isActive;
        bool profitsDistributed;
        int256 periodPnL; // Period profit/loss
        uint256 profitPerDollar; // Profit per dollar contributed
        uint256 insuranceRefundPerDollar; // Insurance refund per dollar contributed
        uint256 insuranceRefundAmount; // Total insurance refund amount
    }
    
    /**
     * @notice Asset configuration structure
     */
    struct AssetConfig {
        bool isSupported;
        uint8 decimals;
        uint256 threshold; // Threshold for this specific asset
        address priceFeed; // Chainlink price feed
        uint256 currentPeriodId; // Current trading period for this asset
        uint256 totalBalance; // Current balance of this asset
        bool periodActive; // Whether trading period is active for this asset
    }
    
    /**
     * @notice Trade request structure for AI trading
     */
    struct TradeRequest {
        bytes32 requestId;
        address asset;
        uint256 amount;
        uint256 timestamp;
        uint256 periodId;
        bool isActive;
        int256 resultPnL;
        bool isCompleted;
    }
    
    /**
     * @notice Fund allocation structure
     */
    struct FundAllocation {
        uint256 insuranceAmount; // 15%
        uint256 tradingAmount; // 85%
        uint256 totalAmount;
        address asset;
    }
    
    /**
     * @notice Pool clone configuration
     */
    struct PoolCloneConfig {
        address nativeAsset; // Chain's native wrapped token
        address pulleyToken; // PulleyToken address
        address customAsset; // Third asset chosen during setup
        uint256 nativeThreshold;
        uint256 pulleyThreshold;
        uint256 customThreshold;
        uint8 customAssetDecimals; // Decimals for custom asset
        string poolName;
        string poolSymbol;
    }
    
    /**
     * @notice Session info for AI wallet
     */
    struct TradingSession {
        uint256 sessionId;
        address asset;
        uint256 initialBalance;
        uint256 periodId;
        uint256 startTime;
        bool isActive;
    }
}
