// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AutoHaltTrap.sol";
import "../src/AutoHaltTrapConfig.sol";

contract MockTargetContract {
    bool private _paused;
    uint256 private _totalSupply = 1000 ether;
    uint256 private _treasuryBalance = 500 ether;
    
    event Paused(address account);
    event Unpaused(address account);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed to, uint256 value);
    event ProposalCreated(uint256 id, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 startBlock, uint256 endBlock, string description);
    event Withdrawal(address indexed account, uint256 amount);
    
    function pause() external {
        _paused = true;
        emit Paused(msg.sender);
    }
    
    function unpause() external {
        _paused = false;
        emit Unpaused(msg.sender);
    }
    
    function isPaused() external view returns (bool) {
        return _paused;
    }
    
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address) external view returns (uint256) {
        return _treasuryBalance;
    }
    
    // Testing helper functions
    function setTotalSupply(uint256 supply) external {
        _totalSupply = supply;
    }
    
    function setTreasuryBalance(uint256 balance) external {
        _treasuryBalance = balance;
    }
}

contract AutoHaltTrapTest is Test {
    AutoHaltTrap public trap;
    AutoHaltTrapConfig public trapConfig;
    MockTargetContract public targetContract;
    
    address public owner = address(0x1);
    address public attacker = address(0x2);
    
    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock target contract
        targetContract = new MockTargetContract();
        
        // Deploy trap system
        trap = new AutoHaltTrap({
            _targetContract: address(targetContract),
            _maxTreasuryDrainPercent: 30,
            _maxSupplyIncreasePercent: 50,
            _maxGovernanceProposalsPerBlock: 3,
            _maxLargeTransfersPerBlock: 5,
            _rapidActionThreshold: 3,
            _analysisWindow: 10,
            _largeTransferThreshold: 100 ether
        });
        
        bytes32 trapHash = keccak256(abi.encodePacked(address(trap), block.timestamp));
        
        trapConfig = new AutoHaltTrapConfig({
            _trapContract: address(trap),
            _targetContract: address(targetContract),
            _trapHash: trapHash,
            _autoPauseEnabled: true,
            _requireManualUnpause: true,
            _cooldownPeriod: 60
        });
        
        vm.stopPrank();
    }
    
    function testNormalActivity() public {
        bytes memory data = trap.collect();
        assertGt(data.length, 0, "Data collection should return data");
        
        bytes[] memory dataArray = new bytes[](1);
        dataArray[0] = data;
        
        (bool incident, ) = trap.shouldRespond(dataArray);
        assertFalse(incident, "Normal activity should not trigger incident");
    }
    
    function testTreasuryDrainDetection() public {
        vm.startPrank(owner);
        
        // Setup: Initial treasury balance
        targetContract.setTreasuryBalance(1000 ether);
        bytes memory data1 = trap.collect();
        
        vm.roll(block.number + 1);
        
        // Simulate large treasury drain (40% - exceeds 30% threshold)
        targetContract.setTreasuryBalance(600 ether);
        bytes memory data2 = trap.collect();
        
        // Test incident detection
        bytes[] memory dataArray = new bytes[](2);
        dataArray[0] = data1;
        dataArray[1] = data2;
        
        (bool incident, bytes memory responseData) = trap.shouldRespond(dataArray);
        assertTrue(incident, "Treasury drain should trigger incident");
        
        (string memory incidentType, ) = abi.decode(responseData, (string, uint256));
        assertEq(incidentType, "Excessive treasury drain");
        
        vm.stopPrank();
    }
    
    function testSupplyManipulationDetection() public {
        vm.startPrank(owner);
        
        // Setup: Initial supply
        targetContract.setTotalSupply(1000 ether);
        bytes memory data1 = trap.collect();
        
        vm.roll(block.number + 1);
        
        // Simulate supply manipulation (60% increase - exceeds 50% threshold)
        targetContract.setTotalSupply(1600 ether);
        bytes memory data2 = trap.collect();
        
        bytes[] memory dataArray = new bytes[](2);
        dataArray[0] = data1;
        dataArray[1] = data2;
        
        (bool incident, bytes memory responseData) = trap.shouldRespond(dataArray);
        assertTrue(incident, "Supply manipulation should trigger incident");
        
        (string memory incidentType, ) = abi.decode(responseData, (string, uint256));
        assertEq(incidentType, "Token supply manipulation");
        
        vm.stopPrank();
    }
    
    function testGovernanceFloodingDetection() public {
        vm.startPrank(owner);
        
        // Create mock event logs for governance proposals
        EventLog[] memory logs = new EventLog[](5);
        for (uint256 i = 0; i < 5; i++) {
            bytes32[] memory topics = new bytes32[](1);
            topics[0] = keccak256("ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)");
            
            logs[i] = EventLog({
                topics: topics,
                data: abi.encode(i, owner),
                emitter: address(targetContract)
            });
        }
        
        trap.setEventLogs(logs);
        
        // Collect data for analysis window
        bytes[] memory dataArray = new bytes[](10);
        for (uint256 i = 0; i < 10; i++) {
            vm.roll(block.number + i);
            dataArray[i] = trap.collect();
        }
        
        (bool incident, bytes memory responseData) = trap.shouldRespond(dataArray);
        assertTrue(incident, "Governance flooding should trigger incident");
        
        (string memory incidentType, ) = abi.decode(responseData, (string, uint256));
        assertEq(incidentType, "Governance flooding attack");
        
        vm.stopPrank();
    }
    
    function testIncidentResponse() public {
        vm.startPrank(owner);
        
        // Verify target is not paused initially
        assertFalse(targetContract.isPaused(), "Target should not be paused initially");
        
        // Simulate incident response
        trapConfig.respondToIncident("Treasury drain attack", abi.encode("Test incident"));
        
        // Verify target is now paused
        assertTrue(targetContract.isPaused(), "Target should be paused after incident");
        
        vm.stopPrank();
    }
    
    function testManualUnpause() public {
        vm.startPrank(owner);
        
        // First pause the contract
        trapConfig.emergencyPause("Test emergency");
        assertTrue(targetContract.isPaused(), "Target should be paused");
        
        // Then unpause it
        trapConfig.manualUnpause();
        assertFalse(targetContract.isPaused(), "Target should be unpaused");
        
        vm.stopPrank();
    }
    
    function testCooldownPeriod() public {
        vm.startPrank(owner);
        
        // First response should succeed
        trapConfig.respondToIncident("First incident", abi.encode("Test"));
        
        // Second response immediately should fail due to cooldown
        vm.expectRevert("Cooldown period active");
        trapConfig.respondToIncident("Second incident", abi.encode("Test"));
        
        // After cooldown period, should succeed
        vm.warp(block.timestamp + 61);
        trapConfig.respondToIncident("Third incident", abi.encode("Test"));
        
        vm.stopPrank();
    }
    
    function testEventLogFilters() public view {
        EventFilter[] memory filters = trap.eventLogFilters();
        
        assertEq(filters.length, 4, "Should have 4 event filters");
        assertEq(filters[0].signature, "Transfer(address,address,uint256)");
        assertEq(filters[1].signature, "Mint(address,uint256)");
        assertEq(filters[2].signature, "ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)");
        assertEq(filters[3].signature, "Withdrawal(address,uint256)");
    }
    
    function testUnauthorizedAccess() public {
        vm.startPrank(attacker);
        
        vm.expectRevert("Not authorized responder");
        trapConfig.emergencyPause("Malicious pause attempt");
        
        vm.expectRevert("Not authorized responder");
        trapConfig.manualUnpause();
        
        vm.stopPrank();
    }
    
    function testResponderManagement() public {
        vm.startPrank(owner);
        
        // Add new responder
        trapConfig.addAuthorizedResponder(attacker);
        assertTrue(trapConfig.isAuthorizedResponder(attacker), "Should be authorized responder");
        
        // New responder should be able to trigger emergency pause
        vm.startPrank(attacker);
        trapConfig.emergencyPause("Authorized emergency pause");
        assertTrue(targetContract.isPaused(), "Target should be paused");
        
        // Remove responder
        vm.startPrank(owner);
        trapConfig.removeAuthorizedResponder(attacker);
        assertFalse(trapConfig.isAuthorizedResponder(attacker), "Should not be authorized responder");
        
        vm.stopPrank();
    }
    
    function testThresholdConfiguration() public view {
        AutoHaltTrap.ThresholdConfig memory thresholds = trap.getThresholds();
        
        assertEq(thresholds.targetContract, address(targetContract));
        assertEq(thresholds.maxTreasuryDrainPercent, 30);
        assertEq(thresholds.maxSupplyIncreasePercent, 50);
        assertEq(thresholds.maxGovernanceProposalsPerBlock, 3);
        assertEq(thresholds.maxLargeTransfersPerBlock, 5);
        assertEq(thresholds.rapidActionThreshold, 3);
        assertEq(thresholds.analysisWindow, 10);
        assertEq(thresholds.largeTransferThreshold, 100 ether);
    }
    
    function testVersion() public view {
        assertEq(trap.version(), "2.0", "Should return correct version");
    }
    
    function testInsufficientData() public {
        bytes[] memory dataArray = new bytes[](1);
        dataArray[0] = trap.collect();
        
        (bool incident, bytes memory responseData) = trap.shouldRespond(dataArray);
        assertFalse(incident, "Single data point should not trigger incident");
        assertEq(responseData.length, 0, "Response data should be empty");
    }
}
