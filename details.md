# Pulley Protocol - Detailed Technical Overview

## What is Pulley?

Pulley Protocol is a decentralized finance (DeFi) trading system that enables anyone to create and deploy their own AI-driven trading strategies while providing built-in insurance coverage through a floating stablecoin mechanism. The protocol is designed as a factory-based system where users can clone and customize trading pools with their own parameters and assets.

## Core Architecture

### 1. Factory & Cloning System

The heart of Pulley is the **ClonePuLTrade** factory contract that allows anyone to create their own trading strategy by cloning the core components:

- **Trading Pool Clone**: A customized trading pool with user-defined parameters
- **Controller Clone**: Manages fund allocation and AI coordination for the specific strategy
- **Wallet Clone**: Handles AI trading funds 

Each clone supports three assets:
- **Native Asset**: sonic Chain's native token 
- **PulleyToken**: The protocol's floating stablecoin for insurance
- **Custom Asset**: Any ERC-20 token chosen by the strategy creator

### 2. Core Components

#### PulleyController
- **Fund Allocation**: Automatically splits incoming funds 85% to AI trading, 15% to insurance
- **AI Integration**: Manages communication with external AI trading systems
- **Profit Distribution**: 90% to trading participants, 10% to insurance pool
- **Automation**: Integrates with Blocklock for automated operations

#### PulleyToken (Floating Stablecoin)
- **Dynamic Pricing**: Token value grows based on system utilization and performance
- **Insurance Mechanism**: Provides coverage for trading losses
- **Dual Minting Logic**: Different minting rules for insurance vs. external users
- **Growth Algorithm**: Base growth rate + utilization multiplier

#### PuLTradingPool
- **User Deposits**: Accepts multiple asset types with threshold-based trading
- **Oracle Integration**: Uses Chainlink price feeds for asset valuation
- **Profit Distribution**: Automated P&L calculation and distribution
- **Period Management**: Handles trading periods and user withdrawals

#### AI Wallet

- **Session Tracking**: Monitors trading sessions and P&L
- **Nonce Protection**: Prevents signature replay attacks
- **Automated Reporting**: Reports trading results back to controller

## How It Works

### 1. Strategy Creation Process

1. **Clone Creation**: User calls `createClone()` with custom configuration:
   - Pool name and symbol
   - Custom asset selection
   - Trading thresholds for each asset
   - Asset decimals configuration

2. **Component Deployment**: Factory creates three clones:
   - Trading pool with custom parameters
   - Controller for fund management
   - Wallet for AI trading operations

3. **Asset Configuration**: Each clone supports three assets:
   - Native token (automatically detected)
   - PulleyToken (for insurance)
   - Custom ERC-20 token (user-selected)

### 2. Fund Flow and Allocation

When users deposit funds into a trading pool:

1. **Fund Reception**: Pool receives user deposits in supported assets
2. **Controller Allocation**: Funds are sent to the controller for processing
3. **Automatic Split**: Controller splits funds:
   - 85% → AI trading wallet
   - 15% → Insurance pool (mints PulleyTokens)
4. **AI Trading**: Trading portion is sent to AI wallet for strategy execution
5. **Insurance Coverage**: Insurance portion backs PulleyToken for loss protection

### 3. AI Trading Integration

The AI trading system operates through:

1. **Fund Transfer**: Controller sends 85% of funds to AI wallet
2. **Session Management**: Wallet starts new trading session with initial balance
3. **External Trading**: AI system executes trades outside the protocol
4. **Signature-Based Returns**: AI uses ECDSA signatures to return profits
5. **P&L Reporting**: Wallet calculates and reports trading results
6. **Profit Distribution**: Controller distributes profits (90% to users, 10% to insurance)

### 4. Insurance Mechanism

The PulleyToken provides insurance through:

1. **Floating Value**: Token price grows based on system performance
2. **Loss Coverage**: Insurance reserves cover trading losses
3. **Growth Algorithm**: 
   - Base growth: 1% daily
   - Utilization bonus: 0.5% per utilization point
   - Maximum growth: 10% daily
4. **Dual Minting**: Different rules for insurance vs. external minting

### 5. Automation and Security

- **Blocklock Integration**: Automated operations using time-locked encryption
- **Permission Management**: Role-based access control
- **Reentrancy Protection**: All critical functions protected
- **Signature Verification**: ECDSA for secure AI operations
- **Nonce System**: Prevents replay attacks

## Key Features

### For Strategy Creators
- **Custom Asset Selection**: Choose any ERC-20 token for trading
- **Flexible Thresholds**: Set custom trading thresholds per asset
- **Independent Operation**: Each clone operates independently
- **Full Control**: Complete control over strategy parameters

### For Users
- **Multi-Asset Support**: Deposit various asset types
- **Insurance Coverage**: Built-in loss protection through PulleyToken
- **Transparent P&L**: Real-time profit/loss tracking
- **Automated Distribution**: Automatic profit sharing

### For AI Systems
- **Signature-Based Security**: Secure fund management
- **Session Tracking**: Clear trading session management
- **Flexible Integration**: Easy integration with external AI systems
- **Automated Reporting**: Built-in P&L reporting

## Technical Specifications

### Fund Allocation
- Trading: 85% of deposited funds
- Insurance: 15% of deposited funds

### Profit Distribution
- Users: 90% of trading profits
- Insurance: 10% of trading profits

### PulleyToken Growth
- Base Rate: 1% daily
- Utilization Multiplier: 0.5% per utilization point
- Maximum Rate: 10% daily
- Update Interval: 24 hours

### Security Features
- Automated time-locked operations

## Use Cases

1. **Custom Trading Strategies**: Deploy unique trading algorithms
2. **Multi-Asset Pools**: Create pools with specific asset combinations
3. **Insurance-Protected Trading**: Trade with built-in loss protection
4. **AI Integration**: Connect external AI systems for automated trading
5. **Community Strategies**: Allow others to participate in custom strategies


Pulley Protocol democratizes AI trading by providing a factory-based system where anyone can create, deploy, and manage their own trading strategies. The combination of cloning technology, insurance mechanisms, and AI integration creates a powerful platform for decentralized trading with built-in risk management. The protocol's modular design allows for maximum flexibility while maintaining security and automation through smart contract technology.


Pulley works by giving anyone the ability to create their own AI-powered trading strategy through a simple factory system. Instead of writing everything from scratch, the user interacts with Pulley’s factory contract, which automatically deploys three components: a trading pool for deposits, a controller that manages fund allocation, and a special AI wallet that interacts with external AI trading bots. These three pieces form a self-contained strategy environment.

When investors deposit assets into the trading pool, the funds don’t all go straight into trading. The controller steps in to enforce Pulley’s built-in safety mechanism. It splits deposits so that the majority — about 85% — goes to the AI wallet, where the strategy’s trades are executed. The remaining 15% is routed to the insurance system, which is powered by PulleyToken, a floating stablecoin whose value grows with protocol usage. This means that every time someone participates in a strategy, they are also strengthening the insurance pool that protects against losses.

The AI wallet then begins a trading session. The trades themselves happen off-chain, where the AI has more flexibility and speed. Once the AI finishes a round of trading, it reports the results back on-chain using cryptographic signatures. The controller verifies these results and calculates the profit or loss. If profits were made, most of the gains (90%) are distributed back to the pool’s participants, while a smaller portion (10%) is added to the insurance reserve. If instead losses occur, the insurance pool steps in to absorb some of the impact, softening the downside for users.

Over time, the PulleyToken itself becomes stronger. Its value isn’t fixed like a normal stablecoin; it grows dynamically. Each day it gains a baseline growth rate, and as more people use Pulley and more insurance is required, it grows even faster. This design means that the more strategies are created and the more deposits flow in, the safer the system becomes for everyone.

In practice, this creates a loop: deposits fuel trading, trading fuels profits (or losses), profits strengthen the insurance pool, and insurance gives users confidence to keep depositing. Meanwhile, Pulley’s automation ensures all of this runs smoothly, with no need for constant manual updates.