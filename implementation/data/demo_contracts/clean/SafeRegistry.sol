pragma solidity 0.5.17;

// =============================================================
// SafeRegistry - so dang ky dia chi
// Chi doc ghi trang thai noi bo, khong goi ngoai, kiem tra day du.
// Bien dich: solc 0.5.17, EVM default, dung cho muc dich thuc nghiem
// =============================================================

contract SafeRegistry {

    // ---------- Metadata ----------
    string public contractName = "SafeRegistry";
    string public contractVersion = "1.0.0";
    uint8 public constant DECIMALS = 18;

    // ---------- Quyen so huu ----------
    address public owner;
    address public pendingOwner;
    bool public paused;

    // ---------- Trang thai chung ----------
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;
    mapping(address => bool) public operators;
    mapping(address => uint256) public lastActionAt;

    address[] public participants;
    mapping(address => bool) private isParticipant;

    uint256 public totalSupply;
    uint256 public operationCount;
    uint256 public feeBasisPoints;

    struct Record {
        address account;
        uint256 amount;
        uint256 timestamp;
        bytes32 tag;
    }

    Record[] public history;

    // ---------- Su kien ----------
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed holder, address indexed spender, uint256 value);
    event OwnershipTransferStarted(address indexed from, address indexed to);
    event OwnershipTransferred(address indexed from, address indexed to);
    event OperatorUpdated(address indexed account, bool enabled);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event RecordAdded(address indexed account, uint256 amount, bytes32 tag);

    // ---------- Dieu kien ----------
    modifier onlyOwner() {
        require(msg.sender == owner, "caller is not the owner");
        _;
    }

    modifier onlyOperator() {
        require(operators[msg.sender] || msg.sender == owner, "caller is not an operator");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "contract is paused");
        _;
    }

    modifier validAddress(address account) {
        require(account != address(0), "zero address not allowed");
        _;
    }

    constructor(uint256 initialSupply) public {
        owner = msg.sender;
        operators[msg.sender] = true;
        totalSupply = initialSupply;
        balances[msg.sender] = initialSupply;
        feeBasisPoints = 25;
        _track(msg.sender);
        emit Transfer(address(0), msg.sender, initialSupply);
    }

    // ---------- Quan tri ----------
    function transferOwnership(address newOwner) public onlyOwner validAddress(newOwner) {
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() public {
        require(msg.sender == pendingOwner, "caller is not the pending owner");
        address previous = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, owner);
    }

    function setOperator(address account, bool enabled) public onlyOwner validAddress(account) {
        operators[account] = enabled;
        emit OperatorUpdated(account, enabled);
    }

    function pause() public onlyOwner {
        require(!paused, "already paused");
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner {
        require(paused, "not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }

    function setFee(uint256 newFee) public onlyOwner {
        require(newFee <= 1000, "fee too high");
        uint256 old = feeBasisPoints;
        feeBasisPoints = newFee;
        emit FeeUpdated(old, newFee);
    }

    // ---------- Tien ich noi bo ----------
    function _track(address account) internal {
        if (!isParticipant[account]) {
            isParticipant[account] = true;
            participants.push(account);
        }
        lastActionAt[account] = now;
        operationCount = operationCount + 1;
    }

    function _record(address account, uint256 amount, bytes32 tag) internal {
        history.push(Record({
            account: account,
            amount: amount,
            timestamp: now,
            tag: tag
        }));
        emit RecordAdded(account, amount, tag);
    }

    function participantCount() public view returns (uint256) {
        return participants.length;
    }

    function historyCount() public view returns (uint256) {
        return history.length;
    }

    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    function allowance(address holder, address spender) public view returns (uint256) {
        return allowances[holder][spender];
    }

    function approve(address spender, uint256 value)
        public whenNotPaused validAddress(spender) returns (bool)
    {
        allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function describe() public view returns (string memory, string memory, uint256, bool) {
        return (contractName, contractVersion, totalSupply, paused);
    }

    function summarize(uint256 fromIndex, uint256 count)
        public view returns (uint256 total, uint256 counted)
    {
        require(fromIndex <= history.length, "index out of range");
        uint256 end = fromIndex + count;
        if (end > history.length) {
            end = history.length;
        }
        for (uint256 i = fromIndex; i < end; i++) {
            total = total + history[i].amount;
            counted = counted + 1;
        }
    }


    struct Profile {
        bytes32 name;
        uint256 level;
        uint256 registeredAt;
        bool active;
    }

    mapping(address => Profile) public profiles;
    mapping(bytes32 => address) public nameToAddress;
    uint256 public activeCount;

    event Registered(address indexed account, bytes32 name);
    event Deactivated(address indexed account);
    event LevelChanged(address indexed account, uint256 oldLevel, uint256 newLevel);

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "subtraction underflow");
        return a - b;
    }

    function register(bytes32 name) public whenNotPaused {
        require(name != bytes32(0), "empty name");
        require(nameToAddress[name] == address(0), "name already taken");
        require(!profiles[msg.sender].active, "already registered");

        profiles[msg.sender] = Profile({
            name: name,
            level: 1,
            registeredAt: now,
            active: true
        });

        nameToAddress[name] = msg.sender;
        activeCount = add(activeCount, 1);

        _track(msg.sender);
        _record(msg.sender, 1, name);

        emit Registered(msg.sender, name);
    }

    function deactivate(address account) public onlyOperator validAddress(account) {
        require(profiles[account].active, "not active");

        profiles[account].active = false;
        nameToAddress[profiles[account].name] = address(0);
        activeCount = sub(activeCount, 1);

        emit Deactivated(account);
    }

    function setLevel(address account, uint256 newLevel) public onlyOperator {
        require(profiles[account].active, "not active");
        require(newLevel > 0 && newLevel <= 10, "level out of range");

        uint256 old = profiles[account].level;
        profiles[account].level = newLevel;

        emit LevelChanged(account, old, newLevel);
    }

    function lookup(bytes32 name) public view returns (address account, uint256 level, bool active) {
        account = nameToAddress[name];
        level = profiles[account].level;
        active = profiles[account].active;
    }

    function countActiveAbove(uint256 minLevel) public view returns (uint256 total) {
        for (uint256 i = 0; i < participants.length; i++) {
            Profile storage p = profiles[participants[i]];
            if (p.active && p.level >= minLevel) {
                total = add(total, 1);
            }
        }
    }

}
