//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPermissionManager} from "../Permission/interface/IPermissionManager.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IPulleyController} from "../interfaces/IPulleyController.sol";



/**
 * @title PulTradingPool
 * @author Core-Connect Team
 * @notice AI-based trading pool with threshold mechanism and oracle-based pricing
 * @dev People deposit, get pool tokens, when threshold reached funds go to controller
 */
contract PulTradingPool is ERC20, ReentrancyGuard {

  using SafeERC20 for IERC20;
    
    // ============ State Variables ============

    address public permissionManager;
    address public controller;
    address public pulleyToken; // Pulley token for insurance
    
    // Chainlink price feeds
    mapping(address => AggregatorV3Interface) public priceFeeds; // asset => price feed
    
    // Threshold mechanism
    uint256 public threshold = 10000 * 1e18; // 10,000 USD threshold
    uint256 public totalDeposited; // Total USD value deposited
    
    // Asset management with oracle pricing
    mapping(address => uint256) public assetBalances; // Asset balances
    mapping(address => bool) public supportedAssets; // Supported assets
    mapping(address => uint8) public assetDecimals; // Store decimals for each asset
    address[] public assetList;

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
    
    // ============ Events ============
    
    event Deposited(address indexed user, address indexed asset, uint256 amount, uint256 poolTokens, uint256 usdValue);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount, uint256 poolTokensBurned);
    event ThresholdReached(uint256 totalAmount, uint256 timestamp);
    event FundsSentToController(uint256 totalUsdValue);
    event ProfitRecorded(uint256 amount);
    event ProfitDistributed(uint256 insuranceShare, uint256 poolShare);
    event LossRecorded(uint256 amount);
    event LossCovered(uint256 lossAmount, bool coveredByInsurance, uint256 coveredAmount);
    event AssetAdded(address indexed asset, uint8 decimals);
    event AssetRemoved(address indexed asset);
    event PriceFeedUpdated(address indexed asset, address indexed priceFeed);
    event ThresholdUpdated(uint256 newThreshold);
    
    // ============ Errors ============
    
    error TradingPool__ZeroAmount();
    error TradingPool__ZeroAddress();
    error TradingPool__UnsupportedAsset();
    error TradingPool__InsufficientBalance();
    error TradingPool__InsufficientPoolTokens();
    error TradingPool__ThresholdNotReached();
    error TradingPool__NotAuthorized();
    error TradingPool__TransferFailed();
    error TradingPool__NotController();

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
        if (amount == 0) revert TradingPool__ZeroAmount();
        _;
    }
    
    modifier supportedAsset(address asset) {
        if (!supportedAssets[asset]) revert TradingPool__UnsupportedAsset();
        _;
    }

    modifier onlyController() {
        if (msg.sender != controller) revert TradingPool__NotController();
        _;
    }
    
    // ============ Constructor ============
    
    constructor(
        string memory name,
        string memory symbol,
        address _permissionManager,
        address _controller,
        address _pulleyToken
    ) ERC20(name, symbol) {
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
        // Transfer asset from user
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        
        // Get USD value using oracle (simplified - implement proper oracle integration)
        uint256 usdValue = _getAssetUsdValue(asset, amount);
        
        // Calculate pool tokens based on current pool state
        if (totalSupply() == 0) {
            // First deposit , minus min share to prevent share manipulation
            poolTokens = usdValue - 1e18;//minShare;
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
        
        // Record user tokens for current trading period (for fair profit distribution)
        _recordUserTokensForPeriod(msg.sender, poolTokens);
        
        // Mint pool tokens
        _mint(msg.sender, poolTokens);
        
        emit Deposited(msg.sender, asset, amount, poolTokens, usdValue);
        
        // Check threshold
        _checkThreshold();
        
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
        if (balanceOf(msg.sender) < poolTokenAmount) revert TradingPool__InsufficientPoolTokens();
        
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
        
        emit Withdrawn(msg.sender, asset, assetAmount, poolTokenAmount);
        
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
     * @notice Manually trigger threshold check (anyone can call)
     */
    function triggerThreshold() external nonReentrant {
        if (totalDeposited < threshold) revert TradingPool__ThresholdNotReached();
        _sendFundsToController();
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
        
        emit ProfitRecorded(profitAmount);
        //emit ProfitDistributed(insuranceShare, poolShare);
    } //@dev add profit distribution mechanism for the traders

    // Trading period tracking for fair profit distribution
    struct TradingPeriod {
        uint256 startTime;
        uint256 endTime;
        uint256 totalPoolTokensAtStart;
        mapping(address => uint256) userTokensAtStart;
        bool isActive;
        bool profitsDistributed;
    }
    
    mapping(uint256 => TradingPeriod) public tradingPeriods;
    uint256 public currentPeriodId;
    uint256 public periodDuration = 7 days; // Default 7 days per period
    
    event TradingPeriodStarted(uint256 indexed periodId, uint256 startTime);
    event TradingPeriodEnded(uint256 indexed periodId, uint256 endTime);
    event ProfitsDistributedForPeriod(uint256 indexed periodId, uint256 totalProfit);
    
    /**
     * @notice Start a new trading period (called by controller)
     */
    function startTradingPeriod() external onlyController {
        // End current period if active
        if (tradingPeriods[currentPeriodId].isActive) {
            _endCurrentTradingPeriod();
        }
        
        currentPeriodId++;
        TradingPeriod storage newPeriod = tradingPeriods[currentPeriodId];
        newPeriod.startTime = block.timestamp;
        newPeriod.totalPoolTokensAtStart = totalSupply();
        newPeriod.isActive = true;
        
        emit TradingPeriodStarted(currentPeriodId, block.timestamp);
    }
    
    /**
     * @notice End current trading period
     */
    function _endCurrentTradingPeriod() internal {
        TradingPeriod storage period = tradingPeriods[currentPeriodId];
        if (period.isActive) {
            period.endTime = block.timestamp;
            period.isActive = false;
            emit TradingPeriodEnded(currentPeriodId, block.timestamp);
        }
    }
    
    /**
     * @notice Record user's tokens at period start (called during deposits)
     */
    function _recordUserTokensForPeriod(address user, uint256 tokens) internal {
        TradingPeriod storage period = tradingPeriods[currentPeriodId];
        if (period.isActive && period.userTokensAtStart[user] == 0) {
            period.userTokensAtStart[user] = balanceOf(user) - tokens; // Tokens before this deposit
        }
    }

     /**
      * @notice Distribute profits to traders based on their participation in trading period
      */
     function distributeTradersProfit(uint256 profitAmount) external onlyAuthorized moreThanZero(profitAmount) {
        totalProfits += profitAmount;
        totalPoolValue += profitAmount;
        
        // End current period and distribute profits
        _endCurrentTradingPeriod();
        
        TradingPeriod storage period = tradingPeriods[currentPeriodId];
        require(!period.profitsDistributed, "TradingPool: Profits already distributed for this period");
        
        if (period.totalPoolTokensAtStart > 0) {
            // Distribute profits proportionally to users who were in the pool at period start
            // This ensures fair distribution without bias toward late joiners
            
            // For gas efficiency, we'll mint additional pool tokens representing the profit
            // Users can claim their share later or it's automatically included in their balance
            uint256 profitTokens = (profitAmount * totalSupply()) / totalPoolValue;
            
            // Increase total pool value to include profits
            // The profit is now reflected in the increased value per token
            // No additional minting needed as the value per token increases
            
            period.profitsDistributed = true;
            emit ProfitsDistributedForPeriod(currentPeriodId, profitAmount);
        }
     }

    /**
     * @notice Record trading loss and handle coverage (called by controller)
     */
    //@dev get insurance balance ocnverted to lossamount to see if it can cover the loss
    function recordLoss(uint256 lossAmount) external onlyController moreThanZero(lossAmount) {
        totalLosses += lossAmount;
        
        // Check if insurance can cover the loss
        bool coveredByInsurance = false;
        uint256 coveredAmount = 0;
        //get insurance funds from controller
        uint256 _insuranceFunds =  getInsuranceFunds();
        
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
        
        emit LossRecorded(lossAmount);
        emit LossCovered(lossAmount, coveredByInsurance, coveredAmount);
    }
    



    //=================== Internal Functions ===================
     /**
     * @notice Get USD value of asset amount using Chainlink price feeds
     * @param asset Asset address
     * @param amount Asset amount
     * @return usdValue USD value in 18 decimals
     */
    function _getAssetUsdValue(address asset, uint256 amount) internal view returns (uint256 usdValue) {
        AggregatorV3Interface priceFeed = priceFeeds[asset];
        
        if (address(priceFeed) == address(0)) {
            //@todo: remove this fallback, not revelant since all aseset used will be set
            // Fallback: assume 1:1 USD for stablecoins
            uint8 decimals = assetDecimals[asset];
            if (decimals == 6) {
                return amount * 1e12; // Convert USDC/USDT to 18 decimals
            } else if (decimals == 18) {
                return amount; // Already 18 decimals
            } else {
                return amount * (10 ** (18 - decimals));
            }
        } else {
            // Use Chainlink price feed
            (, int256 price, , , ) = priceFeed.latestRoundData();
            require(price > 0, "TradingPool: Invalid price");
            
            uint8 assetDecimal = assetDecimals[asset];
            uint8 feedDecimals = priceFeed.decimals();
            
            // Convert to 18 decimals: amount * price * 10^(18 - assetDecimals - feedDecimals)
            usdValue = (amount * uint256(price) * (10 ** (18 - assetDecimal))) / (10 ** feedDecimals);
        }
    }
    

       /**
     * @notice Check if threshold is reached and send funds to controller
     */
    function _checkThreshold() internal {
        if (totalDeposited >= threshold) {
            _sendFundsToController();
        }
    }
    
    /**
     * @notice Send all funds to controller when threshold is reached
     */
    function _sendFundsToController() internal {
        if (controller == address(0)) return;
        
        uint256 totalUsdValue = 0;
        
        // Transfer all assets to controller
        for (uint256 i = 0; i < assetList.length; i++) {
            address asset = assetList[i];
            uint256 balance = assetBalances[asset];
            
            if (balance > 0) {
                uint256 usdValue = _getAssetUsdValue(asset, balance);
                totalUsdValue += usdValue;
                
                // Transfer to controller first
                IERC20(asset).safeTransfer(controller, balance);
                
                // Reset balance
                assetBalances[asset] = 0;
                
                // Call controller's receiveFunds function
                (bool success, ) = controller.call(
                    abi.encodeWithSignature("receiveFunds(address,uint256)", asset, balance)
                );
                
                if (!success) {
                    // If call fails, restore balance
                    assetBalances[asset] = balance;
                    revert("Failed to notify controller");
                }
            }
        }
        
        if (totalUsdValue > 0) {
            totalDeposited = 0; // Reset after transfer
            lastThresholdTransfer = block.timestamp;
            
            emit ThresholdReached(totalUsdValue, block.timestamp);
            emit FundsSentToController(totalUsdValue);
        }
    }





   
    // ============ Administrative Functions ============
    
    /**
     * @notice Add supported asset with decimals
     */
    function addAsset(address asset, uint8 decimals) external onlyAuthorized {
        if (asset == address(0)) revert TradingPool__ZeroAddress();
        
        if (!supportedAssets[asset]) {
            supportedAssets[asset] = true;
            assetDecimals[asset] = decimals;
            assetList.push(asset);
            
            emit AssetAdded(asset, decimals);
        }
    }
    
    /**
     * @notice Remove supported asset
     */
    function removeAsset(address asset) external onlyAuthorized {
        if (supportedAssets[asset]) {
            supportedAssets[asset] = false;
            assetDecimals[asset] = 0;
            
            // Remove from array
            for (uint256 i = 0; i < assetList.length; i++) {
                if (assetList[i] == asset) {
                    assetList[i] = assetList[assetList.length - 1];
                    assetList.pop();
                    break;
                }
            }
            
            emit AssetRemoved(asset);
        }
    }
    
    /**
     * @notice Update threshold
     */
    function updateThreshold(uint256 newThreshold) external onlyAuthorized {
        threshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }
    
    /**
     * @notice Update controller address
     */
    function updateController(address newController) external onlyAuthorized {
        if (newController == address(0)) revert TradingPool__ZeroAddress();
        controller = newController;
    }
    
    /**
     * @notice Set price feed for an asset
     */
    function setPriceFeed(address asset, address priceFeed) external onlyAuthorized {
        priceFeeds[asset] = AggregatorV3Interface(priceFeed);
        emit PriceFeedUpdated(asset, priceFeed);
    }
    
    /**
     * @notice Update Pulley token address
     */
    function updatePulleyToken(address newPulleyToken) external onlyAuthorized {
        if (newPulleyToken == address(0)) revert TradingPool__ZeroAddress();
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
     * @notice Check if threshold is reached
     */
    function isThresholdReached() public view returns (bool) {
        return totalDeposited >= threshold;
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



}