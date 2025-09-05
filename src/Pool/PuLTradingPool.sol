//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPermissionManager} from "../Permission/interface/IPermissionManager.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IPulleyController} from "../interfaces/IPulleyController.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {PriceConvertor} from "../lib/PriceConvertor.sol";



/**
 * @title PulTradingPool
 * @author Core-Connect Team
 * @notice AI-based trading pool with threshold mechanism and oracle-based pricing
 * @dev People deposit, get pool tokens, when threshold reached funds go to controller
 */
contract PulTradingPool is ERC20, ReentrancyGuard, PriceConvertor {

  using SafeERC20 for IERC20;
    
    // ============ State Variables ============

    address public permissionManager;
    address public controller;
    address public pulleyToken; // Pulley token for insurance
    
    // Threshold mechanism
    uint256 public threshold = 10000 * 1e18; // 10,000 USD threshold
    uint256 public totalDeposited; // Total USD value deposited
    
    // Asset management with oracle pricing
    mapping(address => uint256) public assetBalances; // Asset balances
    mapping(address => bool) public supportedAssets; // Supported assets
    mapping(address => uint256) public assetThresholds; // Threshold per asset
    address[] public assetList;
    
    // Asset-specific trading periods - now supports multiple concurrent periods
    mapping(address => mapping(uint256 => DataTypes.TradingPeriod)) public assetPeriods;
    mapping(address => uint256) public assetCurrentPeriodId;
    mapping(address => bool) public assetPeriodActive; // Deprecated - kept for compatibility
    
    // New: Multiple concurrent periods support
    mapping(address => uint256[]) public assetActivePeriods; // Track active period IDs per asset
    mapping(address => mapping(uint256 => uint256)) public periodAssetAllocation; // Asset amount allocated to each period
    mapping(address => uint256) public assetAvailableForTrading; // Available funds for new periods

    // User tracking
    mapping(address => uint256) public userPoolTokens; // User pool token balance
    mapping(address => mapping(address => uint256)) public userAssetDeposits; // User deposits per asset
    
    // Pool metrics
    uint256 public totalPoolValue; // Total USD value in pool
    uint256 public totalProfits; // Total profits received
    uint256 public totalLosses; // Total losses incurred
    uint256 public lastThresholdTransfer; // Last time funds were sent to controller
    
    // Insurance tracking
    uint256 public insuranceFunds; // 15% insurance allocation
    uint256 public totalLossesCovered; // Losses covered by insurance
    uint256 public totalInsuranceRefunds; // Total insurance refunds distributed
    
    // ============ Events & Errors ============
    // Events and errors are now imported from libraries

    // ============ Modifiers ============
    
    modifier onlyAuthorized() {
        if (permissionManager != address(0)) {
        require(
                IPermissionManager(permissionManager).hasPermissions(msg.sender, msg.sig),
                "TradingPool: not authorized"
        );
        } else {
            require(msg.sender == controller, "TradingPool: only controller");
        }
        _;
    }

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert Errors.TradingPool__ZeroAmount();
        _;
    }
    
    modifier supportedAsset(address asset) {
        if (!supportedAssets[asset]) revert Errors.TradingPool__UnsupportedAsset();
        _;
    }

    modifier onlyController() {
        if (msg.sender != controller) revert Errors.TradingPool__NotController();
        _;
    }
    
    // ============ Constructor ============
    
    constructor() ERC20("", "") {
        // Constructor is minimal - initialization happens in initialize()
    }
    
    // ============ Initializer ============
    
    /**
     * @notice Initialize the trading pool with configuration
     * @param _name Pool token name
     * @param _symbol Pool token symbol
     * @param _permissionManager Permission manager address
     * @param _controller Controller address
     * @param _pulleyToken PulleyToken address
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _permissionManager,
        address _controller,
        address _pulleyToken
    ) external {
        if (permissionManager != address(0)) revert Errors.Clone__InitializationFailed();
        if (_permissionManager == address(0) || _controller == address(0)) {
            revert Errors.TradingPool__ZeroAddress();
        }
        
        // Initialize ERC20 name and symbol (requires storage manipulation)
        _name = _name;
        _symbol = _symbol;
        
        permissionManager = _permissionManager;
        controller = _controller;
        pulleyToken = _pulleyToken;
    }
    


 // ============ Main Functions ============
    
    /**
     * @notice Deposit assets and receive pool tokens based on oracle pricing
     * @param asset Asset to deposit
     * @param amount Amount to deposit
     * @return poolTokens Amount of pool tokens minted
     */
    function deposit(address asset, uint256 amount) 
        external
        moreThanZero(amount)
        supportedAsset(asset) 
        nonReentrant
        returns (uint256 poolTokens) 
    {
        // Continuous trading periods - deposits are always allowed
        
        // Get USD value using oracle
        uint256 usdValue = _getAssetUsdValue(asset, amount);
        
        // Calculate pool tokens based on current pool state
        if (totalSupply() == 0) {
            // First deposit, minus min share to prevent share manipulation
            poolTokens = usdValue - 1e18;
        } else {
            // Subsequent deposits: proportional to pool value
            poolTokens = (usdValue * totalSupply()) / totalPoolValue;
        }

        // Update balances
        assetBalances[asset] += amount;
        userAssetDeposits[msg.sender][asset] += amount;
        userPoolTokens[msg.sender] += poolTokens;
        totalDeposited += usdValue;
        totalPoolValue += usdValue;
        
        // Update available funds for trading (continuous periods)
        assetAvailableForTrading[asset] += usdValue;
        
        // Record user contribution for current trading period
        _recordUserContributionForPeriod(msg.sender, asset, usdValue);
        
        // Mint pool tokens
        _mint(msg.sender, poolTokens);
        
        // Transfer asset from user
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        emit Events.Deposited(msg.sender, asset, amount, poolTokens, usdValue);
        
        // Check if we can start a new trading period
        _checkAndStartNewTradingPeriod(asset);
        
        return poolTokens;
    }

      /**
     * @notice Withdraw assets by burning pool tokens
     * @param asset Asset to withdraw
     * @param poolTokenAmount Amount of pool tokens to burn
     * @return assetAmount Amount of asset withdrawn
     */
    function withdraw(address asset, uint256 poolTokenAmount) 
        external
        moreThanZero(poolTokenAmount) 
        supportedAsset(asset) 
        nonReentrant
        returns (uint256 assetAmount) 
    {
        if (balanceOf(msg.sender) < poolTokenAmount) revert Errors.TradingPool__InsufficientPoolTokens();
        
        // Query current PnL before withdrawal to apply any pending losses
        _queryAndApplyPendingPnL();
        
        // Calculate user's share of the asset
        uint256 userShare = (poolTokenAmount * 1e18) / balanceOf(msg.sender);
        assetAmount = (userAssetDeposits[msg.sender][asset] * userShare) / 1e18;
        
        if (assetBalances[asset] < assetAmount) {
            // If not enough of this specific asset, give proportional share of total pool
            assetAmount = (poolTokenAmount * assetBalances[asset]) / totalSupply();
        }
        
        // Get USD value for accounting
        uint256 usdValue = _getAssetUsdValue(asset, assetAmount);

        // Update balances
        assetBalances[asset] -= assetAmount;
        if (userAssetDeposits[msg.sender][asset] >= assetAmount) {
            userAssetDeposits[msg.sender][asset] -= assetAmount;
        } else {
            userAssetDeposits[msg.sender][asset] = 0;
        }
        userPoolTokens[msg.sender] -= poolTokenAmount;
        totalPoolValue -= usdValue;
        
        // Burn pool tokens
        _burn(msg.sender, poolTokenAmount);
        
        // Transfer asset
        IERC20(asset).safeTransfer(msg.sender, assetAmount);
        
        emit Events.Withdrawn(msg.sender, asset, assetAmount, poolTokenAmount);
        
        return assetAmount;
    }
    
    /**
     * @notice Query PnL from controller and apply any pending losses before withdrawal
     */
    function _queryAndApplyPendingPnL() internal {
        if (controller != address(0)) {
            // Get current system metrics from controller
            (uint256 controllerInsuranceFunds, uint256 tradingFunds, uint256 profits, uint256 losses) = 
                IPulleyController(controller).getSystemMetrics();
            
            // Check if there are unreported losses that need to be applied
            if (losses > totalLosses) {
                uint256 pendingLoss = losses - totalLosses;
                
                // Apply the pending loss through the normal loss mechanism
                (bool success, ) = controller.call(
                    abi.encodeWithSignature("reportTradingResult(bytes32,int256)", 
                        keccak256(abi.encode("pending_loss", block.timestamp)), 
                        -int256(pendingLoss)
                    )
                );
                // Don't revert if call fails, just proceed with current state
            }
        }
    }
    

    

       /**
     * @notice Record trading profit and distribute (called by controller)
     */
    function recordProfit(uint256 profitAmount) external onlyAuthorized moreThanZero(profitAmount) {
        totalProfits += profitAmount;
        totalPoolValue += profitAmount;
        
        // Add to insurance funds
        insuranceFunds +=  profitAmount;
        
        // Mint Pulley tokens for insurance (insurance + totalSupply)
        if (pulleyToken != address(0) &&  profitAmount > 0) {
            (bool success, ) = pulleyToken.call(
                abi.encodeWithSignature("mint(address,uint256)", address(this),  profitAmount)
            );
            // Don't revert if call fails
        }
        
        emit Events.ProfitRecorded(address(0), profitAmount, 0);
    }


    



    

    


    /**
     * @notice Record trading loss and handle coverage (called by controller)
     */
    function recordLoss(uint256 lossAmount) external onlyController moreThanZero(lossAmount) {
        totalLosses += lossAmount;
        
        // Check if insurance can cover the loss
        bool coveredByInsurance = false;
        uint256 coveredAmount = 0;
        // Get insurance funds from controller
        uint256 _insuranceFunds = getInsuranceFunds();
        
        if (_insuranceFunds >= lossAmount) {
            // Insurance covers full loss
            _insuranceFunds -= lossAmount;
            totalLossesCovered += lossAmount;
            coveredByInsurance = true;
            coveredAmount = lossAmount;
            
            // Use Pulley token insurance to cover
            if (pulleyToken != address(0)) {
                (bool success, ) = pulleyToken.call(
                    abi.encodeWithSignature("coverLoss(uint256)", lossAmount)
                );
                // Don't revert if call fails
            }
        } else if (insuranceFunds > 0) {
            // Insurance covers partial loss
            coveredAmount = _insuranceFunds;
            totalLossesCovered += coveredAmount;
            _insuranceFunds = 0;
            
            // Use available Pulley token insurance
            if (pulleyToken != address(0)) {
                (bool success, ) = pulleyToken.call(
                    abi.encodeWithSignature("coverLoss(uint256)", coveredAmount)
                );
                // Don't revert if call fails
            }
            
            // Remaining loss affects pool value
            uint256 remainingLoss = lossAmount - coveredAmount;
            if (totalPoolValue >= remainingLoss) {
                totalPoolValue -= remainingLoss;
            } else {
                totalPoolValue = 0;
            }
        } else {
            // No insurance coverage - full loss affects pool
            if (totalPoolValue >= lossAmount) {
                totalPoolValue -= lossAmount;
            } else {
                totalPoolValue = 0;
            }
        }
        
        emit Events.LossRecorded(address(0), lossAmount, 0);
        emit Events.LossCovered(address(0), lossAmount, coveredByInsurance, coveredAmount);
    }
    



    //=================== Internal Functions ===================
    


    






   
    // ============ Administrative Functions ============
    
    /**
     * @notice Add supported asset with decimals
     */
    function addAsset(address asset, uint8 decimals, uint256 assetThreshold, address priceFeed) external onlyAuthorized {
        if (asset == address(0)) revert Errors.TradingPool__ZeroAddress();
        if (assetThreshold == 0) revert Errors.Clone__ThresholdTooLow();
        
        if (!supportedAssets[asset]) {
            supportedAssets[asset] = true;
            assetDecimals[asset] = decimals;
            assetThresholds[asset] = assetThreshold;
            priceFeeds[asset] = AggregatorV3Interface(priceFeed);
            assetList.push(asset);
            
            emit Events.AssetAdded(asset, decimals, assetThreshold, priceFeed);
        }
    }
    
    /**
     * @notice Remove supported asset
     */
    function removeAsset(address asset) external onlyAuthorized {
        if (supportedAssets[asset]) {
            supportedAssets[asset] = false;
            assetDecimals[asset] = 0;
            priceFeeds[asset] = AggregatorV3Interface(address(0));
            
            // Remove from array
            for (uint256 i = 0; i < assetList.length; i++) {
                if (assetList[i] == asset) {
                    assetList[i] = assetList[assetList.length - 1];
                    assetList.pop();
                    break;
                }
            }
            
            emit Events.AssetRemoved(asset);
        }
    }
    
    /**
     * @notice Update threshold
     */
    function updateThreshold(uint256 newThreshold) external onlyAuthorized {
        threshold = newThreshold;
        emit Events.ThresholdUpdated(newThreshold);
    }
    
    /**
     * @notice Update controller address
     */
    function updateController(address newController) external onlyAuthorized {
        if (newController == address(0)) revert Errors.TradingPool__ZeroAddress();
        controller = newController;
    }
    
    /**
     * @notice Set price feed for an asset
     */
    function setPriceFeed(address asset, address priceFeed) external onlyAuthorized {
        priceFeeds[asset] = AggregatorV3Interface(priceFeed);
        emit Events.PriceFeedUpdated(asset, priceFeed);
    }
    
    /**
     * @notice Update Pulley token address
     */
    function updatePulleyToken(address newPulleyToken) external onlyAuthorized {
        if (newPulleyToken == address(0)) revert Errors.TradingPool__ZeroAddress();
        pulleyToken = newPulleyToken;
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get user information
     */
    function getUserInfo(address user) 
        public 
        view 
        returns (uint256 poolTokenBalance, uint256 poolShare) 
    {
        poolTokenBalance = balanceOf(user);
        if (totalSupply() > 0) {
            poolShare = (poolTokenBalance * 1e18) / totalSupply(); // Share in 18 decimals
        } else {
            poolShare = 0;
        }
    }
    
    /**
     * @notice Get pool metrics
     */
    function getPoolMetrics() 
        public
        view 
        returns (
            uint256 totalValue,
            uint256 deposited,
            uint256 profits,
            uint256 losses,
            uint256 thresholdAmount
        ) 
    {
        return (totalPoolValue, totalDeposited, totalProfits, totalLosses, threshold);
    }
    
    /**
     * @notice Get supported assets
     */
    function getSupportedAssets() public view returns (address[] memory) {
        return assetList;
    }
    

    
    /**
     * @notice Get asset balance and USD value
     */
    function getAssetInfo(address asset) 
        public
        view 
        returns (uint256 balance, uint256 usdValue, uint8 decimals) 
    {
        balance = assetBalances[asset];
        usdValue = _getAssetUsdValue(asset, balance);
        decimals = assetDecimals[asset];
    }
    
    /**
     * @notice Get user's asset deposits
     */
    function getUserAssetDeposit(address user, address asset) public view returns (uint256) {
        return userAssetDeposits[user][asset];
    }

function getInsuranceFunds() public view returns (uint256) {
        if (controller == address(0)) return 0;
        
        (bool success, bytes memory data) = controller.staticcall(abi.encodeWithSignature("getSystemMetrics()"));
        if (!success) return 0;
        
        (uint256 controllerInsuranceFunds, , , ) = abi.decode(data, (uint256, uint256, uint256, uint256));
        return controllerInsuranceFunds;
    }
    
    

    

    
    /**
     * @notice Record user contribution for current trading period
     * @param user User address
     * @param asset Asset address
     * @param usdContribution User's USD contribution
     */
    function _recordUserContributionForPeriod(address user, address asset, uint256 usdContribution) internal {
        if (assetCurrentPeriodId[asset] == 0) {
            // Start first trading period for this asset
            assetCurrentPeriodId[asset]++;
            DataTypes.TradingPeriod storage newPeriod = assetPeriods[asset][assetCurrentPeriodId[asset]];
            newPeriod.startTime = block.timestamp;
            newPeriod.isActive = true;
            newPeriod.totalPoolTokensAtStart = totalSupply();
            newPeriod.totalUsdValueAtStart = totalPoolValue;
            
            emit Events.TradingPeriodStarted(asset, assetCurrentPeriodId[asset], block.timestamp, assetThresholds[asset]);
        }
        
        DataTypes.TradingPeriod storage currentPeriod = assetPeriods[asset][assetCurrentPeriodId[asset]];
        
        // Record user's contribution for this period
        if (currentPeriod.userUsdContributionAtStart[user] == 0) {
            currentPeriod.userTokensAtStart[user] = balanceOf(user);
        }
        currentPeriod.userUsdContributionAtStart[user] += usdContribution;
        
        emit Events.UserJoinedPeriod(user, asset, assetCurrentPeriodId[asset], usdContribution);
    }
    
    /**
     * @notice Check if we can start a new trading period (continuous periods)
     * @param asset Asset to check for new trading period
     */
    function _checkAndStartNewTradingPeriod(address asset) internal {
        uint256 availableFunds = assetAvailableForTrading[asset];
        uint256 assetThreshold = assetThresholds[asset];
        
        if (availableFunds >= assetThreshold) {
            // Start new trading period with threshold amount
            _startNewTradingPeriod(asset, assetThreshold);
        }
    }
    
    /**
     * @notice Start a new trading period for an asset
     * @param asset Asset to start trading period for
     * @param amount Amount to allocate to this trading period
     */
    function _startNewTradingPeriod(address asset, uint256 amount) internal {
        // Increment period ID
        assetCurrentPeriodId[asset]++;
        uint256 newPeriodId = assetCurrentPeriodId[asset];
        
        // Create new trading period
        DataTypes.TradingPeriod storage period = assetPeriods[asset][newPeriodId];
        period.startTime = block.timestamp;
        period.totalUsdValueAtStart = amount;
        period.isActive = true;
        period.profitsDistributed = false;
        
        // Track this period as active
        assetActivePeriods[asset].push(newPeriodId);
        periodAssetAllocation[asset][newPeriodId] = amount;
        
        // Reduce available funds
        assetAvailableForTrading[asset] -= amount;
        
        emit Events.TradingPeriodStarted(asset, newPeriodId, block.timestamp, amount);
        
        // Send funds to controller for this period
        _sendFundsToControllerForPeriod(asset, amount, newPeriodId);
    }
    

    
    /**
     * @notice Send funds to controller for a specific trading period
     * @param asset Asset to send
     * @param amount Amount to send for this period
     * @param periodId Period ID this amount belongs to
     */
    function _sendFundsToControllerForPeriod(address asset, uint256 amount, uint256 periodId) internal {
        if (controller == address(0)) return;
        
        uint256 usdValue = _getAssetUsdValue(asset, amount);
        
        // Transfer to controller
        IERC20(asset).safeTransfer(controller, amount);
        
        // Update balances (don't reset to 0, just reduce by amount)
        assetBalances[asset] -= amount;
        totalPoolValue -= usdValue;
        
        // Call controller's receiveFunds function
        (bool success, ) = controller.call(
            abi.encodeWithSignature(
                "receiveFunds(address,uint256)", 
                asset, 
                amount
            )
        );
        
        if (!success) {
            // If call fails, restore balance
            assetBalances[asset] += amount;
            totalPoolValue += usdValue;
            revert Errors.TradingPool__ThresholdNotReached();
        }
        
        emit Events.FundsSentToController(asset, usdValue, periodId);
    }
    
    /**
     * @notice Distribute profits for a specific asset period
     * @param asset Asset that generated profit
     * @param profitAmount Profit amount in USD
     * @param periodId Period ID to distribute profits for
     */
    function distributePeriodProfit(address asset, uint256 profitAmount, uint256 periodId) 
        external 
        onlyAuthorized 
        moreThanZero(profitAmount) 
    {
        DataTypes.TradingPeriod storage period = assetPeriods[asset][periodId];
        
        if (!period.isActive) revert Errors.TradingPool__NoActiveTradingPeriod();
        
        // Calculate profit per dollar contributed
        if (period.totalUsdValueAtStart > 0) {
            period.profitPerDollar = (profitAmount * 1e18) / period.totalUsdValueAtStart;
            period.periodPnL = int256(profitAmount);
        }
        
        // End the period
        period.endTime = block.timestamp;
        period.isActive = false;
        period.profitsDistributed = true;
        
        // Remove from active periods list
        _removeActivePeriod(asset, periodId);
        
        // Update totals
        totalProfits += profitAmount;
        totalPoolValue += profitAmount;
        
        emit Events.ProfitDistributed(asset, 0, profitAmount, periodId);
        emit Events.TradingPeriodEnded(asset, periodId, block.timestamp, int256(profitAmount));
    }
    
    /**
     * @notice Distribute insurance refund to participants when losses occur
     * @param asset Asset that incurred loss
     * @param refundAmount Amount of insurance to refund
     */
    function distributeInsuranceRefund(address asset, uint256 refundAmount) 
        external 
        onlyAuthorized 
        moreThanZero(refundAmount) 
    {
        // Get the most recent active period for this asset
        uint256[] memory activePeriods = assetActivePeriods[asset];
        if (activePeriods.length == 0) {
            revert Errors.TradingPool__NoActiveTradingPeriod();
        }
        
        // Get the latest period (most recent)
        uint256 latestPeriodId = activePeriods[activePeriods.length - 1];
        DataTypes.TradingPeriod storage period = assetPeriods[asset][latestPeriodId];
        
        if (!period.isActive) {
            revert Errors.TradingPool__NoActiveTradingPeriod();
        }
        
        // Calculate refund per dollar contributed (15% of their contribution)
        uint256 refundPerDollar = 0;
        if (period.totalUsdValueAtStart > 0) {
            // Calculate 15% of their contribution as refund
            refundPerDollar = (refundAmount * 1e18) / period.totalUsdValueAtStart;
        }
        
        // Update period with refund information
        period.insuranceRefundPerDollar = refundPerDollar;
        period.insuranceRefundAmount = refundAmount;
        
        // Update pool totals
        totalInsuranceRefunds += refundAmount;
        
        emit Events.InsuranceRefundDistributed(asset, refundAmount, latestPeriodId);
    }
    
    /**
     * @notice Remove a period from the active periods list
     * @param asset Asset address
     * @param periodId Period ID to remove
     */
    function _removeActivePeriod(address asset, uint256 periodId) internal {
        uint256[] storage activePeriods = assetActivePeriods[asset];
        for (uint256 i = 0; i < activePeriods.length; i++) {
            if (activePeriods[i] == periodId) {
                // Remove by swapping with last element and popping
                activePeriods[i] = activePeriods[activePeriods.length - 1];
                activePeriods.pop();
                break;
            }
        }
    }
    
    /**
     * @notice Record loss for a specific asset period
     * @param asset Asset that generated loss
     * @param lossAmount Loss amount in USD
     * @param periodId Period ID to record loss for
     */
    function recordPeriodLoss(address asset, uint256 lossAmount, uint256 periodId) 
        external 
        onlyAuthorized 
        moreThanZero(lossAmount) 
    {
        DataTypes.TradingPeriod storage period = assetPeriods[asset][periodId];
        
        if (!period.isActive) revert Errors.TradingPool__NoActiveTradingPeriod();
        
        // Record the loss
        period.periodPnL = -int256(lossAmount);
        
        // End the period
        period.endTime = block.timestamp;
        period.isActive = false;
        period.profitsDistributed = true;
        
        // Remove from active periods list
        _removeActivePeriod(asset, periodId);
        
        // Update totals
        totalLosses += lossAmount;
        if (totalPoolValue >= lossAmount) {
            totalPoolValue -= lossAmount;
        } else {
            totalPoolValue = 0;
        }
        
        emit Events.LossRecorded(asset, lossAmount, assetCurrentPeriodId[asset]);
        emit Events.TradingPeriodEnded(asset, assetCurrentPeriodId[asset], block.timestamp, -int256(lossAmount));
    }
    
    /**
     * @notice Calculate user's profit/loss for a specific period
     * @param user User address
     * @param asset Asset address
     * @param periodId Period ID
     * @return profit User's profit (0 if loss)
     * @return loss User's loss (0 if profit)
     */
    function calculateUserPnL(address user, address asset, uint256 periodId) 
        external 
        view 
        returns (uint256 profit, uint256 loss) 
    {
        DataTypes.TradingPeriod storage period = assetPeriods[asset][periodId];
        uint256 userContribution = period.userUsdContributionAtStart[user];
        
        if (userContribution == 0) return (0, 0);
        
        if (period.periodPnL > 0) {
            // Profit scenario
            profit = (userContribution * period.profitPerDollar) / 1e18;
        } else if (period.periodPnL < 0) {
            // Loss scenario
            uint256 totalLoss = uint256(-period.periodPnL);
            if (period.totalUsdValueAtStart > 0) {
                loss = (userContribution * totalLoss) / period.totalUsdValueAtStart;
            }
        }
    }
    
    /**
     * @notice Claim profit from a completed period
     * @param asset Asset address
     * @param periodId Period ID
     * @param reinvest Whether to reinvest as pool tokens or withdraw
     */
    function claimPeriodProfit(address asset, uint256 periodId, bool reinvest) 
        external 
        nonReentrant 
    {
        DataTypes.TradingPeriod storage period = assetPeriods[asset][periodId];
        
        if (!period.profitsDistributed) revert Errors.TradingPool__PeriodNotCompleted();
        if (period.userProfitClaimed[msg.sender]) revert Errors.TradingPool__ProfitAlreadyClaimed();
        if (period.userUsdContributionAtStart[msg.sender] == 0) revert Errors.TradingPool__NoContributionInPeriod();
        
        (uint256 profit, ) = this.calculateUserPnL(msg.sender, asset, periodId);
        
        if (profit == 0) return;
        
        period.userProfitClaimed[msg.sender] = true;
        
        if (reinvest) {
            // Mint additional pool tokens
            uint256 currentPrice = totalPoolValue > 0 ? 
                (totalPoolValue * 1e18) / totalSupply() : 1e18;
            uint256 newTokens = (profit * 1e18) / currentPrice;
            
            _mint(msg.sender, newTokens);
            userPoolTokens[msg.sender] += newTokens;
            
            emit Events.ProfitReinvested(msg.sender, asset, profit, newTokens, periodId);
        } else {
            // Withdraw profit in the asset
            uint256 assetAmount = _convertUsdToAsset(asset, profit);
            
            if (assetBalances[asset] >= assetAmount) {
                assetBalances[asset] -= assetAmount;
                totalPoolValue -= profit;
                
                IERC20(asset).safeTransfer(msg.sender, assetAmount);
                
                emit Events.ProfitWithdrawn(msg.sender, asset, assetAmount, profit, periodId);
            }
        }
    }
    
    // ============ View Functions ============
    

    
    /**
     * @notice Get period information
     * @param asset Asset address
     * @param periodId Period ID
     * @return startTime Period start time
     * @return endTime Period end time
     * @return totalContributions Total contributions
     * @return isActive Whether period is active
     * @return pnl Period P&L
     */
    function getPeriodInfo(address asset, uint256 periodId) 
        external 
        view 
        returns (
            uint256 startTime,
            uint256 endTime,
            uint256 totalContributions,
            bool isActive,
            int256 pnl
        ) 
    {
        DataTypes.TradingPeriod storage period = assetPeriods[asset][periodId];
        return (
            period.startTime,
            period.endTime,
            period.totalUsdValueAtStart,
            period.isActive,
            period.periodPnL
        );
    }
    
    /**
     * @notice Get asset configuration
     * @param asset Asset address
     * @return isSupported Whether asset is supported
     * @return decimals Asset decimals
     * @return assetThreshold Asset threshold
     * @return assetPeriodId Current period ID
     * @return totalBalance Current balance
     * @return periodActive Whether period is active
     */
    function getAssetConfig(address asset) external view returns (
        bool isSupported,
        uint8 decimals,
        uint256 assetThreshold,
        uint256 assetPeriodId,
        uint256 totalBalance,
        bool periodActive
    ) {
        return (
            supportedAssets[asset],
            assetDecimals[asset],
            assetThresholds[asset],
            assetCurrentPeriodId[asset],
            assetBalances[asset],
            assetPeriodActive[asset]
        );
    }
    
    // ============ New View Functions for Continuous Periods ============
    
    /**
     * @notice Get all active trading periods for an asset
     * @param asset Asset address
     * @return activePeriods Array of active period IDs
     */
    function getActivePeriods(address asset) external view returns (uint256[] memory activePeriods) {
        return assetActivePeriods[asset];
    }
    
    /**
     * @notice Get available funds for new trading periods
     * @param asset Asset address
     * @return availableFunds Available funds in USD
     */
    function getAvailableFundsForTrading(address asset) external view returns (uint256 availableFunds) {
        return assetAvailableForTrading[asset];
    }
    
    /**
     * @notice Check if an asset can start a new trading period
     * @param asset Asset address
     * @return canStart True if threshold can be reached
     * @return availableFunds Current available funds
     * @return assetThreshold Required threshold
     */
    function canStartNewPeriod(address asset) external view returns (
        bool canStart, 
        uint256 availableFunds, 
        uint256 assetThreshold
    ) {
        availableFunds = assetAvailableForTrading[asset];
        assetThreshold = assetThresholds[asset];
        canStart = availableFunds >= assetThreshold;
    }
    
    /**
     * @notice Get period allocation for a specific period
     * @param asset Asset address
     * @param periodId Period ID
     * @return allocation Amount allocated to this period
     */
    function getPeriodAllocation(address asset, uint256 periodId) external view returns (uint256 allocation) {
        return periodAssetAllocation[asset][periodId];
    }



}