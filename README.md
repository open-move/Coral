# Coral - Move Package Safety Prediction Market Platform

A decentralized prediction market platform aiming to democratize Move packages security through community-driven prediction market.

Each package has its own prediction market, enabling users to express confidence or suspicion by buying or selling market tokens.

## 🎯 Overview

Coral leverages market mechanisms to aggregate subjective risk assessments of Move packages, similar to how traditional financial markets operate. The platform creates binary prediction markets (SAFE/RISKY) for each package, where community sentiment drives price discovery and reveals collective security insights.

### Key Features

- **Per-Package Markets**: Automatically deploy prediction markets for Move packages
- **LMSR Market Making**: Logarithmic Market Scoring Rule ensures liquidity and fair pricing
- **Community Risk Assessment**: Aggregate security insights through market participation
- **Real-time Sentiment**: Live pricing reflects current community confidence levels
- **Modular Architecture**: Separates market making, trading logic and other components.
- **Comprehensive Events**: Full audit trail of all market activities

## 🏗️ Architecture

### Modular Smart Contract Design

The platform is built with a modular architecture that separates core concerns:

```
coral/
├── sources/
│   ├── market.move          # Market creation and lifecycle management
│   ├── lmsr.move           # Market maker algorithm (swappable)
│   ├── outcome.move        # Outcome management
│   ├── math.move           # Mathematical utilities
│   └── registry.move       # Market registry and metadata (future)
├── tests/
    ├── market_tests.move   # Core market functionality tests
    ├── pricing_test.move   # LMSR algorithm validation
    └── tusd.move           # Test collateral token
```

### Market Maker Algorithm

Coral implements the **Logarithmic Market Scoring Rule (LMSR)** for automated market making:

#### Cost Function
```
C(q) = b × ln(∑ exp(qᵢ / b))
```

#### Price Calculation  
```
P(SAFE) = exp(q_safe/b) / (exp(q_safe/b) + exp(q_risky/b))
P(RISKY) = 1 - P(SAFE)
```

**Benefits:**
- **Guaranteed Liquidity**: Always-available trading without order books
- **Bounded Loss**: Maximum subsidy is predictable (b × ln(2))
- **Proper Scoring**: Incentivizes truthful probability reporting
- **Efficient Pricing**: Prices reflect aggregated market beliefs

## 📊 Community Sentiment Aggregation

### How It Works

1. **Package Upload**: New Move package deployed to Sui
2. **Market Creation**: Binary prediction market (SAFE/RISKY) automatically created
3. **Community Trading**: Users buy/sell tokens based on security assessment
4. **Price Discovery**: Market prices reflect collective risk evaluation
5. **Insight Generation**: Developers and users gain security insights

### Risk Signals

- **High SAFE Prices**: Community confidence in package security
- **High RISKY Prices**: Community suspects potential vulnerabilities  
- **Trading Volume**: Indicates strength of conviction
- **Price Volatility**: Uncertainty or new information incorporation

## 🖥️ User Interface Features

### Package Discovery
- Browse and search Move packages by safety score
- Filter by risk level, trading volume, or recent activity
- View package metadata, audit status, and market metrics

### Trading Interface
- One-click buy/sell for SAFE/RISKY tokens
- Real-time price calculations and slippage protection
- Portfolio management across multiple package markets
- Position tracking and profit/loss analysis

### Sentiment Dashboard
- Ecosystem-wide risk overview and trending packages
- Community alerts for rapid sentiment changes
- Historical price charts and trading analytics
- Developer reputation and package comparison tools

## 🔧 Technical Implementation

### Market Creation

```move
public fun create_package_market<SAFE: drop, RISKY: drop, C>(
    package_info: PackageMetadata,    // Package details and version info
    collateral_metadata: &CoinMetadata<C>,  // Trading collateral (USDC, SUI, etc.)
    liquidity_param: u64,             // LMSR liquidity parameter
    blob_id: ID,                      // Market description and metadata
    clock: &Clock,
    ctx: &mut TxContext
): (Market, MarketManagerCap)
```

### Trading Workflow

```move
// Initialize market snapshot for consistent pricing
let snapshot = market::initialize_outcome_snapshot(&market);
market::add_outcome_snapshot_data<SAFE>(&market, &mut snapshot, safe_outcome);
market::add_outcome_snapshot_data<RISKY>(&market, &mut snapshot, risky_outcome);

// Execute trade with slippage protection
let (shares, change) = market::buy_outcome<SAFE, USDC>(
    &mut market,
    snapshot,
    payment_coin,
    safe_outcome,
    amount,
    max_cost,
    &clock,
    ctx
);
```

### Event System

Comprehensive events track all platform activity:

- **MarketCreated**: New package market deployment
- **OutcomePurchased/Sold**: All trading activity with details
- **MarketResolved**: Final outcome determination
- **ConfigUpdated**: Platform parameter changes

## 🧪 Testing Suite

### Contract Testing
```bash
# Run all tests
sui move test
```

### Test Coverage
- **Market Lifecycle**: Creation, trading, resolution, closure
- **LMSR Algorithm**: Price accuracy under various conditions
- **Edge Cases**: Extreme market conditions and error handling
- **Access Controls**: Admin functions and security validations
- **Event Emission**: Comprehensive activity logging

## 🚀 Deployment

### Prerequisites
- Sui CLI and development environment
- Move compiler and testing framework

### Build and Deploy
```bash
# Clone repository
git clone https://github.com/0xDraco/Coral.git
cd Coral/packages/coral

# Build contracts
sui move build

# Run test suite
sui move test

# Deploy to testnet
sui client publish --gas-budget 100000000

# Deploy to mainnet
sui client publish --gas-budget 100000000 --network mainnet
```

## 💡 Use Cases

### For Developers
- **Risk Assessment**: Understand community perception of package security
- **Competitive Analysis**: Compare safety perception across similar packages
- **Security Incentives**: Market feedback drives better security practices
- **Reputation Building**: Consistent safety record builds market confidence

### For Package Users
- **Due Diligence**: Community-sourced security insights before integration
- **Risk Management**: Quantified safety scores for technical decisions
- **Discovery**: Find trusted packages through positive market signals
- **Early Warning**: Rapid detection of potential security concerns

### For Security Researchers
- **Monetized Research**: Profit from identifying package vulnerabilities
- **Information Sharing**: Signal security concerns to broader community
- **Reputation Building**: Build credibility through accurate predictions
- **Ecosystem Service**: Contribute to overall Move ecosystem security

## 🔒 Security & Governance

### Smart Contract Security
- **Modular Design**: Isolated components minimize upgrade risks
- **Access Controls**: Multi-signature admin functions where needed
- **Pause Mechanisms**: Emergency stops for critical issues
- **Comprehensive Testing**: Extensive test coverage for all scenarios

### Platform Governance
- **Parameter Management**: Community input on market parameters
- **Market Resolution**: Clear processes for outcome determination
- **Upgrade Proposals**: Transparent enhancement and bug fix procedures
- **Dispute Resolution**: Fair handling of edge cases and conflicts

## 📈 Economic Model

### Market Dynamics
- **Information Markets**: Traders profit from superior security knowledge
- **Incentive Alignment**: Accurate risk assessment generates returns
- **Community Participation**: Low barriers to entry encourage broad involvement
- **Continuous Discovery**: 24/7 price updates reflect new information

### Platform Sustainability
- **Trading Fees**: Small percentage of trade volume supports platform
- **Market Creation**: Fees for deploying new package markets
- **Value Creation**: Security insights benefit entire ecosystem
- **Network Effects**: More participants improve signal quality

## 📚 Documentation

### Architecture Documentation
- **System Design**: Detailed component interactions and data flows
- **Module Specifications**: Complete API documentation for all contracts
- **Integration Guides**: How to connect external systems and frontends
- **Upgrade Procedures**: Safe contract enhancement methodologies

### User Documentation
- **Trading Guide**: How to participate in prediction markets
- **Developer Guide**: Integrating package safety scores into workflows
- **API Reference**: Complete interface documentation
- **Troubleshooting**: Common issues and resolution procedures

## 🎯 Roadmap

### Phase 1: Core Platform (Current)
- ✅ Binary prediction markets for packages
- ✅ LMSR automated market making
- ✅ Comprehensive event system
- ✅ Basic admin controls and testing

### Phase 2: Enhanced Features
- [ ] Multi-outcome markets (beyond binary)
- [ ] Package version tracking and comparison
- [ ] Audit integration and professional assessments
- [ ] Advanced analytics and historical data

### Phase 3: Ecosystem Integration
- [ ] Cross-package dependency risk analysis
- [ ] Governance token and decentralized management

## 🤝 Contributing

We welcome contributions from the Move and Sui ecosystem:

1. **Code Contributions**: Bug fixes, feature enhancements, optimizations
2. **Testing**: Additional test cases and edge case validation
3. **Documentation**: User guides, tutorials, and technical documentation
4. **Research**: Economic modeling, security analysis, and algorithm improvements

### Development Process
1. Fork repository and create feature branch
2. Implement changes with comprehensive tests
3. Submit pull request with detailed description
4. Code review and collaborative improvement
5. Integration and deployment
