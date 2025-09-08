# Pulley Protocol - AI Trading with Insurance

Pulley Protocol is a DeFi trading system that enables users to participate in AI-driven trading strategies while providing insurance coverage through a floating stablecoin mechanism. The system features Chainlink price feeds, automated profit/loss distribution, and dual minting logic for insurance coverage.

## System Architecture Overview
## System Architecture Overview

```mermaid
graph TB
    subgraph "User Layer"
        U[User]
    end
    
    subgraph "Core Contracts"
        TP[PuLTradingPool<br/>- User deposits<br/>- Trading periods<br/>- Profit distribution]
        PT[PulleyToken<br/>- Insurance stablecoin<br/>- Floating price mechanism<br/>- Loss coverage]
        PC[PulleyController<br/>- Fund allocation<br/>- AI coordination<br/>- PnL reporting]
        AW[AI Wallet<br/>- Fund management<br/>- ECDSA signatures<br/>- Trading execution]
    end
    
    subgraph "Factory & Cloning"
        CF[ClonePuLTrade<br/>- Strategy creation<br/>- Pool cloning<br/>- Controller setup]
        TP[PuLTradingPool<br/>- User deposits<br/>- Trading periods<br/>- Profit distribution]
        PT[PulleyToken<br/>- Insurance stablecoin<br/>- Floating price mechanism<br/>- Loss coverage]
        PC[PulleyController<br/>- Fund allocation<br/>- AI coordination<br/>- PnL reporting]
        AW[AI Wallet<br/>- Fund management<br/>- ECDSA signatures<br/>- Trading execution]
    end
    
    subgraph "Factory & Cloning"
        CF[ClonePuLTrade<br/>- Strategy creation<br/>- Pool cloning<br/>- Controller setup]
    end
    
    subgraph "External Systems"
        AI[AI System<br/>- CFD Trading<br/>- Strategy execution]
        CL[Chainlink<br/>- Price feeds<br/>- Oracle data]
        AI[AI System<br/>- CFD Trading<br/>- Strategy execution]
        CL[Chainlink<br/>- Price feeds<br/>- Oracle data]
        BL[Blocklock<br/>- Automation<br/>- Timelock encryption]
    end
    
    subgraph "Infrastructure"
        PM[PermissionManager<br/>- Access control<br/>- Function permissions]
    end
    
    U -->|Deposit assets| TP
    TP -->|Pool tokens| U
    TP -->|Funds when threshold| PC
    TP -->|Funds when threshold| PC
    PC -->|15% insurance| PT
    PC -->|85% trading| AW
    AW -->|Trading results| PC
    PC -->|85% trading| AW
    AW -->|Trading results| PC
    PC -->|Profit/loss| TP
    CF -->|Create strategies| TP
    CF -->|Create strategies| PC
    CF -->|Create strategies| AW
    CF -->|Create strategies| TP
    CF -->|Create strategies| PC
    CF -->|Create strategies| AW
    BL -->|Automation| PC
    CL -->|Price data| TP
    PM -->|Permissions| TP
    PM -->|Permissions| PT
    PM -->|Permissions| PC
    PM -->|Permissions| AW
    PM -->|Permissions| AW
```

## Complete Trading Flow
## Complete Trading Flow

```mermaid
sequenceDiagram
    participant U as User
    participant U as User
    participant TP as TradingPool
    participant PC as PulleyController
    participant PC as PulleyController
    participant PT as PulleyToken
    participant AW as AI Wallet
    participant AI as AI System
    participant AI as AI System

    Note over U,AI: 1. User Deposit & Period Creation
    U->>TP: deposit(asset, amount)
    Note over U,AI: 1. User Deposit & Period Creation
    U->>TP: deposit(asset, amount)
    TP->>TP: record user contribution in period
    TP->>TP: update assetAvailableForTrading
    
    Note over U,AI: 2. Threshold Check & Fund Allocation
    Note over U,AI: 2. Threshold Check & Fund Allocation
    alt funds reach threshold
        TP->>PC: _sendFundsToControllerForPeriod()
        PC->>PC: allocate 15% insurance, 85% trading
        PC->>PT: mint insurance tokens (15%)
        PC->>AW: receiveFunds(85% of funds)
        PC->>AW: receiveFunds(85% of funds)
        AW->>AW: track initial balance
    end
    
    Note over U,AI: 3. AI Trading Execution
    Note over U,AI: 3. AI Trading Execution
    AW->>AI: execute CFD trading
    AI->>AW: trading results
    AW->>AW: track balance changes (profit/loss)
    
    Note over U,AI: 4. PnL Reporting & Fund Retrieval
    PC->>AW: reportTradingResults() - calls getSessionInfo()
    AW-->>PC: returns PnL data
    alt if profit > 0
        PC->>AW: sendFunds(signature) - retrieve profits
        AW->>PC: transfer profits back
        PC->>TP: distributePeriodProfit()
        TP->>U: claimPeriodProfit()
    else if loss > 0
        PC->>PT: coverLoss() - burn insurance tokens
        PC->>TP: distributeInsuranceRefund()
        TP->>U: refund 15% insurance portion
    end
    Note over U,AI: 4. PnL Reporting & Fund Retrieval
    PC->>AW: reportTradingResults() - calls getSessionInfo()
    AW-->>PC: returns PnL data
    alt if profit > 0
        PC->>AW: sendFunds(signature) - retrieve profits
        AW->>PC: transfer profits back
        PC->>TP: distributePeriodProfit()
        TP->>U: claimPeriodProfit()
    else if loss > 0
        PC->>PT: coverLoss() - burn insurance tokens
        PC->>TP: distributeInsuranceRefund()
        TP->>U: refund 15% insurance portion
    end
```

## Contract Architecture & Relationships
## Contract Architecture & Relationships

```mermaid
classDiagram
    class PuLTradingPool {
        +address controller
        +address pulleyToken
        +address permissionManager
        +address controller
        +address pulleyToken
        +address permissionManager
        +mapping(address => uint256[]) assetActivePeriods
        +mapping(address => uint256) assetAvailableForTrading
        +deposit(address asset, uint256 amount)
        +withdraw(address asset, uint256 poolTokens)
        +_checkAndStartNewTradingPeriod(address asset)
        +_startNewTradingPeriod(address asset, uint256 amount)
        +distributePeriodProfit(address asset, uint256 profit, uint256 periodId)
        +recordPeriodLoss(address asset, uint256 loss, uint256 periodId)
        +distributeInsuranceRefund(address asset, uint256 periodId)
        +distributeInsuranceRefund(address asset, uint256 periodId)
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
        +getGrowthMetrics()
        +getGrowthMetrics()
    }
    
    class PulleyController {
        +address tradingPool
        +address pulleyToken
        +address aiWallet
        +address permissionManager
        +address pulleyToken
        +address aiWallet
        +address permissionManager
        +receiveFunds(address asset, uint256 amount)
        +reportTradingResults(address asset)
        +checkAIWalletPnL(address asset)
        +reportTradingResults(address asset)
        +checkAIWalletPnL(address asset)
        +getSystemMetrics()
        +setAIWallet(address payable _aiWallet)
    }
    
    class Wallet {
        +address controller
        +address aiSigner
        +mapping(address => uint256) balances
        +receiveFunds(address asset, uint256 amount)
        +sendFunds(address asset, uint256 amount, bytes signature)
        +getSessionInfo() returns (int256 pnl, uint256 initialBalance, uint256 currentBalance)
        +getCurrentPnL(address asset)
        +updateAISigner(address newSigner)
    }
    
    class ClonePuLTrade {
        +address tradingPoolImplementation
        +address controllerImplementation
        +address walletImplementation
        +address pulleyToken
        +createClone(PoolCloneConfig config)
        +quickCreateClone(address nativeAsset, address customAsset, uint8 customAssetDecimals)
        +_configureCloneAssets(address pool, PoolCloneConfig config)
        +setAIWallet(address payable _aiWallet)
    }
    
    class Wallet {
        +address controller
        +address aiSigner
        +mapping(address => uint256) balances
        +receiveFunds(address asset, uint256 amount)
        +sendFunds(address asset, uint256 amount, bytes signature)
        +getSessionInfo() returns (int256 pnl, uint256 initialBalance, uint256 currentBalance)
        +getCurrentPnL(address asset)
        +updateAISigner(address newSigner)
    }
    
    class ClonePuLTrade {
        +address tradingPoolImplementation
        +address controllerImplementation
        +address walletImplementation
        +address pulleyToken
        +createClone(PoolCloneConfig config)
        +quickCreateClone(address nativeAsset, address customAsset, uint8 customAssetDecimals)
        +_configureCloneAssets(address pool, PoolCloneConfig config)
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
    PulleyController --> Wallet : manages AI wallet
    Wallet --> PulleyController : reports PnL
    ClonePuLTrade --> PuLTradingPool : creates pool instances
    ClonePuLTrade --> PulleyController : creates controller instances
    ClonePuLTrade --> Wallet : creates wallet instances
    PulleyController --> Wallet : manages AI wallet
    Wallet --> PulleyController : reports PnL
    ClonePuLTrade --> PuLTradingPool : creates pool instances
    ClonePuLTrade --> PulleyController : creates controller instances
    ClonePuLTrade --> Wallet : creates wallet instances
    PuLTradingPool --> PermissionManager : access control
    PulleyToken --> PermissionManager : access control
    PulleyController --> PermissionManager : access control
    Wallet --> PermissionManager : access control
```

## Fund Flow Diagram

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
    L --> N[Send to AI Wallet]
    
    N --> O[AI Trading Execution]
    O --> P{Trading Result}
    
    P -->|Profit| Q[Controller calls sendFunds with signature]
    P -->|Loss| R[Controller calls coverLoss]
    
    Q --> S[Distribute to Period Participants]
    R --> T[Burn Insurance Tokens]
    R --> U[Refund 15% Insurance to Users]
    
    S --> V[Remove from Active Periods]
    T --> V
    U --> V
    
    V --> W[Period Complete]
    W --> X[New Deposits Can Start New Periods]
```

## AI Wallet PnL Flow

```mermaid
sequenceDiagram
    participant PC as PulleyController
    participant AW as AI Wallet
    participant AI as AI System

    Note over PC,AI: 1. Fund Allocation
    PC->>AW: receiveFunds(asset, amount)
    AW->>AW: track initial balance
    
    Note over PC,AI: 2. AI Trading
    AW->>AI: execute trading strategy
    AI->>AW: trading results
    AW->>AW: update balance (profit/loss)
    
    Note over PC,AI: 3. PnL Reporting
    PC->>AW: reportTradingResults() - calls getSessionInfo()
    AW-->>PC: returns (pnl, initialBalance, currentBalance)
    
    Note over PC,AI: 4. Fund Retrieval (if profit)
    alt if pnl > 0
        PC->>PC: generate ECDSA signature
        PC->>AW: sendFunds(asset, amount, signature)
        AW->>AW: verify signature
        AW->>PC: transfer profits
    end
    
    Note over PC,AI: 5. Loss Handling (if loss)
    alt if pnl < 0
        PC->>PC: call coverLoss() on PulleyToken
        PC->>PC: distributeInsuranceRefund() on TradingPool
    end
```

## Clone Factory Strategy Creation

```mermaid
flowchart TD
    A[User Wants New Strategy] --> B[Call ClonePuLTrade.quickCreateClone]
    B --> C[Deploy TradingPool Clone]
    B --> D[Deploy Controller Clone]
    B --> E[Deploy Wallet Clone]
    
    C --> F[Configure Native Asset]
    D --> G[Configure Native Asset]
    E --> H[Configure Native Asset]
    
    F --> I[Configure Custom Asset]
    G --> J[Configure Custom Asset]
    H --> K[Configure Custom Asset]
    
    I --> L[Set Permissions]
    J --> L
    K --> L
    
    L --> M[Return Strategy Addresses]
    M --> N[User Can Start Trading]
    
    style A fill:#e1f5fe
    style M fill:#c8e6c9
    style N fill:#c8e6c9
```






## Mathematical Foundation

### PulleyToken Price Calculation

The PulleyToken uses a floating price mechanism based on the insurance reserve and total backing value:

```
P(t) = (Total Backing Value + Insurance Reserve) / Total Supply
```

Where:
- `P(t)` = Current price of PulleyToken at time t
- `Total Backing Value` = Sum of all asset values backing the token
- `Insurance Reserve` = Accumulated insurance funds
- `Total Supply` = Current circulating supply of PulleyTokens

### Growth Rate Calculation

The growth rate determines how the token price increases over time:

```
Growth Rate = (Insurance Reserve / Total Backing Value) × 100%
```

### Fund Allocation Formula

When funds reach the threshold, they are allocated as follows:

```
Insurance Allocation = Total Funds × 0.15
Trading Allocation = Total Funds × 0.85
```

### Profit Distribution

When trading results in profit:

```
User Profit Share = (User Contribution / Total Period Contribution) × Net Profit × 0.90
Insurance Growth = Net Profit × 0.10
```

Where:
- `Net Profit` = Trading Profit - Gas Costs - Fees
- `0.90` = 90% goes to users
- `0.10` = 10% goes to insurance reserve

### Loss Coverage Calculation

When trading results in loss:

```
Insurance Required = |Loss Amount|
Tokens to Burn = Insurance Required / Current PulleyToken Price
User Refund = User's 15% Insurance Portion
```

### PnL Calculation

The AI Wallet calculates PnL as:

```
PnL = Current Balance - Initial Balance
PnL% = (PnL / Initial Balance) × 100%
```

### Period Profit Distribution

For each trading period, user profits are calculated as:

```
User Period Profit = (User Pool Tokens / Total Pool Tokens) × Period Net Profit
```

### Insurance Reserve Growth

The insurance reserve grows through:

```
New Reserve = Previous Reserve + (Trading Profit × 0.10) + New Insurance Allocations
```

### Token Minting Formula

When minting PulleyTokens for insurance:

```
Tokens to Mint = Insurance Allocation / Current PulleyToken Price
```

### Utilization Rate

The utilization rate affects the token price:

```
Utilization Rate = (Total Backing Value / (Total Backing Value + Insurance Reserve)) × 100%
```

### Price Impact of Losses

When losses occur and insurance is used:

```
New Price = (Total Backing Value - Loss Amount) / (Total Supply - Burned Tokens)
```

### Example Calculation

Let's say:
- User deposits $1000 USDC
- Threshold is $5000 (already reached)
- Current PulleyToken price = $1.05
- Trading results in $200 profit

**Allocation:**
- Insurance: $1000 × 0.15 = $150
- Trading: $1000 × 0.85 = $850

**PulleyToken Minting:**
- Tokens minted: $150 / $1.05 = 142.86 tokens

**Profit Distribution:**
- User profit: $200 × 0.90 = $180
- Insurance growth: $200 × 0.10 = $20

**New PulleyToken Price:**
- New reserve: Previous + $20
- New total backing: Previous + $1000 + $20
- New price: (New total backing) / (Previous supply + 142.86)

### Loss Scenario Example

If trading results in $300 loss:

**Insurance Coverage:**
- Tokens to burn: $300 / $1.05 = 285.71 tokens
- User refund: $150 (their 15% insurance portion)

**New PulleyToken Price:**
- New reserve: Previous - $300
- New total backing: Previous + $1000 - $300
- New price: (New total backing) / (Previous supply + 142.86 - 285.71)

### Advanced Mathematical Models

#### Compound Growth Model

For long-term price appreciation:

```
P(t) = P(0) × (1 + r)^t
```

Where:
- `P(0)` = Initial price
- `r` = Growth rate per period
- `t` = Number of periods

#### Risk-Adjusted Returns

The system calculates risk-adjusted returns as:

```
Sharpe Ratio = (Expected Return - Risk-Free Rate) / Standard Deviation
```

#### Insurance Coverage Ratio

The coverage ratio determines system stability:

```
Coverage Ratio = Insurance Reserve / (Average Loss × Loss Frequency)
```

#### Liquidity Pool Health

Pool health is measured by:

```
Health Score = (Available Liquidity / Total Deposits) × (1 - Utilization Rate)
```

## Contract Overview

| Contract | Purpose | Key Functions |
|----------|---------|---------------|
| `PuLTradingPool` | User deposits and trading periods | `deposit()`, `claimPeriodProfit()`, `distributePeriodProfit()` |
| `PulleyToken` | Insurance stablecoin | `mint()`, `burn()`, `coverLoss()`, `getCurrentPrice()` |
| `PulleyController` | Fund allocation and AI coordination | `receiveFunds()`, `reportTradingResults()`, `checkAIWalletPnL()` |
| `Wallet` | AI fund management | `receiveFunds()`, `sendFunds()`, `getSessionInfo()` |
| `ClonePuLTrade` | Strategy creation factory | `quickCreateClone()`, `createClone()` |
| `PermissionManager` | Access control | `grantPermission()`, `hasPermissions()` |

## Address
  === CORE CONTRACTS ===
  PermissionManager: 0xDba4B629FA01436E0f6849B54B4744ef65a53FDa
  Wallet: 0xCc323BC5DE01A1F3ab8F79CDdF49Fe9017375e74
  PulleyToken: 0xDfC78De351B42788F9a3704E60f1DEF108cCcDe2
  Clone Factory: 0x9f3C93dD934998B9B334bAd67fAC405733FcD98b
  
  === MAIN TRADING POOL (CREATED VIA CLONE) ===
  TradingPool: 0x44E7Efb96eB7D1677A6144285c81b8378661BbF8
  Controller: 0x0f3467e867760c8b188C46c5A283a88c90599E25
  
  === MOCK TOKENS ===
  USDC: 0xf63915eEB4d7d8f17f597CD3E2d749C8A43CF9F4
  USDT: 0x187af3FFbdF71172B217B8Ada11f39224FbCf935
  sToken: 0x63a2fB46b32CDF7DB176dd59d91Ef89D23E859d1