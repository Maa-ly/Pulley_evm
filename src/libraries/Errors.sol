//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title Errors
 * @notice Library containing all custom errors used across the Pulley Protocol
 */
library Errors {
    
    // ============ Common Errors ============
    error ZeroAmount();
    error ZeroAddress();
    error InvalidAmount();
    error NotAuthorized();
    error InvalidAddress();
    
    // ============ Trading Pool Errors ============
    error TradingPool__ZeroAmount();
    error TradingPool__ZeroAddress();
    error TradingPool__NotAuthorized();
    error TradingPool__UnsupportedAsset();
    error TradingPool__InsufficientBalance();
    error TradingPool__InsufficientPoolTokens();
    error TradingPool__ThresholdNotReached();
    error TradingPool__TradingPeriodActive();
    error TradingPool__NoActiveTradingPeriod();
    error TradingPool__PeriodNotCompleted();
    error TradingPool__ProfitAlreadyClaimed();
    error TradingPool__NoContributionInPeriod();
    error TradingPool__InvalidPeriodId();
    error TradingPool__CannotJoinActivePeriod();
    error TradingPool__AssetNotConfigured();
    error TradingPool__NotController();
    
    // ============ Controller Errors ============
    error PulleyController__ZeroAmount();
    error PulleyController__ZeroAddress();
    error PulleyController__NotAuthorized();
    error PulleyController__UnsupportedAsset();
    error PulleyController__RequestNotFound();
    error PulleyController__TradeNotFound();
    error PulleyController__InvalidAllocation();
    error PulleyController__AIWalletNotSet();
    error PulleyController__PeriodNotActive();
    error PulleyController__InvalidPeriodId();
    
    // ============ Wallet Errors ============
    error Wallet__OnlyController();
    error Wallet__OnlyAISigner();
    error Wallet__InvalidSignature();
    error Wallet__InsufficientBalance();
    error Wallet__InvalidAmount();
    error Wallet__SessionNotActive();
    error Wallet__InvalidSession();
    
    // ============ PulleyToken Errors ============
    error PulleyToken__ZeroAmount();
    error PulleyToken__ZeroAddress();
    error PulleyToken__NotAuthorized();
    error PulleyToken__UnsupportedAsset();
    error PulleyToken__InsufficientBackingValue();
    error PulleyToken__InsufficientReserve();
    error PulleyToken__InvalidController();
    
    // ============ Permission Manager Errors ============
    error PermissionManager__NotOwner();
    error PermissionManager__ZeroAddress();
    error PermissionManager__AlreadyAuthorized();
    error PermissionManager__NotAuthorized();
    error PermissionManager__InvalidFunction();
    
    // ============ Clone Errors ============
    error Clone__InvalidConfiguration();
    error Clone__AssetAlreadySet();
    error Clone__ThresholdTooLow();
    error Clone__InitializationFailed();
}
