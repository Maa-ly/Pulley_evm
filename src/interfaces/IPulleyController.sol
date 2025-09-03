//SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

interface IPulleyController {
    function getSystemMetrics() external view returns (
        uint256 totalInsurance,
        uint256 totalTrading, 
        uint256 totalProfitsAmount,
        uint256 totalLossesAmount
    );
    
    function reportTradingResult(bytes32 requestId, int256 pnl) external;
}
