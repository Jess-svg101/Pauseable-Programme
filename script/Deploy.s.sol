// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "./AutoHaltTrap.sol";
import "./AutoHaltTrapConfig.sol";


contract DeployAutoHaltTrap is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address targetContract = vm.envAddress("TARGET_CONTRACT"); // Contract to protect
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the trap contract
        AutoHaltTrap trap = new AutoHaltTrap({
            _targetContract: targetContract,
            _maxTreasuryDrainPercent: 30,      // 30% max drain
            _maxSupplyIncreasePercent: 50,     // 50% max supply increase
            _maxGovernanceProposalsPerBlock: 3, // 3 proposals per block
            _maxLargeTransfersPerBlock: 5,     // 5 large transfers per block
            _rapidActionThreshold: 3,          // 3 blocks for rapid action detection
            _analysisWindow: 10,               // Analyze last 10 blocks
            _largeTransferThreshold: 1000 ether // Consider 1000+ ETH as large
        });
        
        // Calculate trap hash (simplified - in production use proper hashing)
        bytes32 trapHash = keccak256(abi.encodePacked(address(trap), block.timestamp));
        
        // Deploy the trap config
        AutoHaltTrapConfig trapConfig = new AutoHaltTrapConfig({
            _trapContract: address(trap),
            _targetContract: targetContract,
            _trapHash: trapHash,
            _autoPauseEnabled: true,
            _requireManualUnpause: true,       // Require manual intervention to unpause
            _cooldownPeriod: 300              // 5 minutes cooldown between responses
        });
        
        vm.stopBroadcast();
        
        console.log("AutoHaltTrap deployed at:", address(trap));
        console.log("AutoHaltTrapConfig deployed at:", address(trapConfig));
        console.log("Target contract:", targetContract);
        console.log("Trap hash:", vm.toString(trapHash));
        
        // Output Drosera CLI commands
        console.log("\n=== Drosera CLI Commands ===");
        console.log("1. Create trap configuration:");
        console.log(string(abi.encodePacked(
            "drosera create-trap --trap-address ", 
            vm.toString(address(trap)),
            " --config-address ", 
            vm.toString(address(trapConfig)),
            " --response-function respondToIncident(string,bytes)"
        )));
        
        console.log("\n2. Start monitoring:");
        console.log("drosera start-monitoring --trap-id <TRAP_ID>");
    }
}


contract TestAutoHaltTrap is Test {
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
            _cooldownPeriod: 60 // 1 minute for testing
        });
        
        vm.stopPrank();
    }
    
    function testNormalActivity() public {
        // Simulate normal data collection
        bytes memory data = trap.collect();
        
        // Should not trigger incident
        bytes[] memory dataArray = new bytes[](1);
        dataArray[0] = data;
        
        (bool incident, bytes memory responseData) = trap.shouldRespond(dataArray);
        assertFalse(incident);
    }
    
    function testTreasuryDrainDetection() public {
        // Setup: Create historical data showing treasury drain
        vm.startPrank(owner);
        
        // Simulate large treasury drain
        targetContract.setTreasuryBalance(1000 ether); // Initial balance
        bytes memory data1 = trap.collect();
        
        vm.roll(block.number + 1);
        targetContract.setTreasuryBalance(600 ether); // 40% drain - exceeds 30% threshold
        bytes memory data2 = trap.collect();
        
        // Test incident detection
        bytes[] memory dataArray = new bytes[](2);
        dataArray[0] = data1;
        dataArray[1] = data2;
        
        (bool incident, bytes memory responseData) = trap.shouldRespond(dataArray);
        assertTrue(incident);
        
        // Decode response data
        (string memory incidentType, uint256 timestamp) = abi.decode(responseData, (string, uint256));
        assertEq(incidentType, "Excessive treasury drain");
        
        vm.stopPrank();
    }
    
    function testSupplyManipulationDetection() public {
        vm.startPrank(owner);
        
        // Simulate token supply manipulation
        targetContract.setTotalSupply(1000 ether);
        bytes memory data1 = trap.collect();
        
        vm.roll(block.number + 1);
        targetContract.setTotalSupply(1600 ether); // 60% increase - exceeds 50% threshold
        bytes memory data2 = trap.collect();
        
        bytes[] memory dataArray = new bytes[](2);
        dataArray[0] = data1;
        dataArray[1] = data2;
        
        (bool incident, bytes memory responseData) = trap.shouldRespond(dataArray);
        assertTrue(incident);
        
        vm.stopPrank();
    }
    
    function testIncidentResponse() public {
        vm.startPrank(owner);
        
        // Verify target is not paused initially
        assertFalse(targetContract.isPaused());
        
        // Simulate incident response
        trapConfig.respondToIncident("Treasury drain attack", abi.encode("Test incident"));
        
        // Verify target is now paused
        assertTrue(targetContract.isPaused());
        
        vm.stopPrank();
    }
    
    function testManualUnpause() public {
        vm.startPrank(owner);
        
        // First pause the contract
        trapConfig.emergencyPause("Test emergency");
        assertTrue(targetContract.isPaused());
        
        // Then unpause it
        trapConfig.manualUnpause();
        assertFalse(targetContract.isPaused());
        
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
        vm.warp(block.timestamp + 61); // Wait 61 seconds (cooldown is 60 seconds)
        trapConfig.respondToIncident("Third incident", abi.encode("Test"));
        
        vm.stopPrank();
    }
    
    function testGovernanceFloodingDetection() public {
        vm.startPrank(owner);
        
        // Create mock event logs for governance flooding
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
        
        // Collect data for multiple blocks to simulate governance flooding
        bytes[] memory dataArray = new bytes[](10);
        for (uint256 i = 0; i < 10; i++) {
            vm.roll(block.number + i);
            dataArray[i] = trap.collect();
        }
        
        (bool incident, ) = trap.shouldRespond(dataArray);
        assertTrue(incident);
        
        vm.stopPrank();
    }
    
    function testEventLogFilters() public view {
        EventFilter[] memory filters = trap.eventLogFilters();
        
        assertEq(filters.length, 5);
        assertEq(filters[0].signature, "Transfer(address,address,uint256)");
        assertEq(filters[1].signature, "Mint(address,uint256)");
        assertEq(filters[2].signature, "ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)");
        assertEq(filters[3].signature, "Withdrawal(address,uint256)");
        assertEq(filters[4].signature, "Paused(address)");
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
        assertTrue(trapConfig.isAuthorizedResponder(attacker));
        
        // New responder should be able to trigger emergency pause
        vm.startPrank(attacker);
        trapConfig.emergencyPause("Authorized emergency pause");
        assertTrue(targetContract.isPaused());
        
        // Remove responder
        vm.startPrank(owner);
        trapConfig.removeAuthorizedResponder(attacker);
        assertFalse(trapConfig.isAuthorizedResponder(attacker));
        
        vm.stopPrank();
    }
}
