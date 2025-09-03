//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

/**
 * @title MockBlocklockSender
 * @notice Mock implementation of Blocklock sender for testing
 */
contract MockBlocklockSender {
    
    mapping(uint256 => bool) public requests;
    bool public requestMade = false;
    uint256 public lastRequestId;
    
    event BlocklockRequested(uint256 indexed requestId, address indexed requester);
    event BlocklockCallback(uint256 indexed requestId, bytes32 decryptionKey);
    
    function requestBlocklock(
        uint32 callbackGasLimit,
        bytes memory condition,
        bytes memory ciphertext
    ) external payable returns (uint256 requestId) {
        requestId = uint256(keccak256(abi.encode(
            msg.sender,
            block.timestamp,
            block.number,
            condition,
            ciphertext
        )));
        
        requests[requestId] = true;
        requestMade = true;
        lastRequestId = requestId;
        
        emit BlocklockRequested(requestId, msg.sender);
        
        return requestId;
    }
    
    function requestBlocklockWithSubscription(
        uint32 callbackGasLimit,
        uint256 subscriptionId,
        bytes memory condition,
        bytes memory ciphertext
    ) external returns (uint256 requestId) {
        requestId = uint256(keccak256(abi.encode(
            msg.sender,
            subscriptionId,
            block.timestamp,
            block.number,
            condition,
            ciphertext
        )));
        
        requests[requestId] = true;
        requestMade = true;
        lastRequestId = requestId;
        
        emit BlocklockRequested(requestId, msg.sender);
        
        return requestId;
    }
    
    function calculateRequestPriceNative(uint32 callbackGasLimit) 
        external 
        view 
        returns (uint256) 
    {
        return callbackGasLimit * tx.gasprice + 0.001 ether;
    }
    
    function fundSubscriptionWithNative(uint256 subscriptionId) external payable {
        // Mock implementation
    }
    
    function addConsumer(uint256 subscriptionId, address consumer) external {
        // Mock implementation
    }
    
    // Test helper functions
    function triggerCallback(uint256 requestId, address receiver) external {
        require(requests[requestId], "Request not found");
        
        bytes32 decryptionKey = keccak256(abi.encode(requestId, block.timestamp));
        
        (bool success, ) = receiver.call(
            abi.encodeWithSignature("receiveBlocklock(uint256,bytes32)", requestId, decryptionKey)
        );
        
        require(success, "Callback failed");
        
        emit BlocklockCallback(requestId, decryptionKey);
    }
    
    function reset() external {
        requestMade = false;
        lastRequestId = 0;
    }
}
