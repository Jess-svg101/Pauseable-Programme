// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AutoHaltTrap
 * @notice Drosera-compliant trap that detects unusual activity patterns
 * @dev Stateless implementation - all configuration encoded in collect() data
 * 
 * KEY DROSERA CONSTRAINTS:
 * - No constructor arguments (deployed fresh each block)
 * - No persistent state (resets every block)
 * - collect() must be pure/view only
 * - shouldRespond() must be pure (no state reads)
 * - data[0] = current block, data[n-1] = oldest block
 */
contract AutoHaltTrap {
    
    /**
     * @dev Activity data structure for a single block
     * All metrics must be computed off-chain and passed in
     */
    struct ActivityData {
        uint256 blockNumber;
        uint256 timestamp;
        uint256 treasuryBalance;      // Current treasury balance
        uint256 totalSupply;          // Current token supply
        uint256 largeTransferCount;   // Count of transfers > threshold
        uint256 mintEventCount;       // Count of mint events
        uint256 withdrawalEventCount; // Count of withdrawal events
        uint256 proposalCount;        // Count of governance proposals
        address lastSignificantActor; // Last actor in large transaction
    }
    
    /**
     * @dev Configuration structure embedded in collect() output
     * Allows operator to configure thresholds without state
     */
    struct TrapConfig {
        uint256 maxTreasuryDrainBps;      // Max drain in basis points (e.g., 3000 = 30%)
        uint256 maxSupplyIncreaseBps;     // Max supply increase BPS (e.g., 5000 = 50%)
        uint256 maxProposalsPerWindow;    // Max proposals in analysis window
        uint256 maxLargeTransfersPerBlock; // Max large transfers per block
        uint256 rapidActionThreshold;     // Blocks to consider "rapid"
        uint256 analysisWindowSize;       // Number of blocks to analyze
    }

    /**
     * @notice Collects activity data for current block
     * @dev Called by Drosera operator every block
     * @return Encoded ActivityData and TrapConfig
     * 
     * IMPLEMENTATION NOTE:
     * In production, this would read on-chain state or accept operator-computed metrics.
     * For demo purposes, returns empty data. Operator must populate this via off-chain computation.
     */
    function collect() external view returns (bytes memory) {
        // Default configuration (operators can override by encoding custom values)
        TrapConfig memory config = TrapConfig({
            maxTreasuryDrainBps: 3000,        // 30%
            maxSupplyIncreaseBps: 5000,       // 50%
            maxProposalsPerWindow: 10,        // 10 proposals
            maxLargeTransfersPerBlock: 5,     // 5 large transfers
            rapidActionThreshold: 3,          // 3 blocks
            analysisWindowSize: 10            // 10 blocks
        });
        
        // Activity data for current block (would be computed off-chain in production)
        ActivityData memory data = ActivityData({
            blockNumber: block.number,
            timestamp: block.timestamp,
            treasuryBalance: 0,               // Operator computes from events/state
            totalSupply: 0,                   // Operator computes from events/state
            largeTransferCount: 0,            // Operator counts from logs
            mintEventCount: 0,                // Operator counts from logs
            withdrawalEventCount: 0,          // Operator counts from logs
            proposalCount: 0,                 // Operator counts from logs
            lastSignificantActor: address(0)  // Operator extracts from logs
        });
        
        // Encode both config and data so shouldRespond can be pure
        return abi.encode(config, data);
    }

    /**
     * @notice Analyzes historical data to detect incidents
     * @dev PURE function - no state reads allowed
     * @param dataPoints Array where data[0] = current block, data[n-1] = oldest
     * @return incident True if unusual activity detected
     * @return responseData Encoded incident details
     */
    function shouldRespond(
        bytes[] calldata dataPoints
    ) external pure returns (bool incident, bytes memory responseData) {
        
        // Need at least 2 data points for comparison
        if (dataPoints.length < 2) {
            return (false, "");
        }
        
        // Decode current and previous block data
        // NOTE: data[0] = current, data[1] = previous (Drosera convention)
        (TrapConfig memory config, ActivityData memory current) = abi.decode(
            dataPoints[0], 
            (TrapConfig, ActivityData)
        );
        
        (, ActivityData memory previous) = abi.decode(
            dataPoints[1], 
            (TrapConfig, ActivityData)
        );
        
        // 1. Check for treasury drain
        if (_detectTreasuryDrain(current, previous, config)) {
            uint256 drainAmount = previous.treasuryBalance - current.treasuryBalance;
            uint256 drainBps = (drainAmount * 10000) / previous.treasuryBalance;
            
            return (
                true, 
                abi.encode(
                    "TREASURY_DRAIN",
                    current.blockNumber,
                    drainBps,
                    drainAmount
                )
            );
        }
        
        // 2. Check for supply manipulation
        if (_detectSupplyManipulation(current, previous, config)) {
            uint256 increaseAmount = current.totalSupply - previous.totalSupply;
            uint256 increaseBps = (increaseAmount * 10000) / previous.totalSupply;
            
            return (
                true,
                abi.encode(
                    "SUPPLY_MANIPULATION", 
                    current.blockNumber,
                    increaseBps,
                    increaseAmount
                )
            );
        }
        
        // 3. Check for governance flooding (requires full window)
        if (dataPoints.length >= config.analysisWindowSize) {
            if (_detectGovernanceFlooding(dataPoints, config)) {
                uint256 totalProposals = _countTotalProposals(dataPoints, config);
                
                return (
                    true,
                    abi.encode(
                        "GOVERNANCE_FLOODING",
                        current.blockNumber,
                        totalProposals,
                        config.maxProposalsPerWindow
                    )
                );
            }
        }
        
        // 4. Check for rapid suspicious activity
        if (dataPoints.length >= config.rapidActionThreshold) {
            if (_detectRapidActivity(dataPoints, config)) {
                return (
                    true,
                    abi.encode(
                        "RAPID_ACTIVITY",
                        current.blockNumber,
                        current.lastSignificantActor,
                        config.rapidActionThreshold
                    )
                );
            }
        }
        
        // No incident detected
        return (false, "");
    }
    
    // ============ PURE DETECTION FUNCTIONS ============
    
    /**
     * @dev Detects treasury drain exceeding threshold
     * @param current Current block data
     * @param previous Previous block data
     * @param config Trap configuration
     * @return True if drain exceeds threshold
     */
    function _detectTreasuryDrain(
        ActivityData memory current,
        ActivityData memory previous,
        TrapConfig memory config
    ) internal pure returns (bool) {
        
        // Skip if no previous balance
        if (previous.treasuryBalance == 0) {
            return false;
        }
        
        // Skip if balance increased
        if (current.treasuryBalance >= previous.treasuryBalance) {
            return false;
        }
        
        // Calculate drain percentage in basis points
        uint256 drainAmount = previous.treasuryBalance - current.treasuryBalance;
        uint256 drainBps = (drainAmount * 10000) / previous.treasuryBalance;
        
        // Check against threshold
        return drainBps > config.maxTreasuryDrainBps;
    }
    
    /**
     * @dev Detects token supply manipulation
     * @param current Current block data
     * @param previous Previous block data
     * @param config Trap configuration
     * @return True if supply increase exceeds threshold
     */
    function _detectSupplyManipulation(
        ActivityData memory current,
        ActivityData memory previous,
        TrapConfig memory config
    ) internal pure returns (bool) {
        
        // Skip if no previous supply
        if (previous.totalSupply == 0) {
            return false;
        }
        
        // Skip if supply decreased
        if (current.totalSupply <= previous.totalSupply) {
            return false;
        }
        
        // Calculate supply increase in basis points
        uint256 increaseAmount = current.totalSupply - previous.totalSupply;
        uint256 increaseBps = (increaseAmount * 10000) / previous.totalSupply;
        
        // Check against threshold
        return increaseBps > config.maxSupplyIncreaseBps;
    }
    
    /**
     * @dev Detects governance proposal flooding
     * @param dataPoints Historical data array
     * @param config Trap configuration
     * @return True if proposal count exceeds threshold
     */
    function _detectGovernanceFlooding(
        bytes[] calldata dataPoints,
        TrapConfig memory config
    ) internal pure returns (bool) {
        
        uint256 totalProposals = _countTotalProposals(dataPoints, config);
        
        return totalProposals > config.maxProposalsPerWindow;
    }
    
    /**
     * @dev Counts total proposals in analysis window
     * @param dataPoints Historical data array
     * @param config Trap configuration
     * @return Total proposal count
     */
    function _countTotalProposals(
        bytes[] calldata dataPoints,
        TrapConfig memory config
    ) internal pure returns (uint256) {
        
        uint256 totalProposals = 0;
        uint256 blocksToCheck = config.analysisWindowSize;
        
        if (dataPoints.length < blocksToCheck) {
            blocksToCheck = dataPoints.length;
        }
        
        for (uint256 i = 0; i < blocksToCheck; i++) {
            (, ActivityData memory data) = abi.decode(
                dataPoints[i],
                (TrapConfig, ActivityData)
            );
            totalProposals += data.proposalCount;
        }
        
        return totalProposals;
    }
    
    /**
     * @dev Detects rapid suspicious activity patterns
     * @param dataPoints Historical data array
     * @param config Trap configuration
     * @return True if rapid activity detected
     */
    function _detectRapidActivity(
        bytes[] calldata dataPoints,
        TrapConfig memory config
    ) internal pure returns (bool) {
        
        uint256 blocksToCheck = config.rapidActionThreshold;
        if (dataPoints.length < blocksToCheck) {
            blocksToCheck = dataPoints.length;
        }
        
        // Check for same actor in consecutive blocks
        address lastActor = address(0);
        uint256 consecutiveActions = 0;
        
        for (uint256 i = 0; i < blocksToCheck; i++) {
            (, ActivityData memory data) = abi.decode(
                dataPoints[i],
                (TrapConfig, ActivityData)
            );
            
            // Check for same actor
            if (data.lastSignificantActor != address(0) && 
                data.lastSignificantActor == lastActor) {
                consecutiveActions++;
            }
            
            // Check for excessive large transfers
            if (data.largeTransferCount > config.maxLargeTransfersPerBlock) {
                return true;
            }
            
            lastActor = data.lastSignificantActor;
        }
        
        // Trigger if same actor in 2+ consecutive blocks
        return consecutiveActions >= 2;
    }
}

/**
 * @notice ITrap interface for reference
 * @dev This is the actual Drosera interface your trap must implement
 */
interface ITrap {
    function collect() external view returns (bytes memory);
    function shouldRespond(bytes[] calldata) external pure returns (bool, bytes memory);
}
