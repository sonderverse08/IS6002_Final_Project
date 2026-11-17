pragma solidity 0.5.17;

// =============================================================
// SafeStaking - gui va rut von co khoa thoi gian
// Moi phep tinh deu kiem tra tran so, khong goi ngoai toi dia chi tuy y.
// Bien dich: solc 0.5.17, EVM default, dung cho muc dich thuc nghiem
// =============================================================

contract SafeStaking {

    // ---------- Metadata ----------
    string public contractName = "SafeStaking";
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


    struct Stake {
        uint256 amount;
        uint256 startedAt;
        uint256 unlockAt;
        bool withdrawn;
    }

    mapping(address => Stake) public stakes;
    uint256 public totalStaked;
    uint256 public rewardRateBasisPoints;
    uint256 public minLockSeconds;

    event Staked(address indexed account, uint256 amount, uint256 unlockAt);
    event Unstaked(address indexed account, uint256 amount, uint256 reward);

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "subtraction underflow");
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "multiplication overflow");
        return c;
    }

    function configure(uint256 rate, uint256 lockSeconds) public onlyOwner {
        require(rate <= 5000, "rate too high");
        require(lockSeconds >= 1 days, "lock too short");
        rewardRateBasisPoints = rate;
        minLockSeconds = lockSeconds;
    }

    function stake(uint256 lockSeconds) public payable whenNotPaused {
        require(msg.value > 0, "no value sent");
        require(lockSeconds >= minLockSeconds, "lock period too short");
        require(stakes[msg.sender].amount == 0, "existing stake found");

        stakes[msg.sender] = Stake({
            amount: msg.value,
            startedAt: now,
            unlockAt: add(now, lockSeconds),
            withdrawn: false
        });

        totalStaked = add(totalStaked, msg.value);

        _track(msg.sender);
        _record(msg.sender, msg.value, "stake");

        emit Staked(msg.sender, msg.value, stakes[msg.sender].unlockAt);
    }

    function pendingReward(address account) public view returns (uint256) {
        Stake storage s = stakes[account];
        if (s.amount == 0 || s.withdrawn) {
            return 0;
        }
        return mul(s.amount, rewardRateBasisPoints) / 10000;
    }

    function unstake() public whenNotPaused {
        Stake storage s = stakes[msg.sender];
        require(s.amount > 0, "no stake found");
        require(!s.withdrawn, "already withdrawn");
        require(now >= s.unlockAt, "stake still locked");

        uint256 amount = s.amount;
        uint256 reward = mul(amount, rewardRateBasisPoints) / 10000;

        // Cap nhat trang thai TRUOC khi chuyen tien
        s.withdrawn = true;
        s.amount = 0;
        totalStaked = sub(totalStaked, amount);

        msg.sender.transfer(amount);

        emit Unstaked(msg.sender, amount, reward);
    }

    function emergencyWithdraw() public onlyOwner {
        require(paused, "only when paused");
        uint256 amount = address(this).balance;
        require(amount > 0, "no balance");
        msg.sender.transfer(amount);
    }

    function stakeInfo(address account)
        public view returns (uint256 amount, uint256 unlockAt, bool withdrawn, bool unlocked)
    {
        Stake storage s = stakes[account];
        return (s.amount, s.unlockAt, s.withdrawn, now >= s.unlockAt);
    }

}
