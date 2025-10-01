// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AutoHaltTrapConfig
 * @notice Response contract for AutoHaltTrap - Handles incident responses from Drosera operators
 * @dev This contract IS stateful and persists between Drosera operator calls
 * 
 * CRITICAL REQUIREMENTS:
 * - Target contract must implement IPausable interface
 * - Drosera operators must be authorized via authorizeOperator()
 * - Config contract needs PAUSER_ROLE on target contract
 * - Response function signature: respondToIncident(bytes calldata)
 * 
 * @author Your Name
 * @custom:security-contact security@yourprotocol.com
 */

interface IPausable {
    function pause() external;
    function unpause() external;
    function isPaused() external view returns (bool);
}

contract AutoHaltTrapConfig {
    
    // ============================================================
    //                      IMMUTABLE STATE
    // ============================================================
    
    /// @notice Address of the trap contract (for reference/verification)
    address public immutable trapAddress;
    
    /// @notice Address of the target contract to protect
    address public immutable targetContract;
    
    /// @notice Drosera protocol contract address (for future operator verification)
    /// @dev In production, use this to verify operators against protocol registry
    address public immutable droseraProtocolAddress;
    
    // ============================================================
    //                      MUTABLE STATE
    // ============================================================
    
    /// @notice Contract owner (has full administrative control)
    address public owner;
    
    /// @notice Whether automated pause responses are enabled
    bool public autoPauseEnabled;
    
    /// @notice Whether manual unpause is required (prevents auto-recovery)
    bool public requireManualUnpause;
    
    /// @notice Cooldown period between automated responses (seconds)
    uint256 public cooldownPeriod;
    
    /// @notice Timestamp of last automated response (for cooldown enforcement)
    uint256 public lastResponseTime;
    
    /// @notice Authorized Drosera operators (can trigger automated responses)
    mapping(address => bool) public authorizedOperators;
    
    /// @notice Emergency responders (can manually pause/unpause)
    mapping(address => bool) public emergencyResponders;
    
    /// @notice Total number of incidents responded to
    uint256 public totalIncidentCount;
    
    /// @notice Total number of successful pauses executed
    uint256 public totalPauseCount;
    
    // ============================================================
    //                          EVENTS
    // ============================================================
    
    event IncidentResponse(
        string indexed incidentType,
        uint256 blockNumber,
        uint256 timestamp,
        bytes incidentData
    );
    
    event EmergencyPause(
        address indexed target,
        address indexed initiator,
        string reason,
        uint256 timestamp
    );
    
    event ManualUnpause(
        address indexed target,
        address indexed operator,
        uint256 timestamp
    );
    
    event OperatorAuthorized(address indexed operator);
    event OperatorRevoked(address indexed operator);
    event ResponderAdded(address indexed responder);
    event ResponderRemoved(address indexed responder);
    event ConfigUpdated(string parameter, uint256 newValue);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    // ============================================================
    //                          ERRORS
    // ============================================================
    
    error OnlyOwner();
    error UnauthorizedOperator(address caller);
    error UnauthorizedResponder(address caller);
    error CooldownActive(uint256 remainingSeconds);
    error AutoPauseDisabled();
    error PauseFailed(string reason);
    error TargetNotPausable();
    error InvalidAddress();
    error CannotRemoveOwner();
    
    // ============================================================
    //                         MODIFIERS
    // ============================================================
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }
    
    modifier onlyAuthorizedOperator() {
        if (!authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        _;
    }
    
    modifier onlyEmergencyResponder() {
        if (!emergencyResponders[msg.sender] && msg.sender != owner) {
            revert UnauthorizedResponder(msg.sender);
        }
        _;
    }
    
    // ============================================================
    //                       CONSTRUCTOR
    // ============================================================
    
    /**
     * @notice Initialize the trap config contract
     * @param _trapAddress Address of the deployed trap contract
     * @param _targetContract Address of the contract to protect
     * @param _droseraProtocolAddress Address of Drosera protocol (for operator verification)
     * @param _autoPauseEnabled Whether automated pausing is enabled
     * @param _requireManualUnpause Whether manual intervention required for unpause
     * @param _cooldownPeriod Minimum seconds between automated responses
     */
    constructor(
        address _trapAddress,
        address _targetContract,
        address _droseraProtocolAddress,
        bool _autoPauseEnabled,
        bool _requireManualUnpause,
        uint256 _cooldownPeriod
    ) {
        if (_trapAddress == address(0) || 
            _targetContract == address(0) || 
            _droseraProtocolAddress == address(0)) {
            revert InvalidAddress();
        }
        
        trapAddress = _trapAddress;
        targetContract = _targetContract;
        droseraProtocolAddress = _droseraProtocolAddress;
        
        owner = msg.sender;
        autoPauseEnabled = _autoPauseEnabled;
        requireManualUnpause = _requireManualUnpause;
        cooldownPeriod = _cooldownPeriod;
        lastResponseTime = 0;
        totalIncidentCount = 0;
        totalPauseCount = 0;
        
        // Owner is default emergency responder
        emergencyResponders[msg.sender] = true;
        emit ResponderAdded(msg.sender);
    }
    
    // ============================================================
    //                   CORE RESPONSE FUNCTION
    // ============================================================
    
    /**
     * @notice Main response function called by Drosera operators when trap detects incidents
     * @dev This is the callback specified in Drosera trap registration
     * @param incidentData Encoded incident details from trap's shouldRespond()
     * 
     * Expected incident data formats:
     * - TREASURY_DRAIN: abi.encode("TREASURY_DRAIN", blockNumber, drainBps, drainAmount)
     * - SUPPLY_MANIPULATION: abi.encode("SUPPLY_MANIPULATION", blockNumber, increaseBps, increaseAmount)
     * - GOVERNANCE_FLOODING: abi.encode("GOVERNANCE_FLOODING", blockNumber, totalProposals, threshold)
     * - RAPID_ACTIVITY: abi.encode("RAPID_ACTIVITY", blockNumber, actorAddress, thresholdBlocks)
     */
    function respondToIncident(bytes calldata incidentData) 
        external 
        onlyAuthorizedOperator 
    {
        // Check if auto-pause is enabled
        if (!autoPauseEnabled) {
            revert AutoPauseDisabled();
        }
        
        // Enforce cooldown period
        if (block.timestamp < lastResponseTime + cooldownPeriod) {
            uint256 remaining = lastResponseTime + cooldownPeriod - block.timestamp;
            revert CooldownActive(remaining);
        }
        
        // Update response timestamp
        lastResponseTime = block.timestamp;
        totalIncidentCount++;
        
        // Decode incident type and block number
        (string memory incidentType, uint256 blockNumber) = abi.decode(
            incidentData,
            (string, uint256)
        );
        
        // Execute pause on target contract
        _executePause(incidentType, incidentData);
        
        // Emit comprehensive incident response event
        emit IncidentResponse(
            incidentType,
            blockNumber,
            block.timestamp,
            incidentData
        );
    }
    
    // ============================================================
    //                    MANUAL CONTROLS
    // ============================================================
    
    /**
     * @notice Manual emergency pause triggered by authorized responder
     * @dev Bypasses cooldown period - use for immediate threats
     * @param reason Human-readable reason for emergency pause
     */
    function emergencyPause(string calldata reason) 
        external 
        onlyEmergencyResponder 
    {
        bytes memory incidentData = abi.encode(
            "MANUAL_EMERGENCY",
            block.number,
            msg.sender,
            reason
        );
        
        _executePause(reason, incidentData);
        
        emit EmergencyPause(
            targetContract,
            msg.sender,
            reason,
            block.timestamp
        );
    }
    
    /**
     * @notice Manual unpause after incident investigation and resolution
     * @dev Only works if requireManualUnpause is true
     */
    function manualUnpause() 
        external 
        onlyEmergencyResponder 
    {
        if (!requireManualUnpause) {
            revert("Manual unpause not required - disable flag first");
        }
        
        // Verify target is actually paused before attempting unpause
        try IPausable(targetContract).isPaused() returns (bool paused) {
            if (!paused) {
                revert("Target is not paused");
            }
        } catch {
            // If isPaused() not implemented, try unpause anyway
        }
        
        // Attempt to unpause target contract
        try IPausable(targetContract).unpause() {
            emit ManualUnpause(targetContract, msg.sender, block.timestamp);
        } catch Error(string memory reason) {
            revert PauseFailed(reason);
        } catch {
            revert TargetNotPausable();
        }
    }
    
    // ============================================================
    //                   INTERNAL FUNCTIONS
    // ============================================================
    
    /**
     * @dev Internal function to execute pause on target contract with comprehensive error handling
     * @param reason Description of why pause is being executed
     * @param incidentData Full incident data for event logging
     */
    function _executePause(string memory reason, bytes memory incidentData) 
        internal 
    {
        // First check if target is already paused
        try IPausable(targetContract).isPaused() returns (bool paused) {
            if (paused) {
                // Already paused - emit event but don't try to pause again
                emit IncidentResponse(
                    string(abi.encodePacked(reason, " (already paused)")),
                    block.number,
                    block.timestamp,
                    incidentData
                );
                return;
            }
        } catch {
            // Target doesn't implement isPaused() - continue with pause attempt
        }
        
        // Attempt to pause the target contract
        try IPausable(targetContract).pause() {
            totalPauseCount++;
            emit EmergencyPause(
                targetContract,
                msg.sender,
                reason,
                block.timestamp
            );
        } catch Error(string memory errorReason) {
            // Pause failed with error message - log but don't revert
            // This allows Drosera monitoring to continue even if pause fails
            emit IncidentResponse(
                string(abi.encodePacked("PAUSE_FAILED: ", reason, " - ", errorReason)),
                block.number,
                block.timestamp,
                incidentData
            );
        } catch (bytes memory lowLevelData) {
            // Catch low-level revert without error message
            emit IncidentResponse(
                string(abi.encodePacked("PAUSE_FAILED: ", reason, " - Low level revert")),
                block.number,
                block.timestamp,
                abi.encode(incidentData, lowLevelData)
            );
        }
    }
    
    // ============================================================
    //                  OPERATOR MANAGEMENT
    // ============================================================
    
    /**
     * @notice Authorize a Drosera operator to trigger automated responses
     * @param operator Address of operator to authorize
     * @dev In production, verify operator is registered with Drosera protocol:
     *      require(IDroseraProtocol(droseraProtocolAddress).isOperator(operator), "Not registered");
     */
    function authorizeOperator(address operator) 
        external 
        onlyOwner 
    {
        if (operator == address(0)) revert InvalidAddress();
        
        // TODO: In production, verify against Drosera protocol registry
        // interface IDroseraProtocol {
        //     function isRegisteredOperator(address) external view returns (bool);
        // }
        // require(
        //     IDroseraProtocol(droseraProtocolAddress).isRegisteredOperator(operator),
        //     "Operator not registered with Drosera"
        // );
        
        authorizedOperators[operator] = true;
        emit OperatorAuthorized(operator);
    }
    
    /**
     * @notice Revoke operator authorization
     * @param operator Address of operator to revoke
     */
    function revokeOperator(address operator) 
        external 
        onlyOwner 
    {
        authorizedOperators[operator] = false;
        emit OperatorRevoked(operator);
    }
    
    /**
     * @notice Batch authorize multiple operators (gas efficient)
     * @param operators Array of operator addresses to authorize
     */
    function batchAuthorizeOperators(address[] calldata operators) 
        external 
        onlyOwner 
    {
        for (uint256 i = 0; i < operators.length; i++) {
            if (operators[i] != address(0)) {
                authorizedOperators[operators[i]] = true;
                emit OperatorAuthorized(operators[i]);
            }
        }
    }
    
    /**
     * @notice Add emergency responder (can manually pause/unpause)
     * @param responder Address to authorize as emergency responder
     */
    function addEmergencyResponder(address responder) 
        external 
        onlyOwner 
    {
        if (responder == address(0)) revert InvalidAddress();
        
        emergencyResponders[responder] = true;
        emit ResponderAdded(responder);
    }
    
    /**
     * @notice Remove emergency responder authorization
     * @param responder Address to remove
     */
    function removeEmergencyResponder(address responder) 
        external 
        onlyOwner 
    {
        if (responder == owner) revert CannotRemoveOwner();
        
        emergencyResponders[responder] = false;
        emit ResponderRemoved(responder);
    }
    
    // ============================================================
    //                    CONFIGURATION
    // ============================================================
    
    /**
     * @notice Update configuration parameters
     * @param _autoPauseEnabled Whether automated pausing is enabled
     * @param _requireManualUnpause Whether manual unpause is required
     * @param _cooldownPeriod New cooldown period in seconds
     */
    function updateConfig(
        bool _autoPauseEnabled,
        bool _requireManualUnpause,
        uint256 _cooldownPeriod
    ) external onlyOwner {
        autoPauseEnabled = _autoPauseEnabled;
        requireManualUnpause = _requireManualUnpause;
        cooldownPeriod = _cooldownPeriod;
        
        emit ConfigUpdated("autoPauseEnabled", _autoPauseEnabled ? 1 : 0);
        emit ConfigUpdated("requireManualUnpause", _requireManualUnpause ? 1 : 0);
        emit ConfigUpdated("cooldownPeriod", _cooldownPeriod);
    }
    
    /**
     * @notice Transfer ownership to new address
     * @param newOwner Address of new owner
     */
    function transferOwnership(address newOwner) 
        external 
        onlyOwner 
    {
        if (newOwner == address(0)) revert InvalidAddress();
        
        address previousOwner = owner;
        owner = newOwner;
        
        // Automatically add new owner as emergency responder
        emergencyResponders[newOwner] = true;
        emit ResponderAdded(newOwner);
        
        emit OwnershipTransferred(previousOwner, newOwner);
    }
    
    // ============================================================
    //                     VIEW FUNCTIONS
    // ============================================================
    
    /**
     * @notice Check if automated response can be executed (cooldown passed)
     * @return True if response can be triggered
     */
    function canRespond() external view returns (bool) {
        return autoPauseEnabled && 
               block.timestamp >= lastResponseTime + cooldownPeriod;
    }
    
    /**
     * @notice Get remaining time in cooldown period
     * @return Seconds remaining until next response can be executed (0 if ready)
     */
    function cooldownRemaining() external view returns (uint256) {
        uint256 nextResponseTime = lastResponseTime + cooldownPeriod;
        if (block.timestamp >= nextResponseTime) {
            return 0;
        }
        return nextResponseTime - block.timestamp;
    }
    
    /**
     * @notice Check if address is authorized Drosera operator
     * @param operator Address to check
     * @return True if authorized
     */
    function isAuthorizedOperator(address operator) 
        external 
        view 
        returns (bool) 
    {
        return authorizedOperators[operator];
    }
    
    /**
     * @notice Check if address is authorized emergency responder
     * @param responder Address to check
     * @return True if authorized (includes owner)
     */
    function isEmergencyResponder(address responder) 
        external 
        view 
        returns (bool) 
    {
        return emergencyResponders[responder] || responder == owner;
    }
    
    /**
     * @notice Get comprehensive config status
     * @return Config struct with all current settings
     */
    function getConfig() 
        external 
        view 
        returns (
            address _owner,
            bool _autoPauseEnabled,
            bool _requireManualUnpause,
            uint256 _cooldownPeriod,
            uint256 _lastResponseTime,
            uint256 _totalIncidents,
            uint256 _totalPauses
        ) 
    {
        return (
            owner,
            autoPauseEnabled,
            requireManualUnpause,
            cooldownPeriod,
            lastResponseTime,
            totalIncidentCount,
            totalPauseCount
        );
    }
    
    /**
     * @notice Check if target contract is currently paused
     * @return True if paused, false otherwise
     */
    function isTargetPaused() external view returns (bool) {
        try IPausable(targetContract).isPaused() returns (bool paused) {
            return paused;
        } catch {
            return false; // Assume not paused if call fails
        }
    }
}
