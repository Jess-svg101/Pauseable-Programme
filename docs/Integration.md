# Drosera Integration Guide

This guide provides detailed instructions for integrating the Auto-Halt Unusual Activity Trap with the Drosera Protocol.

# 🔄 Integration Overview

The Auto-Halt trap integrates with Drosera through a two-contract system:

__AutoHaltTrap:__ Implements detection logic and data collection

__AutoHaltTrapConfig:__ Handles response execution and configuration

# 📋 Prerequisites

__Required Components__

. Deployed AutoHaltTrap contract

. Deployed AutoHaltTrapConfig contract

. Target contract implementing IPausable interface

. Drosera CLI installed and configured

. Valid Drosera operator account

__Target Contract Requirements__

Your target contract must implement the ```IPausable``` interface:
```bash
interface IPausable {
    function pause() external;
    function unpause() external; 
    function isPaused() external view returns (bool);
}
```

__Example Implementation__
```bash
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyProtocol is Pausable, Ownable {
    // Grant pause permission to AutoHaltTrapConfig
    function grantPauseRole(address trapConfig) external onlyOwner {
        // Implementation depends on your access control system
        _grantRole(PAUSER_ROLE, trapConfig);
    }
    
    function pause() external override {
        require(hasRole(PAUSER_ROLE, msg.sender), "Unauthorized");
        _pause();
    }
    
    function unpause() external override {
        require(hasRole(PAUSER_ROLE, msg.sender), "Unauthorized");
        _unpause();
    }
}
```
# 🚀 Step-by-Step Integration

__Step 1: Install Drosera CLI__
```bash
# Install Drosera CLI
npm install -g @drosera-network/cli

# Verify installation
drosera --version

# Login to Drosera (required for trap registration)
drosera login
```

__Step 2:Deploy Trap Contracts__
```bash
# Set up environment
cp .env.example .env
# Edit .env with your configuration

# Deploy contracts
forge script script/Deploy.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

__Record the deployment addresses from the output:__
```bash
AutoHaltTrap deployed at: 0x1234...
AutoHaltTrapConfig deployed at: 0x5678...
```

__Step 3: Verify Contract Integration__
```bash
# Test trap data collection
cast call TRAP_ADDRESS "collect()(bytes)" --rpc-url $RPC_URL

# Verify event filters
cast call TRAP_ADDRESS "eventLogFilters()" --rpc-url $RPC_URL

# Check target contract connection
cast call TRAP_ADDRESS "getThresholds()" --rpc-url $RPC_URL

# Verify response config
cast call CONFIG_ADDRESS "canRespond()(bool)" --rpc-url $RPC_URL
```

__Step 4: Register Trap with Drosera__
```bash
# Register the trap
drosera create-trap \
    --name "Auto-Halt Unusual Activity Trap" \
    --description "Detects treasury drains, supply manipulation, and governance attacks" \
    --trap-address TRAP_ADDRESS \
    --config-address CONFIG_ADDRESS \
    --response-function "respondToIncident(string,bytes)" \
    --network testnet \
    --tags "defi,security,auto-halt"

# Save the returned TRAP_ID
export TRAP_ID=<returned_trap_id>
```
__Step 5: Configure Response Parameters__
```bash
# Set response configuration (if needed)
cast send CONFIG_ADDRESS \
    "updateResponseConfig(bool,bool,uint256)" \
    true \
    true \
    300 \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL

# Add additional authorized responders
cast send CONFIG_ADDRESS \
    "addAuthorizedResponder(address)" \
    RESPONDER_ADDRESS \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL
```

__Step 6: Start Monitoring__
```bash
# Start Drosera monitoring
drosera start-monitoring --trap-id $TRAP_ID

# Verify monitoring status
drosera status --trap-id $TRAP_ID

# View real-time logs
drosera logs --trap-id $TRAP_ID --follow
```

# 🔧 Configuration Management

__Drosera CLI Configuration__

Create a ```drosera.config.json``` file:
```bash
{
  "traps": [
    {
      "id": "auto-halt-unusual-activity",
      "name": "Auto-Halt Unusual Activity Trap",
      "trapAddress": "0x...",
      "configAddress": "0x...",
      "targetContract": "0x...",
      "network": "mainnet",
      "responseFunction": "respondToIncident(string,bytes)",
      "monitoringEnabled": true,
      "alerting": {
        "webhook": "https://hooks.slack.com/...",
        "email": "security@yourprotocol.com",
        "severity": "critical"
      }
    }
  ]
}
```
__Environment Variables for Automation__
```bash
# Drosera configuration
export DROSERA_API_KEY=your_api_key
export TRAP_ID=your_trap_id
export WEBHOOK_URL=your_slack_webhook

# Contract addresses
export TRAP_ADDRESS=0x...
export CONFIG_ADDRESS=0x...
export TARGET_CONTRACT=0x...

# Network configuration
export RPC_URL=https://...
export CHAIN_ID=1
```

# 📊 Monitoring and Alerts

__Real-Time Monitoring__
```bash
# Monitor trap status
drosera status --trap-id $TRAP_ID

# View recent incidents
drosera incidents --trap-id $TRAP_ID --limit 10

# Check trap performance metrics
drosera metrics --trap-id $TRAP_ID --period 24h
```

__Alert Configuration__

__Webhook Integration__
```bash
# Configure Slack webhook
drosera configure-alerts \
    --trap-id $TRAP_ID \
    --webhook $WEBHOOK_URL \
    --events "incident,pause,unpause"

# Test webhook
drosera test-webhook --trap-id $TRAP_ID
```

__Email Notifications__
```bash
# Configure email alerts
drosera configure-alerts \
    --trap-id $TRAP_ID \
    --email "security@yourprotocol.com" \
    --severity "critical,high"
```

__# Configure email alerts__
```bash
drosera configure-alerts \
    --trap-id $TRAP_ID \
    --email "security@yourprotocol.com" \
    --severity "critical,high"
```

__Custom Monitoring Script__

```bash
// monitoring.js - Custom monitoring script
const { DroseraClient } = require('@drosera-network/client');

const client = new DroseraClient({
    apiKey: process.env.DROSERA_API_KEY,
    network: 'mainnet'
});

async function monitorTrap() {
    const status = await client.getTrapStatus(process.env.TRAP_ID);
    
    if (status.incidents.length > 0) {
        console.log(`🚨 ${status.incidents.length} incidents detected`);
        
        for (const incident of status.incidents) {
            console.log(`- ${incident.type}: ${incident.description}`);
            
            // Custom alert logic
            await sendCustomAlert(incident);
        }
    }
    
    console.log(`✅ Trap monitoring active - Last check: ${new Date()}`);
}

// Run every 30 seconds
setInterval(monitorTrap, 30000);
```

# 🔄 Operational Procedures

__Incident Response Workflow__

__1. Automated Detection__
```bash
graph TD
    A[Unusual Activity] --> B[Trap Detects Pattern]
    B --> C[shouldRespond Returns True]
    C --> D[Drosera Calls respondToIncident]
    D --> E[Target Contract Paused]
    E --> F[Alerts Sent to Team]
```

__2. Manual Assessment__
```bash
# Check incident details
drosera incident --incident-id $INCIDENT_ID

# Review trap data
cast call TRAP_ADDRESS "collect()(bytes)" --rpc-url $RPC_URL

# Analyze recent transactions
cast logs \
    --address $TARGET_CONTRACT \
    --from-block $(cast block-number --rpc-url $RPC_URL | awk '{print $1-100}') \
    --rpc-url $RPC_URL
```

__3. Recovery Procedures__
```bash
# If false positive - unpause immediately
cast send CONFIG_ADDRESS \
    "manualUnpause()" \
    --private-key $AUTHORIZED_RESPONDER_KEY \
    --rpc-url $RPC_URL

# If legitimate incident - investigate further
# Update thresholds if needed
cast send TRAP_ADDRESS \
    "updateThresholds(...)" \
    --private-key $OWNER_KEY \
    --rpc-url $RPC_URL
```

__Maintenance Tasks__

__Regular Health Checks__
```bash
#!/bin/bash
# health-check.sh

echo "🔍 Checking trap health..."

# Verify trap is active
STATUS=$(drosera status --trap-id $TRAP_ID --json | jq -r '.status')
if [ "$STATUS" != "active" ]; then
    echo "❌ Trap not active: $STATUS"
    exit 1
fi

# Check recent data collection
LAST_COLLECT=$(cast call $TRAP_ADDRESS "collect()(bytes)" --rpc-url $RPC_URL)
if [ ${#LAST_COLLECT} -lt 10 ]; then
    echo "❌ Data collection failed"
    exit 1
fi

# Verify target contract accessibility
PAUSED=$(cast call $TARGET_CONTRACT "isPaused()(bool)" --rpc-url $RPC_URL)
echo "✅ Target contract accessible, paused: $PAUSED"

echo "✅ All health checks passed"
```

__Threshold Optimization__
```bash
# Analyze false positive rate
drosera analytics --trap-id $TRAP_ID --metric false-positive-rate --period 7d

# Review detection accuracy
drosera analytics --trap-id $TRAP_ID --metric detection-accuracy --period 30d

# Update thresholds based on data
# (Requires careful analysis and testing)
```

# 🔧 Troubleshooting

__Common Issues__

__1. Trap Not Responding__
```bash
# Check trap registration
drosera list-traps | grep $TRAP_ID

# Verify contract deployment
cast code $TRAP_ADDRESS --rpc-url $RPC_URL

# Test shouldRespond function
cast call $TRAP_ADDRESS "shouldRespond(bytes[])" "[\"0x...\"]" --rpc-url $RPC_URL
```
__2. Response Function Failing__
```bash
# Check authorized responders
cast call $CONFIG_ADDRESS "getAuthorizedResponders()(address[])" --rpc-url $RPC_URL

# Verify target contract permissions
cast call $TARGET_CONTRACT "hasRole(bytes32,address)" \
    $(cast keccak "PAUSER_ROLE") \
    $CONFIG_ADDRESS \
    --rpc-url $RPC_URL

# Test manual pause
cast send $CONFIG_ADDRESS \
    "emergencyPause(string)" \
    "Test pause" \
    --private-key $RESPONDER_KEY \
    --rpc-url $RPC_URL
```
__3. High False Positive Rate__
```bash
# Review detection thresholds
cast call $TRAP_ADDRESS "getThresholds()" --rpc-url $RPC_URL

# Analyze recent activity patterns
drosera analytics --trap-id $TRAP_ID --metric activity-patterns --period 7d

# Adjust thresholds (test on fork first)
forge script script/UpdateThresholds.s.sol \
    --fork-url $RPC_URL \
    --sender $OWNER_ADDRESS
```
# 📈 Performance Optimization

__Gas Optimization__
```bash
# Monitor gas usage
forge test --gas-report | grep -E "(collect|shouldRespond|respondToIncident)"

# Optimize event log processing
# (Consider batching or filtering strategies)
```
__Response Time Optimization__
```bash
# Measure response times
drosera metrics --trap-id $TRAP_ID --metric response-time --period 24h

# Optimize threshold calculations
# (Pre-compute values where possible)
```
# 🔐 Security Best Practices

__Access Control__

. Use multi-signature wallets for owner functions

. Rotate authorized responder keys regularly

__Monitoring__

. Set up redundant monitoring systems

. Implement circuit breakers for automated responses

__Testing__

. Continuous integration with trap simulations

. Regular fire drills with manual procedures

# Support Resources

Drosera Documentation: https://docs.drosera.io

Discord Support: https://discord.gg/drosera

GitHub Issues: https://github.com/drosera-network/examples/issues

Emergency Contact: security@drosera.io
