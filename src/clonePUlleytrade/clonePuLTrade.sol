//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PulTradingPool} from "../Pool/PuLTradingPool.sol";
import {PulleyController} from "../PulleyController.sol";
import {Wallet} from "../wallet.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";

/**
 * @title Clone PuL Trade
 * @notice Factory for creating trading pool clones with 3 assets: native, PulleyToken, and custom
 * @dev Each clone gets its own controller and wallet
 */
contract ClonePuLTrade is Ownable {
    using Clones for address;
    
    // ============ State Variables ============
    
    address public immutable tradingPoolImplementation;
    address public immutable controllerImplementation;
    address public immutable walletImplementation;
    address public immutable pulleyToken;
    address public permissionManager;
    
    // Deployed clones
    address[] public deployedClones;
    mapping(address => bool) public isValidClone;
    mapping(address => DataTypes.PoolCloneConfig) public cloneConfigs;
    mapping(address => address) public cloneControllers; // clone => controller
    mapping(address => address) public cloneWallets; // clone => wallet
    
    // ============ Events ============
    
    event CloneCreated(
        address indexed clone,
        address indexed controller,
        address indexed wallet,
        address creator,
        string name,
        address nativeAsset,
        address customAsset
    );
    
    // ============ Constructor ============
    
    constructor(
        address _tradingPoolImplementation,
        address _controllerImplementation,
        address _walletImplementation,
        address _pulleyToken,
        address _permissionManager,
        address _owner
    ) Ownable(_owner) {
        if (_tradingPoolImplementation == address(0) || 
            _controllerImplementation == address(0) ||
            _walletImplementation == address(0) ||
            _pulleyToken == address(0) || 
            _permissionManager == address(0)) {
            revert Errors.ZeroAddress();
        }
        
        tradingPoolImplementation = _tradingPoolImplementation;
        controllerImplementation = _controllerImplementation;
        walletImplementation = _walletImplementation;
        pulleyToken = _pulleyToken;
        permissionManager = _permissionManager;
    }
    
    // ============ Core Functions ============
    
    /**
     * @notice Create a new trading pool clone with controller and wallet
     * @param config Clone configuration
     * @return clone Address of the created clone
     * @return controller Address of the created controller
     * @return wallet Address of the created wallet
     */
    function createClone(DataTypes.PoolCloneConfig memory config) 
        external 
        returns (address clone, address payable controller, address payable wallet) 
    {
        // Validate configuration
        if (bytes(config.poolName).length == 0 || bytes(config.poolSymbol).length == 0) {
            revert Errors.Clone__InvalidConfiguration();
        }
        
        if (config.customAsset == address(0)) {
            revert Errors.ZeroAddress();
        }
        
        if (config.nativeThreshold == 0 || 
            config.pulleyThreshold == 0 || 
            config.customThreshold == 0) {
            revert Errors.Clone__ThresholdTooLow();
        }
        
        // Get native token for current chain (when msg.value > 0)
        address nativeToken = _getNativeToken();
        config.nativeAsset = nativeToken;
        config.pulleyToken = pulleyToken;
        
        // Create clone
        clone = tradingPoolImplementation.clone();
        
        // Create controller for this clone
        controller = payable(controllerImplementation.clone());
        
        // Create wallet for this clone
        wallet = payable(walletImplementation.clone());
        
        // Initialize the clone
        PulTradingPool(clone).initialize(
            config.poolName,
            config.poolSymbol,
            permissionManager,
            controller,
            pulleyToken
        );
        
        // Initialize controller
        address[] memory supportedAssets = new address[](3);
        supportedAssets[0] = config.nativeAsset;
        supportedAssets[1] = config.pulleyToken;
        supportedAssets[2] = config.customAsset;
        
        PulleyController(controller).initialize(
            permissionManager,
            clone,
            address(0), // insurance pool - not used
            pulleyToken,
            address(0), // ai trader - not used
            supportedAssets
        );
        
        // Initialize wallet
        Wallet(wallet).initialize(controller, msg.sender); // msg.sender as AI signer
        
        // Configure the three assets in the clone
        _configureCloneAssets(clone, config);
        
        // Store clone info
        deployedClones.push(clone);
        isValidClone[clone] = true;
        cloneConfigs[clone] = config;
        cloneControllers[clone] = controller;
        cloneWallets[clone] = wallet;
        
        emit CloneCreated(clone, controller, wallet, msg.sender, config.poolName, nativeToken, config.customAsset);
        emit Events.PoolCloneCreated(clone, msg.sender, config.poolName);
        
        return (clone, controller, wallet);
    }
    
    /**
     * @notice Quick create clone with default configuration
     * @param poolName Pool name
     * @param poolSymbol Pool symbol
     * @param customAsset Custom third asset
     * @param nativeThreshold Threshold for native asset
     * @param pulleyThreshold Threshold for PulleyToken
     * @param customThreshold Threshold for custom asset
     * @return clone Address of created clone
     * @return controller Address of created controller
     * @return wallet Address of created wallet
     */
    function quickCreateClone(
        string memory poolName,
        string memory poolSymbol,
        address customAsset,
        uint256 nativeThreshold,
        uint256 pulleyThreshold,
        uint256 customThreshold
    ) external returns (address clone, address payable controller, address payable wallet) {
        DataTypes.PoolCloneConfig memory config = DataTypes.PoolCloneConfig({
            nativeAsset: address(0), // Will be set in createClone
            pulleyToken: pulleyToken,
            customAsset: customAsset,
            nativeThreshold: nativeThreshold,
            pulleyThreshold: pulleyThreshold,
            customThreshold: customThreshold,
            poolName: poolName,
            poolSymbol: poolSymbol
        });
        
        return this.createClone(config);
    }
    
    /**
     * @notice Configure assets for a newly created clone
     * @param clone Clone address
     * @param config Clone configuration
     */
    function _configureCloneAssets(address clone, DataTypes.PoolCloneConfig memory config) internal {
        PulTradingPool pool = PulTradingPool(clone);
        
        // Add native asset (e.g., WETH on Ethereum)
        pool.addAsset(
            config.nativeAsset,
            18, // Most native tokens are 18 decimals
            config.nativeThreshold,
            address(0) // Price feed to be set later
        );
        
        // Add PulleyToken
        pool.addAsset(
            config.pulleyToken,
            18, // PulleyToken is 18 decimals
            config.pulleyThreshold,
            address(0) // Price feed to be set later
        );
        
        // Add custom asset
        pool.addAsset(
            config.customAsset,
            18, // Assume 18 decimals, can be updated
            config.customThreshold,
            address(0) // Price feed to be set later
        );
        
        emit Events.CloneInitialized(clone, config.nativeAsset, config.pulleyToken, config.customAsset);
    }
    
    /**
     * @notice Get native token for current chain
     * @return nativeToken Native token address
     */
    function _getNativeToken() internal view returns (address nativeToken) {
        // For now, return a placeholder. In real implementation, this would:
        // 1. Check if msg.value > 0 to determine if user wants native currency
        // 2. Return the appropriate wrapped native token for the current chain
        // 3. Handle different chains (ETH -> WETH, MATIC -> WMATIC, etc.)
        
        // Placeholder implementation - would need to be updated based on deployment chain
        return address(0); // This should be set to the actual wrapped native token
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get all deployed clones
     * @return clones Array of clone addresses
     */
    function getAllClones() external view returns (address[] memory clones) {
        return deployedClones;
    }
    
    /**
     * @notice Get clone configuration
     * @param clone Clone address
     * @return config Clone configuration
     */
    function getCloneConfig(address clone) external view returns (DataTypes.PoolCloneConfig memory config) {
        return cloneConfigs[clone];
    }
    
    /**
     * @notice Get clone's controller
     * @param clone Clone address
     * @return controller Controller address
     */
    function getCloneController(address clone) external view returns (address controller) {
        return cloneControllers[clone];
    }
    
    /**
     * @notice Get clone's wallet
     * @param clone Clone address
     * @return wallet Wallet address
     */
    function getCloneWallet(address clone) external view returns (address wallet) {
        return cloneWallets[clone];
    }
    
    /**
     * @notice Get number of deployed clones
     * @return count Number of clones
     */
    function getCloneCount() external view returns (uint256 count) {
        return deployedClones.length;
    }
    
    /**
     * @notice Check if address is a valid clone
     * @param clone Address to check
     * @return valid Whether it's a valid clone
     */
    function isClone(address clone) external view returns (bool valid) {
        return isValidClone[clone];
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Update permission manager
     * @param _permissionManager New permission manager
     */
    function updatePermissionManager(address _permissionManager) external onlyOwner {
        if (_permissionManager == address(0)) revert Errors.ZeroAddress();
        permissionManager = _permissionManager;
    }
}