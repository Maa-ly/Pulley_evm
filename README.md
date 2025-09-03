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

## Key Features & Benefits

### 🚀 **Simplified Architecture**
- Single-chain operation (no complex cross-chain)
- Four core contracts working in harmony
- Clear separation of concerns

### 💰 **Floating Stablecoin**
- PulleyToken grows with utilization
- Not pegged 1:1 like traditional stablecoins
- Dynamic pricing based on system performance

### 🛡️ **Insurance Mechanism**
- 15% of funds allocated to insurance
- Automatic loss coverage before pool impact
- Insurance reserve grows with profits

### 🤖 **AI Trading Integration**
- 85% of funds deployed to AI strategies
- Automated profit/loss reporting
- Real-time performance monitoring

### ⚡ **Automation**
- Blocklock-powered automation
- Automated profit/loss checking
- Automated rebalancing

### 🔒 **Security**
- Permission-based access control
- Reentrancy protection
- Oracle-based price feeds

## How It Works

### Simplified System Architecture
Pulley Protocol now operates as a simplified single-chain system with four core contracts:

1. **TradingPool** - Users deposit funds, get minted pool tokens based on oracle pricing, threshold mechanism triggers fund transfer
2. **PulleyToken** - Floating stablecoin that grows with utilization (NOT 1:1 ratio), anyone can mint
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

### Asset Conversion & Bridging
When users deposit assets (ETH, USDC, Core Token, etc.) into Pulley on Kaia Network, the protocol follows this process:

1. **Asset Swapping**: All deposited assets are first converted to **Kaia native USDT** using the AssetSwapper contract
2. **Why USDT?**: USDT serves as the standard stable asset for cross-chain operations, providing:
   - Price stability during bridging
   - Universal acceptance across chains
   - Reduced slippage in destination chain operations
   - Consistent value representation

3. **Cross-Chain Bridging**: The USDT is then bridged from Kaia Network to Ethereum using LayerZero infrastructure

### Fund Allocation Strategy
Once bridged to Ethereum, the Controller allocates funds according to this strategy:

- **10% → Insurance Reserve**: Converted to Pulley Tokens for loss protection
- **45% → Nest Protocol Vaults**: Real-world asset (RWA) exposure on Ethereum
- **45% → Limit Order Trading**: Active trading strategies on Ethereum DEXs

### Insurance Mechanism
The Pulley Token acts as an insurance reserve for the entire system. When trading strategies generate profits:
- **50% of profits** are distributed to insurance providers (PulleyToken holders)
- **50% of profits** are reinvested in the trading pool

If trading strategies incur losses, the Pulley Token reserve automatically covers them, ensuring users' deposits remain protected.

## Technical Workflow

### 1. User Deposit (Kaia Network)
- User deposits assets into Pulley's trading vault on Kaia Network
- System checks if total assets exceed minimum threshold for efficiency

### 2. Asset Conversion & Bridging
- **AssetSwapper** converts all assets to Kaia native USDT
- **CrossChainController** initiates bridging to Ethereum via LayerZero
- USDT is transferred to Ethereum destination chain

### 3. Strategy Execution (Ethereum)
- **Nest Protocol Vaults**: 45% deployed to RWA yield-generating strategies
- **Limit Order Trading**: 45% deployed to active trading strategies
- **Insurance Reserve**: 10% held as Pulley Tokens for protection

### 4. Profit Collection & Distribution
- Profits from Ethereum strategies are bridged back to Kaia Network
- **50% → Insurance providers** (PulleyToken holders)
- **50% → Trading pool** for reinvestment

### 5. Continuous Cycle
- System continuously monitors and rebalances allocations
- Insurance reserve grows stronger over time
- Users benefit from Ethereum opportunities while staying on Kaia Network

## Why This Architecture?

### Kaia Network Benefits
- **Lower fees** for user deposits and withdrawals
- **Faster transactions** for day-to-day operations
- **Native asset support** for Core ecosystem tokens

### Ethereum Benefits
- **Largest DeFi ecosystem** with highest liquidity
- **Best yield opportunities** in RWA and trading strategies
- **Mature infrastructure** for complex financial operations

### Cross-Chain Bridge Benefits
- **Asset diversification** across multiple networks
- **Risk mitigation** through geographic and technical distribution
- **Access to best opportunities** regardless of chain location

## Key Components

- **AssetSwapper**: Converts assets to Kaia native USDT
- **CrossChainController**: Manages fund allocation and cross-chain messaging
- **LayerZero**: Provides secure cross-chain communication
- **Nest Protocol**: RWA vaults on Ethereum for yield generation
- **Trading Strategies**: Active limit order and spot trading on Ethereum DEXs

This architecture ensures users can access the best DeFi opportunities on Ethereum while maintaining the benefits of Kaia Network, all protected by a robust insurance system that grows stronger over time.