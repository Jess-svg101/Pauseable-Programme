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
    
    function simulateTransfer(address to, uint256 amount) external {
        emit Transfer(msg.sender, to, amount);
    }
    
    function simulateMint(address to, uint256 amount) external {
        emit Mint(to, amount);
        _totalSupply += amount;
    }
    
    function simulateWithdrawal(uint256 amount) external {
        emit Withdrawal(msg.sender, amount);
        _treasuryBalance -= amount;
    }
    
    function simulateProposal(string memory description) external {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        
        targets[0] = address(this);
        values[0] = 0;
        signatures[0] = "pause()";
        calldatas[0] = "";
        
        emit ProposalCreated(
            block.timestamp,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            block.number,
            block.number + 100,
            description
        );
    }
}
