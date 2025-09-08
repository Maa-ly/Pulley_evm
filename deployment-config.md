# Deployment Configuration

## Environment Variables Required

Create a `.env` file in the project root with the following variables:

```bash
# Deployment Configuration
PRIVATE_KEY=your_private_key_here
KWN=0x0000000000000000000000000000000000000000
TREASURY=0x0000000000000000000000000000000000000000
TIE_SLASH_BPS=400

# RPC URLs
KAIATESTNET_RPC_URL=https://rpc.testnet.kairoschain.com
MAINNET_RPC_URL=https://rpc.kairoschain.com
```

## Deployment Commands

### Deploy to Kairos Testnet
```bash
forge script script/DeployDisputeMarket.s.sol --rpc-url kaiatestnet --broadcast --verify
```

### Deploy to Local Fork
```bash
forge script script/DeployDisputeMarket.s.sol --fork-url kaiatestnet --broadcast
```

### Deploy with Custom Parameters
```bash
forge script script/DeployDisputeMarket.s.sol \
  --rpc-url kaiatestnet \
  --broadcast \
  --verify \
  --sig "run()" \
  --private-key $PRIVATE_KEY
```

## Mock Tokens

The deployment script will automatically deploy:
- Mock USDC (6 decimals)
- Mock USDT (6 decimals) 
- Mock sToken (18 decimals)

Each mock token includes a `faucet()` function for easy testing.



