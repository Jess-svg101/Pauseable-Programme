// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPausable {
    function pause() external;
    function unpause() external;
    function isPaused() external view returns (bool);
}


contract AutoHaltTrapConfig {
    // The trap contract address
    address public immutable trapContract;
    
    // The target contract to pause when incidents are detected
    address public immutable targetContract;
    
    // The trap contract hash for verification
    bytes32 public immutable trapHash;
    
    // Owner who can update configurations
    address public owner;
    
    // Emergency response settings
    struct ResponseConfig {
        bool autoPauseEnabled;
        bool requireManualUnpause;
        uint256 cooldownPeriod;
        uint256 lastResponseTime;
        address[] authorizedResponders;
    }
    
    ResponseConfig public responseConfig;
    
    // Events
    event IncidentResponse(string incidentType, uint256 timestamp, bytes responseData);
    event EmergencyPause(address indexed target, string reason, uint256 timestamp);
    event ManualUnpause(address indexed target, address indexed operator, uint256 timestamp);
    event ConfigUpdated(address indexed updater, uint256 timestamp);
    event ResponderAdded(address indexed responder);
    event ResponderRemoved(address indexed responder);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyAuthorizedResponder() {
        require(_isAuthorizedResponder(msg.sender), "Not authorized responder");
        _;
    }

    modifier onlyDroseraOperator() {
        // In production, this would verify the caller is a valid Drosera operator
        // For now, we'll allow authorized responders
        require(_isAuthorizedResponder(msg.sender), "Not authorized operator");
        _;
    }

    constructor(
        address _trapContract,
        address _targetContract,
        bytes32 _trapHash,
        bool _autoPauseEnabled,
        bool _requireManualUnpause,
        uint256 _cooldownPeriod
    ) {
        trapContract = _trapContract;
        targetContract = _targetContract;
        trapHash = _trapHash;
        owner = msg.sender;
        
        responseConfig = ResponseConfig({
            autoPauseEnabled: _autoPauseEnabled,
            requireManualUnpause: _requireManualUnpause,
            cooldownPeriod: _cooldownPeriod,
            lastResponseTime: 0,
            authorizedResponders: new address[](0)
        });

        // Add deployer as initial authorized responder
        responseConfig.authorizedResponders.push(msg.sender);
    }

    /**
     * @dev Main response function called by Drosera operators when incident detected
     * This is the callback function specified in the Drosera Protocol
     */
    function respondToIncident(
        string calldata incidentType,
        bytes calldata responseData
    ) external onlyDroseraOperator {
        require(responseConfig.autoPauseEnabled, "Auto-pause disabled");
        require(
            block.timestamp >= responseConfig.lastResponseTime + responseConfig.cooldownPeriod,
            "Cooldown period active"
        );

        // Update last response time
        responseConfig.lastResponseTime = block.timestamp;

        // Execute the pause action
        _pauseTarget(incidentType, responseData);

        emit IncidentResponse(incidentType, block.timestamp, responseData);
    }

    /**
     * @dev Alternative response function for different incident severities
     */
    function respondToSevereIncident(
        string calldata incidentType,
        bytes calldata responseData
    ) external onlyDroseraOperator {
        // Severe incidents bypass cooldown period
        responseConfig.lastResponseTime = block.timestamp;
        
        _pauseTarget(incidentType, responseData);
        
        emit IncidentResponse(
            string(abi.encodePacked("SEVERE: ", incidentType)), 
            block.timestamp, 
            responseData
        );
    }

    /**
     * @dev Manual emergency pause function for authorized responders
     */
    function emergencyPause(string calldata reason) external onlyAuthorizedResponder {
        _pauseTarget("Manual Emergency", abi.encode(reason, block.timestamp));
    }

    /**
     * @dev Manual unpause function (if manual unpause is required)
     */
    function manualUnpause() external onlyAuthorizedResponder {
        require(responseConfig.requireManualUnpause, "Manual unpause not required");
        
        try IPausable(targetContract).unpause() {
            emit ManualUnpause(targetContract, msg.sender, block.timestamp);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Unpause failed: ", reason)));
        }
    }

    /**
     * @dev Internal function to pause the target contract
     */
    function _pauseTarget(string memory incidentType, bytes memory responseData) internal {
        try IPausable(targetContract).isPaused() returns (bool isPaused) {
            if (!isPaused) {
                try IPausable(targetContract).pause() {
                    emit EmergencyPause(targetContract, incidentType, block.timestamp);
                } catch Error(string memory reason) {
                    // If pause fails, emit event for monitoring
                    emit IncidentResponse(
                        string(abi.encodePacked("PAUSE_FAILED: ", incidentType, " - ", reason)),
                        block.timestamp,
                        responseData
                    );
                }
            }
        } catch {
            // Target contract doesn't implement isPaused, try to pause anyway
            try IPausable(targetContract).pause() {
                emit EmergencyPause(targetContract, incidentType, block.timestamp);
            } catch Error(string memory reason) {
                emit IncidentResponse(
                    string(abi.encodePacked("PAUSE_FAILED: ", incidentType, " - ", reason)),
                    block.timestamp,
                    responseData
                );
            }
        }
    }

    /**
     * @dev Check if address is authorized responder
     */
    function _isAuthorizedResponder(address responder) internal view returns (bool) {
        for (uint256 i = 0; i < responseConfig.authorizedResponders.length; i++) {
            if (responseConfig.authorizedResponders[i] == responder) {
                return true;
            }
        }
        return false;
    }

    // ============ CONFIGURATION FUNCTIONS ============

    function updateResponseConfig(
        bool _autoPauseEnabled,
        bool _requireManualUnpause,
        uint256 _cooldownPeriod
    ) external onlyOwner {
        responseConfig.autoPauseEnabled = _autoPauseEnabled;
        responseConfig.requireManualUnpause = _requireManualUnpause;
        responseConfig.cooldownPeriod = _cooldownPeriod;
        
        emit ConfigUpdated(msg.sender, block.timestamp);
    }

    function addAuthorizedResponder(address responder) external onlyOwner {
        require(responder != address(0), "Invalid responder address");
        require(!_isAuthorizedResponder(responder), "Already authorized");
        
        responseConfig.authorizedResponders.push(responder);
        emit ResponderAdded(responder);
    }

    function removeAuthorizedResponder(address responder) external onlyOwner {
        for (uint256 i = 0; i < responseConfig.authorizedResponders.length; i++) {
            if (responseConfig.authorizedResponders[i] == responder) {
                // Move last element to the deleted position and pop
                responseConfig.authorizedResponders[i] = responseConfig.authorizedResponders[responseConfig.authorizedResponders.length - 1];
                responseConfig.authorizedResponders.pop();
                emit ResponderRemoved(responder);
                return;
            }
        }
        revert("Responder not found");
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        owner = newOwner;
    }

    // ============ VIEW FUNCTIONS ============

    function getAuthorizedResponders() external view returns (address[] memory) {
        return responseConfig.authorizedResponders;
    }

    function isAuthorizedResponder(address responder) external view returns (bool) {
        return _isAuthorizedResponder(responder);
    }

    function getResponseConfig() external view returns (ResponseConfig memory) {
        return responseConfig;
    }

    function canRespond() external view returns (bool) {
        return responseConfig.autoPauseEnabled && 
               block.timestamp >= responseConfig.lastResponseTime + responseConfig.cooldownPeriod;
    }

    function getTimeUntilNextResponse() external view returns (uint256) {
        uint256 nextResponseTime = responseConfig.lastResponseTime + responseConfig.cooldownPeriod;
        if (block.timestamp >= nextResponseTime) {
            return 0;
        }
        return nextResponseTime - block.timestamp;
    }
}
