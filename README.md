# Pulley Protocol - AI Trading with Insurance

Pulley Protocol is a DeFi trading system that enables users to participate in AI-driven trading strategies while providing insurance coverage through a floating stablecoin mechanism. The system features Chainlink price feeds, automated profit/loss distribution, and dual minting logic for insurance coverage.

## System Architecture Overview

```mermaid
graph TB
    subgraph "User Layer"
        U[User]
    end
    
    subgraph "Core Contracts"
        TP[PuLTradingPool<br/>- Manages deposits<br/>- Mints pool tokens<br/>- Threshold mechanism]
        PT[PulleyToken<br/>- Floating stablecoin<br/>- Insurance reserve<br/>- Growth mechanism]
        PC[PulleyController<br/>- Fund allocation<br/>- AI trading coordination<br/>- Profit/loss handling]
    end
    
    subgraph "External Systems"
        AI[AI Trader<br/>- CFD Trading<br/>- Strategy execution]
        BL[Blocklock<br/>- Automation<br/>- Timelock encryption]
        CL[Chainlink<br/>- Price feeds<br/>- Oracle data]
    end
    
    subgraph "Infrastructure"
        PM[PermissionManager<br/>- Access control<br/>- Function permissions]
    end
    
    U -->|Deposit assets| TP
    TP -->|Pool tokens| U
    TP -->|Threshold reached| PC
    PC -->|15% insurance| PT
    PC -->|85% trading| AI
    AI -->|Trading results| PC
    PC -->|Profit/loss| TP
    BL -->|Automation| PC
    CL -->|Price data| TP
    PM -->|Permissions| TP
    PM -->|Permissions| PT
    PM -->|Permissions| PC
```

## User Flow Sequence

```mermaid
sequenceDiagram
    participant U as User
    participant TP as TradingPool
    participant PC as Controller
    participant PT as PulleyToken
    participant AI as AI Trader
    participant BL as Blocklock

    Note over U,BL: Trading Period Initiation
    U->>TP: startTradingPeriod()
    U->>TP: deposit(asset, amount)
    TP->>TP: recordUserTokensForPeriod()
    TP->>U: mint pool tokens

    Note over U,BL: Threshold Reached
    alt Threshold Reached
        TP->>PC: sendFundsToController()
        PC->>PC: allocate 15% insurance, 85% trading
        PC->>PT: mint insurance tokens
        PC->>AI: initiate trading
        AI->>PC: reportTradingResult(requestId, pnl)
    end

    Note over U,BL: Profit/Loss Handling
    alt Profit
        PC->>TP: distributeTradersProfit(90%)
        PC->>TP: end trading period
        PC->>TP: distribute based on period participation
        PC->>PT: mint insurance tokens (10%)
    else Loss
        PC->>PC: record loss(amount)
        PC->>PC: check insurance coverage
        alt Insurance Can Cover
            PC->>PT: burn insurance tokens
        else Cannot Cover
            PC->>TP: reduce pool value
        end
    end

    Note over U,BL: User Withdrawal
    U->>TP: withdraw(asset, poolTokens)
    TP->>TP: queryPendingPnL()
    TP->>TP: apply pending losses
    TP->>U: transfer assets

    Note over U,BL: Automated Operations
    BL->>PC: automatedProfitLossCheck()
    BL->>PC: automatedRebalancing()
    PC->>PC: execute automated actions
```

## Fund Allocation Flow

```mermaid
flowchart TD
    A[User Deposits Assets] --> B[Oracle Price Calculation]
    B --> C[Pool Token Minting]
    C --> D{Threshold Reached?}
    
    D -->|No| E[Continue Accumulating]
    E --> D
    
    D -->|Yes| F[Transfer to Controller]
    F --> G[Calculate Allocation]
    
    G --> H[15% Insurance Allocation]
    G --> I[85% Trading Allocation]
    
    H --> J[Mint PulleyToken for Insurance]
    I --> K[Send to AI Trader]
    
    K --> L[AI Trading Execution]
    L --> M{Trading Result}
    
    M -->|Profit| N[90% to Trading Pool]
    M -->|Profit| O[10% to Insurance]
    M -->|Loss| P{Insurance Coverage?}
    
    P -->|Yes| Q[Burn Insurance Tokens]
    P -->|No| R[Reduce Pool Value]
    
    N --> S[Distribute to Users]
    O --> T[Add to Insurance Reserve]
    Q --> U[Cover Losses]
    R --> V[Apply Losses to Pool]
    
    S --> W[End Trading Period]
    T --> W
    U --> W
    V --> W
```

## Contract Structure & Relationships

```mermaid
classDiagram
    class PuLTradingPool {
        +address controller
        +address pulleyToken
        +uint256 threshold
        +mapping(address => uint256) assetBalances
        +deposit(address asset, uint256 amount)
        +withdraw(address asset, uint256 poolTokens)
        +_sendFundsToController()
        +recordProfit(uint256 amount)
        +recordLoss(uint256 amount)
        +distributeTradersProfit(uint256 amount)
    }
    
    class PulleyToken {
        +address controller
        +address tradingPool
        +uint256 insuranceReserve
        +uint256 totalBackingValue
        +mapping(address => bool) supportedAssets
        +mint(address asset, uint256 backingAmount)
        +burn(address from, uint256 amount)
        +coverLoss(uint256 lossAmount)
        +addProfits(uint256 profitAmount)
        +getCurrentPrice()
    }
    
    class PulleyController {
        +address tradingPool
        +address pulleyStablecoin
        +address aiTrader
        +uint256 totalInsuranceFunds
        +uint256 totalTradingFunds
        +receiveFunds(address asset, uint256 amount)
        +reportTradingResult(bytes32 requestId, int256 pnl)
        +automatedProfitLossCheck()
        +automatedRebalancing()
        +getSystemMetrics()
    }
    
    class PermissionManager {
        +mapping(address => mapping(bytes4 => bool)) permissions
        +grantPermission(address account, bytes4 functionSelector)
        +revokePermission(address account, bytes4 functionSelector)
        +hasPermissions(address account, bytes4 functionSelector)
    }
    
    class AbstractBlocklockReceiver {
        +address blocklock
        +_requestBlocklockPayInNative()
        +_onBlocklockReceived()
    }
    
    PuLTradingPool --> PulleyController : sends funds
    PuLTradingPool --> PulleyToken : queries insurance
    PulleyController --> PulleyToken : mints insurance tokens
    PulleyController --> AbstractBlocklockReceiver : inherits automation
    PuLTradingPool --> PermissionManager : access control
    PulleyToken --> PermissionManager : access control
    PulleyController --> PermissionManager : access control
```



## How It Works

### Simplified System Architecture

1. **TradingPool** - Users deposit funds, get minted pool tokens based on oracle pricing, threshold mechanism triggers fund transfer
2. **PulleyToken** - Floating stablecoin that grows with utilization ), anyone can mint
3. **PulleyTokenEngine** - Manages the floating stablecoin mechanics and growth
4. **Controller** - Receives funds when threshold reached, allocates 15% insurance / 85% AI trading

### Key Features
- **Oracle-based Pricing**: Each asset has stored decimals for proper USD conversion
- **Floating Stablecoin**: PulleyToken grows with utilization, not pegged 1:1
- **Threshold Mechanism**: Automatic fund transfer when deposits reach threshold
- **AI Trading Integration**: 85% of funds go to external AI trading system
- **Insurance Coverage**: 15% goes to insurance, covers losses first
- **Profit Distribution**: 10% to insurance, 90% back to trading pool
- **Blocklock Automation**: Automated profit/loss checking and rebalancing




```mermaid
graph TB
    subgraph "User Layer"
        U[User]
    end
    
    subgraph "Core Contracts"
        TP[PuLTradingPool<br/>- Continuous deposits<br/>- Multiple concurrent periods<br/>- Automatic period creation]
        PT[PulleyToken<br/>- Floating stablecoin<br/>- Insurance reserve<br/>- Growth mechanism]
        PC[PulleyController<br/>- Fund allocation<br/>- AI trading coordination<br/>- Profit/loss handling]
    end
    
    subgraph "External Systems"
        AI[AI Trader<br/>- CFD Trading<br/>- Strategy execution]
        BL[Blocklock<br/>- Automation<br/>- Timelock encryption]
        CL[Chainlink<br/>- Price feeds<br/>- Oracle data]
    end
    
    subgraph "Infrastructure"
        PM[PermissionManager<br/>- Access control<br/>- Function permissions]
    end
    
    U -->|Deposit assets| TP
    TP -->|Pool tokens| U
    TP -->|Auto-start periods| PC
    PC -->|15% insurance| PT
    PC -->|85% trading| AI
    AI -->|Trading results| PC
    PC -->|Profit/loss| TP
    BL -->|Automation| PC
    CL -->|Price data| TP
    PM -->|Permissions| TP
    PM -->|Permissions| PT
    PM -->|Permissions| PC
```

## Complete Protocol Workflow

```mermaid
sequenceDiagram
    participant U as User ($4 contribution)
    participant TP as TradingPool
    participant PC as Controller
    participant PT as PulleyToken
    participant AI as AI Trader
    participant AW as AI Wallet
    participant BL as Blocklock

    Note over U,BL: User Deposit & Period Creation
    U->>TP: deposit(asset, $4)
    TP->>TP: record user contribution in period
    TP->>TP: update assetAvailableForTrading
    
    Note over U,BL: Threshold Check & Fund Allocation
    alt funds reach threshold
        TP->>PC: _sendFundsToControllerForPeriod()
        PC->>PC: allocate 15% insurance, 85% trading
        PC->>PT: mint insurance tokens (15%)
        PC->>AW: send 85% to AI wallet
        AW->>AW: track initial balance
    end
    
    Note over U,BL: AI Trading Execution
    AW->>AI: execute CFD trading
    AI->>AW: trading results
    AW->>AW: track balance changes (profit/loss)
    
    Note over U,BL: Profit/Loss Settlement
    AW->>PC: sendFunds(signature) - send profits back
    PC->>TP: profits with P&L data
    TP->>TP: distribute profits
    TP->>TP: calculate user's $$ estimated profit
    
    Note over U,BL: User Claim Process
    U->>TP: claimPeriodProfit(periodId, reinvest?)
    alt if (tradingShare > 0)
        TP->>U: transfer profits or reinvest
    end
    
    Note over U,BL: Automated Operations
    BL->>PC: automatedProfitLossCheck()
    BL->>PC: automatedRebalancing()
    PC->>PC: execute automated actions
```

## Continuous Trading Period Workflow

```mermaid
sequenceDiagram
    participant U as User
    participant TP as TradingPool
    participant PC as Controller
    participant PT as PulleyToken
    participant AI as AI Trader
    participant CL as Chainlink

    Note over U,AI: Continuous Trading Periods
    
    U->>TP: deposit(asset, amount)
    TP->>CL: getAssetUsdValue(asset, amount)
    CL-->>TP: USD value
    TP->>TP: mint pool tokens
    TP->>TP: update assetAvailableForTrading
    
    alt Threshold Reached
        TP->>TP: _checkAndStartNewTradingPeriod()
        TP->>TP: _startNewTradingPeriod()
        TP->>TP: update assetActivePeriods[]
        TP->>PC: _sendFundsToControllerForPeriod()
        PC->>PC: allocate 15% insurance, 85% trading
        PC->>PT: mint insurance tokens
        PC->>AI: initiate trading
    end
    
    Note over U,AI: Multiple Concurrent Periods
    U->>TP: deposit(asset, amount) [New user]
    TP->>TP: check threshold again
    alt New Threshold Reached
        TP->>TP: start another concurrent period
        TP->>PC: send funds for new period
    end
    
    Note over U,AI: Trading Results
    AI->>PC: reportTradingResult(requestId, pnl)
    
    alt Profit
        PC->>TP: distributePeriodProfit(asset, profit, periodId)
        TP->>TP: _removeActivePeriod(asset, periodId)
        TP->>TP: distribute to period participants
    else Loss
        PC->>TP: recordPeriodLoss(asset, loss, periodId)
        TP->>TP: _removeActivePeriod(asset, periodId)
        TP->>TP: apply losses to period participants
    end
    
    Note over U,AI: User Claims
    U->>TP: claimPeriodProfit(asset, periodId, reinvest)
    TP->>U: transfer profits or reinvest
```

## Key Improvements in Continuous Trading

### Before (Blocking System)
- Users couldn't deposit during active trading periods
- Single trading period at a time
- Users had to wait for period completion

### After (Continuous System)
- Users can always deposit
- Multiple concurrent trading periods
- Automatic period creation when thresholds are met
- Better user experience and capital efficiency

## Fund Allocation Flow

```mermaid
flowchart TD
    A[User Deposits Assets] --> B[Oracle Price Calculation]
    B --> C[Pool Token Minting]
    C --> D[Update Available Funds]
    D --> E{Threshold Reached?}
    
    E -->|No| F[Continue Accumulating]
    F --> E
    
    E -->|Yes| G[Start New Trading Period]
    G --> H[Add to Active Periods Array]
    H --> I[Transfer to Controller]
    I --> J[Calculate Allocation]
    
    J --> K[15% Insurance Allocation]
    J --> L[85% Trading Allocation]
    
    K --> M[Mint PulleyToken for Insurance]
    L --> N[Send to AI Trader]
    
    N --> O[AI Trading Execution]
    O --> P{Trading Result}
    
    P -->|Profit| Q[90% to Trading Pool]
    P -->|Profit| R[10% to Insurance]
    P -->|Loss| S{Insurance Coverage?}
    
    S -->|Yes| T[Burn Insurance Tokens]
    S -->|No| U[Reduce Pool Value]
    
    Q --> V[Distribute to Period Participants]
    R --> W[Add to Insurance Reserve]
    T --> X[Cover Losses]
    U --> Y[Apply Losses to Pool]
    
    V --> Z[Remove from Active Periods]
    W --> Z
    X --> Z
    Y --> Z
    
    Z --> AA[Period Complete]
    AA --> BB[New Deposits Can Start New Periods]
```

## Contract Structure & Relationships

```mermaid
classDiagram
    class PuLTradingPool {
        +mapping(address => uint256[]) assetActivePeriods
        +mapping(address => mapping(uint256 => uint256)) periodAssetAllocation
        +mapping(address => uint256) assetAvailableForTrading
        +deposit(address asset, uint256 amount)
        +withdraw(address asset, uint256 poolTokens)
        +_checkAndStartNewTradingPeriod(address asset)
        +_startNewTradingPeriod(address asset, uint256 amount)
        +distributePeriodProfit(address asset, uint256 profit, uint256 periodId)
        +recordPeriodLoss(address asset, uint256 loss, uint256 periodId)
        +getActivePeriods(address asset)
        +getPeriodInfo(address asset, uint256 periodId)
        +claimPeriodProfit(address asset, uint256 periodId, bool reinvest)
    }
    
    class PulleyToken {
        +address controller
        +address tradingPool
        +uint256 insuranceReserve
        +uint256 totalBackingValue
        +mapping(address => bool) supportedAssets
        +mint(address asset, uint256 backingAmount)
        +burn(address from, uint256 amount)
        +coverLoss(uint256 lossAmount)
        +addProfits(uint256 profitAmount)
        +getCurrentPrice()
    }
    
    class PulleyController {
        +address tradingPool
        +address pulleyStablecoin
        +address aiTrader
        +uint256 totalInsuranceFunds
        +uint256 totalTradingFunds
        +receiveFunds(address asset, uint256 amount)
        +reportTradingResult(bytes32 requestId, int256 pnl)
        +automatedProfitLossCheck()
        +automatedRebalancing()
        +getSystemMetrics()
    }
    
    class PermissionManager {
        +mapping(address => mapping(bytes4 => bool)) permissions
        +grantPermission(address account, bytes4 functionSelector)
        +revokePermission(address account, bytes4 functionSelector)
        +hasPermissions(address account, bytes4 functionSelector)
    }
    
    PuLTradingPool --> PulleyController : sends funds for periods
    PuLTradingPool --> PulleyToken : queries insurance
    PulleyController --> PulleyToken : mints insurance tokens
    PuLTradingPool --> PermissionManager : access control
    PulleyToken --> PermissionManager : access control
    PulleyController --> PermissionManager : access control
```