# Auto-Halt Unusual Activity Trap
A comprehensive Drosera trap system that automatically detects and halts unusual activities in DeFi protocols, including treasury drains, excessive minting, and governance attacks.

# 🛡️ Overview

This trap monitors blockchain activity in real-time and automatically pauses target contracts when unusual patterns are detected, providing protection against:

Treasury Drains: Rapid or large-scale asset withdrawals

Token Supply Manipulation: Excessive minting or burning events

Governance Flooding: Spam proposal attacks

Rapid Activity Patterns: Coordinated multi-transaction exploits

# 🏗️ Architecture

graph

    A[Drosera Operators] --> B[AutoHaltTrap] 
    B --> C[Data Collection]
    B --> D[Pattern Analysis] 
    D --> E[Incident Detection]
    E --> F[AutoHaltTrapConfig]
    F --> G[Pause Target Contract]
    
    H[Event Logs] --> C
    I[Treasury Balance] --> C
    J[Token Supply] --> C
    K[Governance Data] --> C
# 🚀 Quick Start
**Prerequisites**

**. Foundry**

**. Git**

# Installation

**1. Clone the repository**

```bash
git clone https://github.com/your-username/auto-halt-trap.git
```

```bash
cd auto-halt-trap
```

**Install dependencies**

```bash
forge install
```

**Build contracts**

```bash
forge build
```

**Run tests**

```bash
forge test
```

# Deployment

```bash # Set environment variables
export PRIVATE_KEY=0x...
export TARGET_CONTRACT=0x...
export RPC_URL=https://...

# Deploy the trap system
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

# 📋 Configuration

```bash
AutoHaltTrap trap = new AutoHaltTrap({
    _targetContract: 0x...,           // Contract to protect
    _maxTreasuryDrainPercent: 30,     // 30% max drain per block
    _maxSupplyIncreasePercent: 50,    // 50% max supply increase
    _maxGovernanceProposalsPerBlock: 3, // Max proposals per block
    _maxLargeTransfersPerBlock: 5,    // Max large transfers
    _rapidActionThreshold: 3,         // Rapid action detection
    _analysisWindow: 10,              // Analysis window in blocks
    _largeTransferThreshold: 1000 ether // Large transfer threshold
});
```
# Response Configuration
```bash
AutoHaltTrapConfig config = new AutoHaltTrapConfig({
    _trapContract: address(trap),
    _targetContract: targetContract,
    _autoPauseEnabled: true,          // Enable auto-pause
    _requireManualUnpause: true,      // Require manual unpause
    _cooldownPeriod: 300             // 5-minute cooldown
});
```

# 🧪 Testing

**Run the comprehensive test suite:**

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/AutoHaltTrap.t.sol

# Run with gas reporting
forge test --gas-report

# Run with coverage
forge coverage
```
