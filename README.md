# Auto-Halt Unusual Activity Trap
A comprehensive Drosera trap system that automatically detects and halts unusual activities in DeFi protocols, including treasury drains, excessive minting, and governance attacks.

# 🛡️ Overview

This trap monitors blockchain activity in real-time and automatically pauses target contracts when unusual patterns are detected, providing protection against:

. Treasury Drains: Rapid or large-scale asset withdrawals

. Token Supply Manipulation: Excessive minting or burning events

. Governance Flooding: Spam proposal attacks

. Rapid Activity Patterns: Coordinated multi-transaction exploits

# 🏗️ How It Works

The trap follows the standard Drosera architecture:

. Data Collection (collect()): Gathers activity metrics every block

. Pattern Analysis (shouldRespond()): Analyzes historical data using time-series analysis

. Incident Detection: Detects anomalies across configurable time windows

. Automated Response: Triggers pause functionality via response contract

# 🔍 Detection Methods
**Treasury Drain Detection**
```bash
// Detects >30% treasury balance decrease in single block
if (percentageChange > thresholds.maxTreasuryDrainPercent) {
    return (true, abi.encode("Excessive treasury drain", timestamp));
}
```
**Supply Manipulation Detection**
```bash
// Detects >50% token supply increase (inflation attacks)  
if (percentageIncrease > thresholds.maxSupplyIncreasePercent) {
    return (true, abi.encode("Token supply manipulation", timestamp));
}
```
**Rapid Activity Detection**
```bash
// Identifies burst patterns typical of exploits
if (rapidActions >= thresholds.rapidActionThreshold) {
    return (true, abi.encode("Rapid suspicious activity", timestamp));
}
```

# ⚙️ Configuration
**Trap Parameters**
```bash
AutoHaltTrap trap = new AutoHaltTrap({
    _targetContract: 0x...,                // Contract to protect
    _maxTreasuryDrainPercent: 30,          // 30% max drain per block
    _maxSupplyIncreasePercent: 50,         // 50% max supply increase
    _maxGovernanceProposalsPerBlock: 3,    // Max proposals per block
    _maxLargeTransfersPerBlock: 5,         // Max large transfers
    _rapidActionThreshold: 3,              // Rapid action detection
    _analysisWindow: 10,                   // Analysis window in blocks
    _largeTransferThreshold: 1000 ether    // Large transfer threshold
});
```
**Response Configuration**
```bash
AutoHaltTrapConfig config = new AutoHaltTrapConfig({
    _trapContract: address(trap),
    _targetContract: targetContract,
    _autoPauseEnabled: true,               // Enable auto-pause
    _requireManualUnpause: true,           // Require manual unpause
    _cooldownPeriod: 300                   // 5-minute cooldown
});
```

# 🚀 Quick Start

__Step-by-step deployment process__

__Drosera CLI integration commands__

__Testing instructions__

**1.Deploy Contracts**
```bash
# Set environment variables
cp .env.example .env
# Edit .env with your values

# Deploy the trap system
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

**2.Register with Drosera**
```bash
# Install Drosera CLI
npm install -g @drosera-network/cli

# Register trap
drosera create-trap \
  --name "Auto-Halt Unusual Activity Trap" \
  --trap-address <TRAP_ADDRESS> \
  --config-address <CONFIG_ADDRESS> \
  --response-function "respondToIncident(string,bytes)"
```

**3.Start Monitoring**
```bash
drosera start-monitoring --trap-id <TRAP_ID>
```

# 🧪 Testing
```bash
# Install dependencies
forge install

# Run all tests
forge test

# Run with detailed output
forge test -vvv

# Test specific scenarios
forge test --match-test testTreasuryDrainDetection
forge test --match-test testGovernanceFloodingDetection

# Generate gas report
forge test --gas-report
```

**Test Coverage**
. ✅ Normal activity detection (should not trigger)

. ✅ Treasury drain detection (30%+ decrease)

. ✅ Supply manipulation detection (50%+ increase)

. ✅ Governance flooding detection (>3 proposals/block)

. ✅ Rapid activity pattern detection (3+ consecutive actions)

. ✅ Incident response execution

. ✅ Manual emergency controls

. ✅ Authorization and access control

. ✅ Cooldown period enforcement

. ✅ Edge cases and error conditions


# 📊 Use Cases & Configuration Examples

**DeFi Lending Protocol**
```bash
// Conservative settings for lending protocols
AutoHaltTrap trap = new AutoHaltTrap({
    _targetContract: lendingProtocol,
    _maxTreasuryDrainPercent: 15,          // More conservative
    _maxSupplyIncreasePercent: 25,         // Prevent reward inflation
    _rapidActionThreshold: 2,              // Faster detection
    _cooldownPeriod: 180                   // 3-minute response
});
```

**Governance Token Contract**
```bash
// Governance-focused protection
AutoHaltTrap trap = new AutoHaltTrap({
    _maxGovernanceProposalsPerBlock: 1,    // Very strict
    _analysisWindow: 20,                   // Longer analysis
    _rapidActionThreshold: 1,              // Immediate detection
    _cooldownPeriod: 600                   // 10-minute cooldown
});
```

**High-Value Treasury**
```bash
// Maximum protection for large treasuries
AutoHaltTrap trap = new AutoHaltTrap({
    _maxTreasuryDrainPercent: 10,          // 10% threshold
    _largeTransferThreshold: 100 ether,    // Lower threshold
    _rapidActionThreshold: 1,              // Single action triggers
    _requireManualUnpause: true            // Always require manual review
});
```

# 🔧 Emergency Procedures
**Automated Response Flow**
**. Detection:** Trap detects unusual activity pattern

**. Validation:** Historical data analysis confirms incident

**. Response:** Automatic pause triggered via ```respondToIncident()```

**. Notification:** All authorized responders alerted

**. Assessment:** Manual review required for unpause

**Manual Controls**
```bash
// Emergency pause by authorized responder
trapConfig.emergencyPause("Suspicious activity detected");

// Manual unpause after investigation
trapConfig.manualUnpause();

// Add/remove authorized responders
trapConfig.addAuthorizedResponder(newResponder);
trapConfig.removeAuthorizedResponder(oldResponder);
```

# 📈 Monitoring & Alerts

**Key Events**
```bash
event IncidentDetected(string incidentType, uint256 severity, bytes32 dataHash);
event EmergencyPause(address indexed target, string reason, uint256 timestamp);
event ResponderAdded(address indexed responder);
```

__Integration with Monitoring Systems__

**. Discord/Slack:** Webhook notifications for incidents

**. The Graph:** Index events for dashboard visualization

**. Chainlink Automation:** Additional response triggers

**. OpenZeppelin Defender:** Backup monitoring system

# 🔒 Security Considerations

**Threshold Tuning**

**. Start Conservative:** Begin with lower thresholds, increase gradually

**. Protocol Analysis:** Study normal activity patterns before deployment

**. Regular Review:** Adjust thresholds based on false positive rates

**Access Control**

**. Multi-Sig Ownership:** Use multi-signature wallet for owner functions

**. Responder Rotation:** Regularly rotate authorized responder keys

**. Emergency Procedures:** Document clear escalation procedures

**False Positive Managements**

**. Monitoring:** Track false positive rates and adjust accordingly

**. Quick Response:** Ensure manual unpause capability is always available

**. Communication:** Maintain clear channels with protocol users

# 🏗️ Architecture Details

**Contract Interaction Flow**
```
Drosera Operators ----> AutoHaltTrap(Detection) ----> Target Contract(Pausable)

                               |                                ^
                               
                               |                                | 
                               
                               AutoHaltTrapConfig(Response) -----
```
**Data Flow**
1. Block N: Drosera operators call ```collect()``` → Returns encoded ```ActivityData```
   
2. Block N+1: Operators call ```shouldRespond(data[])``` → Analyzes historical patterns
  
3.  If Incident: Operators call ```respondToIncident()``` → Triggers pause
  
4. Manual Review: Authorized responder calls ```manualUnpause()``` → Resumes operations

   # 🙏 Acknowledgments
**[Drosera Network](https://drosera.io) for the innovative trap framework**

**[Foundry](https://github.com/foundry-rs/foundry) for excellent development tools**

**The DeFi security community for inspiration and feedback**
                       
