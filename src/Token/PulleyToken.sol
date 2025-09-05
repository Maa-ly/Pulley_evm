//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPermissionManager} from "../Permission/interface/IPermissionManager.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {PriceConvertor} from "../lib/PriceConvertor.sol";

/**
 * @title PulleyToken
 * @author Core-Connect Team
 * @notice Floating stablecoin that grows with utilization - anyone can mint
 * @dev This token grows in value based on system utilization, not 1:1 backing
 */
contract PulleyToken is ERC20, ERC20Permit, ReentrancyGuard, PriceConvertor {
    using SafeERC20 for IERC20;

    // ============ State Variables ============
    
    address public permissionManager;
    address public pulleyTokenEngine;
    address public controller;
    address public tradingPool;
    
    // Insurance mechanism
    uint256 public insuranceReserve; // Insurance funds from trading pool
    uint256 public totalBackingValue; // Total USD value backing tokens
    uint256 public utilizationRate; // Current utilization rate (basis points)
    uint256 public growthRate; // Current growth rate (basis points per day)
    uint256 public lastGrowthUpdate; // Last time growth was applied
    
    // Growth parameters
    uint256 public baseGrowthRate = 100; // 1% base daily growth
    uint256 public utilizationMultiplier = 50; // 0.5% additional per utilization point
    uint256 public maxGrowthRate = 1000; // 10% max daily growth
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant GROWTH_INTERVAL = 1 days;
    
    // Asset backing
    mapping(address => uint256) public assetBacking;
    mapping(address => bool) public supportedAssets;
    address[] public backingAssets;
    
    // ============ Events ============
    // Events are now imported from libraries
    
    // ============ Errors ============
    // Errors are now imported from libraries
    
    // ============ Modifiers ============
    
    modifier onlyAuthorized() {
        if (msg.sender != pulleyTokenEngine && msg.sender != controller) {
            if (permissionManager != address(0)) {
                require(
                    IPermissionManager(permissionManager).hasPermissions(msg.sender, msg.sig),
                    "PulleyToken: not authorized"
                );
            } else {
                revert Errors.PulleyToken__NotAuthorized();
            }
        }
        _;
    }
    
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert Errors.PulleyToken__ZeroAmount();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(
        string memory name,
        string memory symbol,
        address _permissionManager,
        address[] memory _supportedAssets
    ) ERC20(name, symbol) ERC20Permit(name) {
        permissionManager = _permissionManager;
        lastGrowthUpdate = block.timestamp;
        
        // Set supported assets for initial minting
        for (uint256 i = 0; i < _supportedAssets.length; i++) {
            supportedAssets[_supportedAssets[i]] = true;
            backingAssets.push(_supportedAssets[i]);
            emit Events.AssetSupportUpdatedInToken(_supportedAssets[i], true);
        }
    }
    
    // ============ Public Minting (Anyone can mint) ============
    
    /**
     * @notice Mint Pulley tokens by providing backing assets (anyone can call)
     * @param asset The backing asset to deposit
     * @param backingAmount Amount of backing asset to deposit
     * @return tokensToMint Amount of Pulley tokens minted
     */
    function mint(address asset, uint256 backingAmount) 
        external 
        moreThanZero(backingAmount) 
        nonReentrant 
        returns (uint256 tokensToMint) 
    {
        if (!supportedAssets[asset]) revert Errors.PulleyToken__UnsupportedAsset();
        
        // Apply growth before minting
        _updateGrowth();
        
        // Get current token price (floating, not 1:1)
        uint256 currentPrice = getCurrentPrice();
        
        // Calculate tokens to mint based on current price
        uint256 usdValue = _getAssetUsdValue(asset, backingAmount);
        tokensToMint = (usdValue * 1e18) / currentPrice; // Price in 18 decimals
        
        // Transfer backing asset
        IERC20(asset).safeTransferFrom(msg.sender, address(this), backingAmount);
        
        // Update backing
        assetBacking[asset] += backingAmount;
        totalBackingValue += usdValue;
        
        // Different minting logic based on caller
        if (msg.sender == controller) {
            // Trading pool minting: insurance + totalSupply
            insuranceReserve += tokensToMint;
            _mint(msg.sender, tokensToMint);
           //_mint(address(this), tokensToMint); // Mint to contract as insurance
        } else {
            // External user minting: just totalSupply
            _mint(msg.sender, tokensToMint);
        }
        
        emit Events.Minted(msg.sender, tokensToMint, backingAmount);
    }
    
    /**
     * @notice Burn Pulley tokens to redeem backing assets
     * @param asset The asset to receive
     * @param tokenAmount Amount of tokens to burn
     * @return backingReturned Amount of backing asset returned
     */
    function burn(address asset, uint256 tokenAmount) 
        external
        moreThanZero(tokenAmount) 
        nonReentrant 
        returns (uint256 backingReturned) 
    {
        if (!supportedAssets[asset]) revert Errors.PulleyToken__UnsupportedAsset();
        if (balanceOf(msg.sender) < tokenAmount) revert Errors.PulleyToken__InsufficientBackingValue();
        
        // Apply growth before burning
        _updateGrowth();
        
        // Get current token price
        uint256 currentPrice = getCurrentPrice();
        
        // Calculate USD value of tokens being burned
        uint256 usdValue = (tokenAmount * currentPrice) / 1e18;
        
        // Calculate proportional backing to return
        if (totalBackingValue > 0) {
            backingReturned = (usdValue * assetBacking[asset]) / totalBackingValue;
        } else {
            backingReturned = 0;
        }
        
        if (assetBacking[asset] < backingReturned) {
            backingReturned = assetBacking[asset]; // Return what we have
        }
        
        // Update backing
        assetBacking[asset] -= backingReturned;
        totalBackingValue -= (backingReturned > usdValue ? usdValue : backingReturned);
        
        // Burn tokens
        _burn(msg.sender, tokenAmount);
        
        // Transfer backing asset
        if (backingReturned > 0) {
            IERC20(asset).safeTransfer(msg.sender, backingReturned);
        }
        
        emit Events.Burned(msg.sender, tokenAmount, backingReturned);
    }
    
    // ============ Growth Mechanism ============
    
    /**
     * @notice Update growth based on utilization (can be called by anyone)
     */
    function updateGrowth() external {
        _updateGrowth();
    }
    
    /**
     * @notice Internal function to apply growth
     */
    function _updateGrowth() internal {
        if (block.timestamp < lastGrowthUpdate + GROWTH_INTERVAL) {
            return; // Not enough time passed
        }
        
        if (totalSupply() == 0) {
            lastGrowthUpdate = block.timestamp;
            return; // No tokens to grow
        }
        
        // Calculate periods elapsed
        uint256 periodsElapsed = (block.timestamp - lastGrowthUpdate) / GROWTH_INTERVAL;
        
        // Calculate current growth rate based on utilization
        uint256 currentGrowthRate = _calculateGrowthRate();
        
        // Apply compound growth for each period
        uint256 currentSupply = totalSupply();
        uint256 newSupply = currentSupply;
        
        for (uint256 i = 0; i < periodsElapsed; i++) {
            newSupply = (newSupply * (BASIS_POINTS + currentGrowthRate)) / BASIS_POINTS;
        }
        
        if (newSupply > currentSupply) {
            uint256 growthAmount = newSupply - currentSupply;
            
            // Mint growth to insurance reserve (increases token value for holders)
            insuranceReserve += growthAmount;
            _mint(address(this), growthAmount);
            
            emit Events.ProfitsAddedToToken(growthAmount, insuranceReserve);
        }
        
        lastGrowthUpdate = block.timestamp;
        growthRate = currentGrowthRate;
    }
    
    /**
     * @notice Calculate current growth rate based on utilization
     */
    function _calculateGrowthRate() internal view returns (uint256) {
        // Growth rate = base rate + (utilization * multiplier)
        uint256 rate = baseGrowthRate + (utilizationRate * utilizationMultiplier) / BASIS_POINTS;
        
        // Cap at maximum
        if (rate > maxGrowthRate) {
            rate = maxGrowthRate;
        }
        
        return rate;
    }
    
    // ============ Price Calculation ============
    
    /**
     * @notice Get current token price (floating, not 1:1)
     * @return price Current price in 18 decimals (USD per token)
     */
    function getCurrentPrice() public view returns (uint256 price) {
        if (totalSupply() == 0) {
            return 1e18; // Initial price: 1 USD
        }
        
        // Price increases with growth and utilization
        // Base price + growth premium + utilization premium
        uint256 basePrice = 1e18; // 1 USD base
        
        // Growth premium based on total growth applied
        uint256 growthPremium = (insuranceReserve * 1e18) / totalSupply();
        
        // Utilization premium
        uint256 utilizationPremium = (utilizationRate * 1e14) / BASIS_POINTS; // Max 1% premium
        
        price = basePrice + growthPremium + utilizationPremium;
    }
    
    // ============ Authorized Functions ============
    
    /**
     * @notice Update utilization rate (called by controller)
     */
    function updateUtilization(uint256 newUtilizationRate) external onlyAuthorized {
        utilizationRate = newUtilizationRate;
        
        // Trigger growth update when utilization changes
        _updateGrowth();
        
        emit Events.ProfitsAddedToToken(0, insuranceReserve); // Utilization updated
    }
    
    /**
     * @notice Cover losses using insurance reserve
     */
    function coverLoss(uint256 lossAmount) external onlyAuthorized moreThanZero(lossAmount) {
        if (insuranceReserve < lossAmount) revert Errors.PulleyToken__InsufficientReserve();
        
        insuranceReserve -= lossAmount;
        
        // Burn tokens from insurance reserve
        _burn(msg.sender, lossAmount);
        
        emit Events.LossCoveredByToken(lossAmount, insuranceReserve);
    }
    
    /**
     * @notice Add profits to insurance reserve
     */
    function addProfits(uint256 profitAmount) external onlyAuthorized moreThanZero(profitAmount) {
        insuranceReserve += profitAmount;
        
        
        // Mint tokens to insurance reserve (increases token value)
        _mint(msg.sender, profitAmount);
    }
    
    // ============ Administrative Functions ============
    
    /**
     * @notice Set contract addresses
     */
    function setContracts(address _pulleyTokenEngine, address _controller, address _tradingPool) external onlyAuthorized {
        if (_pulleyTokenEngine != address(0)) pulleyTokenEngine = _pulleyTokenEngine;
        if (_controller != address(0)) controller = _controller;
        if (_tradingPool != address(0)) tradingPool = _tradingPool;
    }
    
    /**
     * @notice Update asset support
     */
    function updateAssetSupport(address asset, bool supported) external onlyAuthorized {
        if (supported && !supportedAssets[asset]) {
            supportedAssets[asset] = true;
            backingAssets.push(asset);
        } else if (!supported && supportedAssets[asset]) {
            supportedAssets[asset] = false;
            // Remove from array
            for (uint256 i = 0; i < backingAssets.length; i++) {
                if (backingAssets[i] == asset) {
                    backingAssets[i] = backingAssets[backingAssets.length - 1];
                    backingAssets.pop();
                    break;
                }
            }
        }
        
        emit Events.AssetSupportUpdatedInToken(asset, supported);
    }
    
    /**
     * @notice Update growth parameters
     */
    function updateGrowthParameters(
        uint256 _baseGrowthRate,
        uint256 _utilizationMultiplier,
        uint256 _maxGrowthRate
    ) external onlyAuthorized {
        baseGrowthRate = _baseGrowthRate;
        utilizationMultiplier = _utilizationMultiplier;
        maxGrowthRate = _maxGrowthRate;
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get backing information
     */
    function getBackingInfo(address asset) external view returns (uint256 backing) {
        return assetBacking[asset];
    }
    
    /**
     * @notice Get supported assets
     */
    function getSupportedAssets() external view returns (address[] memory) {
        return backingAssets;
    }
    
    /**
     * @notice Get growth metrics
     */
    function getGrowthMetrics() 
        external
        view 
        returns (
            uint256 currentPrice,
            uint256 currentGrowthRate,
            uint256 currentUtilization,
            uint256 reserve
        ) 
    {
        return (getCurrentPrice(), _calculateGrowthRate(), utilizationRate, insuranceReserve);
    }
    
    /**
     * @notice Check if asset is supported
     */
    function isAssetSupported(address asset) external view returns (bool) {
        return supportedAssets[asset];
    }
}