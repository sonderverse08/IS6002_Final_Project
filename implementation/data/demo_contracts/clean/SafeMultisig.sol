pragma solidity 0.5.17;

// =============================================================
// SafeMultisig - vi da chu ky don gian
// Giao dich phai du so xac nhan, danh dau da thuc thi truoc khi goi ngoai.
// Bien dich: solc 0.5.17, EVM default, dung cho muc dich thuc nghiem
// =============================================================

contract SafeMultisig {

    // ---------- Metadata ----------
    string public contractName = "SafeMultisig";
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


    struct Proposal {
        address payable target;
        uint256 value;
        uint256 confirmations;
        bool executed;
    }

    Proposal[] public proposals;
    mapping(uint256 => mapping(address => bool)) public confirmedBy;
    uint256 public requiredConfirmations;

    event ProposalCreated(uint256 indexed id, address target, uint256 value);
    event Confirmed(uint256 indexed id, address indexed signer);
    event Executed(uint256 indexed id);

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }

    function setRequired(uint256 count) public onlyOwner {
        require(count > 0 && count <= 10, "invalid requirement");
        requiredConfirmations = count;
    }

    function propose(address payable target, uint256 value)
        public onlyOperator validAddress(target) returns (uint256)
    {
        require(value <= address(this).balance, "value exceeds balance");

        proposals.push(Proposal({
            target: target,
            value: value,
            confirmations: 0,
            executed: false
        }));

        uint256 id = proposals.length - 1;
        emit ProposalCreated(id, target, value);
        return id;
    }

    function confirm(uint256 id) public onlyOperator {
        require(id < proposals.length, "invalid proposal");
        require(!proposals[id].executed, "already executed");
        require(!confirmedBy[id][msg.sender], "already confirmed");

        confirmedBy[id][msg.sender] = true;
        proposals[id].confirmations = add(proposals[id].confirmations, 1);

        emit Confirmed(id, msg.sender);
    }

    function execute(uint256 id) public onlyOperator {
        require(id < proposals.length, "invalid proposal");

        Proposal storage p = proposals[id];

        require(!p.executed, "already executed");
        require(p.confirmations >= requiredConfirmations, "not enough confirmations");
        require(p.value <= address(this).balance, "insufficient balance");

        // Danh dau da thuc thi TRUOC khi chuyen tien
        p.executed = true;
        _record(p.target, p.value, "execute");

        p.target.transfer(p.value);

        emit Executed(id);
    }

    function proposalCount() public view returns (uint256) {
        return proposals.length;
    }

    function isConfirmed(uint256 id) public view returns (bool) {
        return id < proposals.length && proposals[id].confirmations >= requiredConfirmations;
    }

    function () external payable {
        _track(msg.sender);
    }

}
