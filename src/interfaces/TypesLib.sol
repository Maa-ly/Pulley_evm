//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

/**
 * @title TypesLib
 * @notice Library for Blocklock types and data structures
 * @dev Based on blocklock-solidity library types
 */
library TypesLib {
    
    /**
     * @notice Ciphertext structure for encrypted data
     * @param data Encrypted data bytes
     * @param signature Cryptographic signature for verification
     */
    struct Ciphertext {
        bytes data;
        bytes32 signature;
    }
    
    /**
     * @notice Condition structure for decryption triggers
     * @param conditionType Type of condition (time, block, event, etc.)
     * @param parameters Encoded parameters for the condition
     * @param threshold Threshold value for condition evaluation
     */
    struct Condition {
        uint8 conditionType;
        bytes parameters;
        uint256 threshold;
    }
    
    /**
     * @notice Request structure for Blocklock operations
     * @param requestId Unique identifier for the request
     * @param requester Address that made the request
     * @param callbackGasLimit Gas limit for callback execution
     * @param condition Condition for decryption
     * @param ciphertext Encrypted data
     * @param timestamp Request timestamp
     * @param isCompleted Whether request has been completed
     */
    struct BlocklockRequest {
        uint256 requestId;
        address requester;
        uint32 callbackGasLimit;
        Condition condition;
        Ciphertext ciphertext;
        uint256 timestamp;
        bool isCompleted;
    }
    
    // Condition types
    uint8 public constant CONDITION_TIME = 1;
    uint8 public constant CONDITION_BLOCK = 2;
    uint8 public constant CONDITION_EVENT = 3;
    uint8 public constant CONDITION_THRESHOLD = 4;
    uint8 public constant CONDITION_CUSTOM = 5;
    
    /**
     * @notice Create a time-based condition
     * @param targetTime Target timestamp for condition trigger
     * @return condition Encoded condition
     */
    function createTimeCondition(uint256 targetTime) internal pure returns (bytes memory condition) {
        return abi.encode(CONDITION_TIME, targetTime);
    }
    
    /**
     * @notice Create a block-based condition
     * @param targetBlock Target block number for condition trigger
     * @return condition Encoded condition
     */
    function createBlockCondition(uint256 targetBlock) internal pure returns (bytes memory condition) {
        return abi.encode(CONDITION_BLOCK, targetBlock);
    }
    
    /**
     * @notice Create a threshold-based condition
     * @param threshold Threshold value
     * @param operator Comparison operator (0: ==, 1: >, 2: <, 3: >=, 4: <=)
     * @return condition Encoded condition
     */
    function createThresholdCondition(uint256 threshold, uint8 operator) 
        internal 
        pure 
        returns (bytes memory condition) 
    {
        return abi.encode(CONDITION_THRESHOLD, threshold, operator);
    }
    
    /**
     * @notice Create a custom condition
     * @param customData Custom condition data
     * @return condition Encoded condition
     */
    function createCustomCondition(bytes memory customData) 
        internal 
        pure 
        returns (bytes memory condition) 
    {
        return abi.encode(CONDITION_CUSTOM, customData);
    }
    
    /**
     * @notice Encode ciphertext for Blocklock request
     * @param data Data to encrypt
     * @param signature Cryptographic signature
     * @return ciphertext Encoded ciphertext
     */
    function encodeCiphertext(bytes memory data, bytes32 signature) 
        internal 
        pure 
        returns (Ciphertext memory ciphertext) 
    {
        return Ciphertext({
            data: data,
            signature: signature
        });
    }
    
    /**
     * @notice Decode condition parameters
     * @param condition Encoded condition
     * @return conditionType Type of condition
     * @return parameters Decoded parameters
     */
    function decodeCondition(bytes memory condition) 
        internal 
        pure 
        returns (uint8 conditionType, bytes memory parameters) 
    {
        return abi.decode(condition, (uint8, bytes));
    }
    
    /**
     * @notice Validate ciphertext structure
     * @param ciphertext Ciphertext to validate
     * @return isValid Whether ciphertext is valid
     */
    function validateCiphertext(Ciphertext memory ciphertext) 
        internal 
        pure 
        returns (bool isValid) 
    {
        return ciphertext.data.length > 0 && ciphertext.signature != bytes32(0);
    }
    
    /**
     * @notice Calculate request hash for verification
     * @param request Blocklock request
     * @return hash Request hash
     */
    function calculateRequestHash(BlocklockRequest memory request) 
        internal 
        pure 
        returns (bytes32 hash) 
    {
        return keccak256(abi.encode(
            request.requestId,
            request.requester,
            request.callbackGasLimit,
            request.condition.conditionType,
            request.condition.parameters,
            request.ciphertext.data,
            request.timestamp
        ));
    }
}
