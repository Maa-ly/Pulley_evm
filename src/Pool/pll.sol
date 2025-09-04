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



/**
 * @title Pul
 * @author Core-Connect Team
 * @notice AI-based trading pool with threshold mechanism and oracle-based pricing
 * @dev People deposit, get pool tokens, when threshold reached funds go to controller
 */
contract Pul is ERC20, ReentrancyGuard {

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
    




}