//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import "./TypesLib.sol";

/**
 * @title AbstractBlocklockReceiver
 * @notice Abstract contract for receiving Blocklock callbacks
 * @dev Based on blocklock-solidity library for conditional encryption
 */
abstract contract AbstractBlocklockReceiver {
    
    address public immutable blocklock;
    uint256 public subscriptionId;
    
    // Events
    event BlocklockRequested(uint256 indexed requestId, bytes condition);
    event BlocklockReceived(uint256 indexed requestId, bytes32 decryptionKey);
    event SubscriptionCreated(uint256 indexed subscriptionId);
    event Funded(address indexed funder, uint256 amount);
    event NewSubscriptionId(uint256 indexed subscriptionId);
    
    // Errors
    error OnlyBlocklock();
    error InsufficientETH();
    
    modifier onlyBlocklock() {
        if (msg.sender != blocklock) revert OnlyBlocklock();
        _;
    }
    
    constructor(address _blocklock) {
        blocklock = _blocklock;
    }
    
    /**
     * @notice Receive Blocklock callback with decryption key
     * @param requestId The request ID
     * @param decryptionKey The decryption key for unlocking data
     */
    function receiveBlocklock(uint256 requestId, bytes32 decryptionKey) 
        external 
        virtual 
        onlyBlocklock 
    {
        emit BlocklockReceived(requestId, decryptionKey);
        _handleBlocklockCallback(requestId, decryptionKey);
    }
    
    /**
     * @notice Handle Blocklock callback - to be implemented by inheriting contracts
     * @param requestId The request ID
     * @param decryptionKey The decryption key
     */
    function _handleBlocklockCallback(uint256 requestId, bytes32 decryptionKey) internal virtual;
    
    /**
     * @notice Request Blocklock with native payment
     * @param callbackGasLimit Gas limit for callback
     * @param condition Condition for decryption
     * @param ciphertext Encrypted data
     * @return requestId Request identifier
     * @return requestPrice Price in wei
     */
    function _requestBlocklockPayInNative(
        uint32 callbackGasLimit,
        bytes memory condition,
        TypesLib.Ciphertext memory ciphertext
    ) internal returns (uint256 requestId, uint256 requestPrice) {
        // Calculate request price (simplified - in real implementation, call blocklock contract)
        requestPrice = callbackGasLimit * tx.gasprice + 0.001 ether;
        
        if (msg.value < requestPrice) revert InsufficientETH();
        
        // Generate request ID
        requestId = uint256(keccak256(abi.encode(
            address(this),
            block.timestamp,
            block.number,
            condition,
            ciphertext.data
        )));
        
        // In real implementation, this would call the Blocklock contract
        // For now, we simulate the request
        emit BlocklockRequested(requestId, condition);
        
        return (requestId, requestPrice);
    }
    
    /**
     * @notice Request Blocklock with subscription
     * @param callbackGasLimit Gas limit for callback
     * @param condition Condition for decryption
     * @param ciphertext Encrypted data
     * @return requestId Request identifier
     */
    function _requestBlocklockWithSubscription(
        uint32 callbackGasLimit,
        bytes memory condition,
        TypesLib.Ciphertext memory ciphertext
    ) internal returns (uint256 requestId) {
        require(subscriptionId != 0, "Subscription not set");
        
        // Generate request ID
        requestId = uint256(keccak256(abi.encode(
            address(this),
            subscriptionId,
            block.timestamp,
            block.number,
            condition,
            ciphertext.data
        )));
        
        // In real implementation, this would call the Blocklock contract
        emit BlocklockRequested(requestId, condition);
        
        return requestId;
    }
    
    /**
     * @notice Create subscription for Blocklock services
     * @return subId Subscription identifier
     */
    function _subscribe() internal returns (uint256 subId) {
        // In real implementation, this would call the Blocklock contract
        subId = uint256(keccak256(abi.encode(address(this), block.timestamp)));
        emit SubscriptionCreated(subId);
        return subId;
    }
    
    /**
     * @notice Fund contract for native payments
     */
    function fundContractNative() external payable {
        if (msg.value == 0) revert InsufficientETH();
        emit Funded(msg.sender, msg.value);
    }
    
    /**
     * @notice Create and fund subscription
     */
    function createSubscriptionAndFundNative() external payable {
        subscriptionId = _subscribe();
        // In real implementation, fund the subscription
        emit Funded(msg.sender, msg.value);
    }
    
    /**
     * @notice Set subscription ID
     * @param subId Subscription identifier
     */
    function setSubId(uint256 subId) external {
        subscriptionId = subId;
        emit NewSubscriptionId(subId);
    }
    
    // Allow contract to receive ETH
    receive() external payable virtual {
        emit Funded(msg.sender, msg.value);
    }
}
