// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


interface IPausable {
    function pause() external;
    function unpause() external;
    function isPaused() external view returns (bool);
}

contract AutoHaltTrap is Trap {
    // Activity monitoring data structure
    struct ActivityData {
        uint256 timestamp;
        uint256 treasuryBalance;
        uint256 totalSupply;
        uint256 governanceProposalCount;
        uint256 largeTransferCount;
        uint256 mintingEvents;
        uint256 drainEvents;
        address lastActor;
        bool emergencyState;
    }

    // Threshold configuration
    struct ThresholdConfig {
        uint256 maxTreasuryDrainPercent;      // Max % drain allowed (e.g., 30 = 30%)
        uint256 maxSupplyIncreasePercent;     // Max % supply increase (e.g., 50 = 50%)
        uint256 maxGovernanceProposalsPerBlock; // Max proposals per analysis window
        uint256 maxLargeTransfersPerBlock;    // Max large transfers per block
        uint256 rapidActionThreshold;         // Blocks between actions to consider "rapid"
        uint256 analysisWindow;               // Number of blocks to analyze
        address targetContract;               // Contract to monitor
        uint256 largeTransferThreshold;       // Minimum amount to consider "large"
    }

    ThresholdConfig public thresholds;
    
    // Events
    event IncidentDetected(string incidentType, uint256 severity, bytes32 dataHash);
    event ThresholdBreached(string metric, uint256 actual, uint256 threshold);

    constructor(
        address _targetContract,
        uint256 _maxTreasuryDrainPercent,
        uint256 _maxSupplyIncreasePercent,
        uint256 _maxGovernanceProposalsPerBlock,
        uint256 _maxLargeTransfersPerBlock,
        uint256 _rapidActionThreshold,
        uint256 _analysisWindow,
        uint256 _largeTransferThreshold
    ) {
        thresholds = ThresholdConfig({
            targetContract: _targetContract,
            maxTreasuryDrainPercent: _maxTreasuryDrainPercent,
            maxSupplyIncreasePercent: _maxSupplyIncreasePercent,
            maxGovernanceProposalsPerBlock: _maxGovernanceProposalsPerBlock,
            maxLargeTransfersPerBlock: _maxLargeTransfersPerBlock,
            rapidActionThreshold: _rapidActionThreshold,
            analysisWindow: _analysisWindow,
            largeTransferThreshold: _largeTransferThreshold
        });
    }

    /**
     * @dev Collects current activity data for the target contract
     * This function is called every block by Drosera operators
     */
    function collect() external view override returns (bytes memory) {
        ActivityData memory data = ActivityData({
            timestamp: block.timestamp,
            treasuryBalance: _getTreasuryBalance(),
            totalSupply: _getTotalSupply(),
            governanceProposalCount: _getGovernanceProposalCount(),
            largeTransferCount: _getLargeTransferCount(),
            mintingEvents: _getMintingEvents(),
            drainEvents: _getDrainEvents(),
            lastActor: _getLastSignificantActor(),
            emergencyState: _checkEmergencyState()
        });

        return abi.encode(data);
    }

    /**
     * @dev Analyzes historical data to determine if an incident occurred
     * @param data Array of encoded ActivityData from previous blocks
     * @return incident True if incident detected
     * @return responseData Encoded data for the response function
     */
    function shouldRespond(
        bytes[] calldata data
    ) external pure override returns (bool incident, bytes memory responseData) {
        if (data.length < 2) {
            // Need at least 2 data points for comparison
            return (false, "");
        }

        // Decode the latest data points
        ActivityData memory current = abi.decode(data[data.length - 1], (ActivityData));
        ActivityData memory previous = abi.decode(data[data.length - 2], (ActivityData));

        // Check for immediate emergency state
        if (current.emergencyState) {
            return (true, abi.encode("Emergency state detected", current.timestamp));
        }

        // Analyze treasury drain
        if (_detectTreasuryDrain(current, previous)) {
            return (true, abi.encode("Excessive treasury drain", current.timestamp));
        }

        // Analyze token supply manipulation
        if (_detectSupplyManipulation(current, previous)) {
            return (true, abi.encode("Token supply manipulation", current.timestamp));
        }

        // Analyze governance flooding
        if (_detectGovernanceFlooding(data)) {
            return (true, abi.encode("Governance flooding attack", current.timestamp));
        }

        // Analyze rapid suspicious activity
        if (_detectRapidActivity(data)) {
            return (true, abi.encode("Rapid suspicious activity", current.timestamp));
        }

        // Analyze pattern-based attacks
        if (_detectSuspiciousPatterns(data)) {
            return (true, abi.encode("Suspicious activity pattern", current.timestamp));
        }

        return (false, "");
    }

    /**
     * @dev Specifies which events to monitor
     */
    function eventLogFilters() public view override returns (EventFilter[] memory) {
        EventFilter[] memory filters = new EventFilter[](5);
        
        // Monitor ERC20 Transfer events
        filters[0] = EventFilter({
            contractAddress: thresholds.targetContract,
            signature: "Transfer(address,address,uint256)"
        });
        
        // Monitor Mint events
        filters[1] = EventFilter({
            contractAddress: thresholds.targetContract,
            signature: "Mint(address,uint256)"
        });
        
        // Monitor Governance events
        filters[2] = EventFilter({
            contractAddress: thresholds.targetContract,
            signature: "ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)"
        });
        
        // Monitor Withdrawal events
        filters[3] = EventFilter({
            contractAddress: thresholds.targetContract,
            signature: "Withdrawal(address,uint256)"
        });

        // Monitor Pause events
        filters[4] = EventFilter({
            contractAddress: thresholds.targetContract,
            signature: "Paused(address)"
        });
        
        return filters;
    }

    // ============ INTERNAL ANALYSIS FUNCTIONS ============

    function _detectTreasuryDrain(
        ActivityData memory current, 
        ActivityData memory previous
    ) internal view returns (bool) {
        if (previous.treasuryBalance == 0) return false;
        
        uint256 balanceChange = previous.treasuryBalance - current.treasuryBalance;
        uint256 percentageChange = (balanceChange * 100) / previous.treasuryBalance;
        
        return percentageChange > thresholds.maxTreasuryDrainPercent;
    }

    function _detectSupplyManipulation(
        ActivityData memory current, 
        ActivityData memory previous
    ) internal view returns (bool) {
        if (previous.totalSupply == 0) return false;
        
        if (current.totalSupply > previous.totalSupply) {
            uint256 supplyIncrease = current.totalSupply - previous.totalSupply;
            uint256 percentageIncrease = (supplyIncrease * 100) / previous.totalSupply;
            
            return percentageIncrease > thresholds.maxSupplyIncreasePercent;
        }
        
        return false;
    }

    function _detectGovernanceFlooding(bytes[] calldata data) internal view returns (bool) {
        if (data.length < thresholds.analysisWindow) return false;
        
        uint256 recentProposals = 0;
        uint256 startIndex = data.length > thresholds.analysisWindow ? 
            data.length - thresholds.analysisWindow : 0;
        
        for (uint256 i = startIndex; i < data.length; i++) {
            ActivityData memory blockData = abi.decode(data[i], (ActivityData));
            recentProposals += blockData.governanceProposalCount;
        }
        
        return recentProposals > thresholds.maxGovernanceProposalsPerBlock * thresholds.analysisWindow;
    }

    function _detectRapidActivity(bytes[] calldata data) internal view returns (bool) {
        if (data.length < 3) return false;
        
        uint256 rapidActions = 0;
        address lastActor = address(0);
        
        for (uint256 i = data.length - thresholds.rapidActionThreshold; i < data.length; i++) {
            ActivityData memory blockData = abi.decode(data[i], (ActivityData));
            
            if (blockData.lastActor == lastActor && lastActor != address(0)) {
                rapidActions++;
            }
            
            if (blockData.largeTransferCount > thresholds.maxLargeTransfersPerBlock) {
                rapidActions++;
            }
            
            lastActor = blockData.lastActor;
        }
        
        return rapidActions >= thresholds.rapidActionThreshold;
    }

    function _detectSuspiciousPatterns(bytes[] calldata data) internal pure returns (bool) {
        if (data.length < 5) return false;
        
        // Look for alternating high-activity patterns (potential coordinated attack)
        uint256 highActivityBlocks = 0;
        
        for (uint256 i = data.length - 5; i < data.length; i++) {
            ActivityData memory blockData = abi.decode(data[i], (ActivityData));
            
            if (blockData.largeTransferCount > 0 || 
                blockData.mintingEvents > 0 || 
                blockData.drainEvents > 2) {
                highActivityBlocks++;
            }
        }
        
        return highActivityBlocks >= 3; // 3 out of 5 blocks showing high activity
    }

    // ============ DATA COLLECTION HELPERS ============

    function _getTreasuryBalance() internal view returns (uint256) {
        // Implementation depends on your specific treasury contract
        // This is a placeholder - replace with actual treasury balance logic
        if (thresholds.targetContract != address(0)) {
            try IERC20(thresholds.targetContract).balanceOf(thresholds.targetContract) returns (uint256 balance) {
                return balance;
            } catch {
                return 0;
            }
        }
        return 0;
    }

    function _getTotalSupply() internal view returns (uint256) {
        if (thresholds.targetContract != address(0)) {
            try IERC20(thresholds.targetContract).totalSupply() returns (uint256 supply) {
                return supply;
            } catch {
                return 0;
            }
        }
        return 0;
    }

    function _getGovernanceProposalCount() internal view returns (uint256) {
        // Count recent governance events from stored event logs
        EventLog[] memory logs = getEventLogs();
        uint256 count = 0;
        
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && 
                logs[i].topics[0] == keccak256("ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)")) {
                count++;
            }
        }
        
        return count;
    }

    function _getLargeTransferCount() internal view returns (uint256) {
        EventLog[] memory logs = getEventLogs();
        uint256 count = 0;
        
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && 
                logs[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                
                if (logs[i].data.length >= 32) {
                    uint256 amount = abi.decode(logs[i].data, (uint256));
                    if (amount >= thresholds.largeTransferThreshold) {
                        count++;
                    }
                }
            }
        }
        
        return count;
    }

    function _getMintingEvents() internal view returns (uint256) {
        EventLog[] memory logs = getEventLogs();
        uint256 count = 0;
        
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && 
                logs[i].topics[0] == keccak256("Mint(address,uint256)")) {
                count++;
            }
        }
        
        return count;
    }

    function _getDrainEvents() internal view returns (uint256) {
        EventLog[] memory logs = getEventLogs();
        uint256 count = 0;
        
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && 
                logs[i].topics[0] == keccak256("Withdrawal(address,uint256)")) {
                count++;
            }
        }
        
        return count;
    }

    function _getLastSignificantActor() internal view returns (address) {
        EventLog[] memory logs = getEventLogs();
        
        for (uint256 i = logs.length; i > 0; i--) {
            if (logs[i-1].topics.length > 1) {
                return address(uint160(uint256(logs[i-1].topics[1])));
            }
        }
        
        return address(0);
    }

    function _checkEmergencyState() internal view returns (bool) {
        // Check if target contract is already paused or in emergency state
        if (thresholds.targetContract != address(0)) {
            try IPausable(thresholds.targetContract).isPaused() returns (bool paused) {
                return paused;
            } catch {
                return false;
            }
        }
        return false;
    }

    // ============ CONFIGURATION FUNCTIONS ============

    function updateThresholds(
        uint256 _maxTreasuryDrainPercent,
        uint256 _maxSupplyIncreasePercent,
        uint256 _maxGovernanceProposalsPerBlock,
        uint256 _maxLargeTransfersPerBlock,
        uint256 _rapidActionThreshold,
        uint256 _analysisWindow,
        uint256 _largeTransferThreshold
    ) external {
        thresholds.maxTreasuryDrainPercent = _maxTreasuryDrainPercent;
        thresholds.maxSupplyIncreasePercent = _maxSupplyIncreasePercent;
        thresholds.maxGovernanceProposalsPerBlock = _maxGovernanceProposalsPerBlock;
        thresholds.maxLargeTransfersPerBlock = _maxLargeTransfersPerBlock;
        thresholds.rapidActionThreshold = _rapidActionThreshold;
        thresholds.analysisWindow = _analysisWindow;
        thresholds.largeTransferThreshold = _largeTransferThreshold;
    }

    function getThresholds() external view returns (ThresholdConfig memory) {
        return thresholds;
    }
}

// Required interface for ERC20 interactions
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}
