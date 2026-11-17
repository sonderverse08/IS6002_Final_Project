pragma solidity 0.5.17;

// =============================================================
// SafeAuction - dau gia theo mo hinh pull payment
// Nguoi thua tu rut tien ve, hop dong khong chu dong goi ngoai trong vong lap.
// Bien dich: solc 0.5.17, EVM default, dung cho muc dich thuc nghiem
// =============================================================

contract SafeAuction {

    // ---------- Metadata ----------
    string public contractName = "SafeAuction";
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


    address public highestBidder;
    uint256 public highestBid;
    uint256 public auctionEndTime;
    bool public ended;

    mapping(address => uint256) public refunds;

    event HighestBidIncreased(address indexed bidder, uint256 amount);
    event AuctionEnded(address indexed winner, uint256 amount);
    event RefundWithdrawn(address indexed bidder, uint256 amount);

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "subtraction underflow");
        return a - b;
    }

    function startAuction(uint256 durationSeconds) public onlyOwner {
        require(auctionEndTime == 0, "auction already started");
        require(durationSeconds > 0, "invalid duration");
        auctionEndTime = add(now, durationSeconds);
    }

    function bid() public payable whenNotPaused {
        require(auctionEndTime > 0, "auction not started");
        require(now < auctionEndTime, "auction already ended");
        require(msg.value > highestBid, "bid not high enough");

        if (highestBidder != address(0)) {
            refunds[highestBidder] = add(refunds[highestBidder], highestBid);
        }

        highestBidder = msg.sender;
        highestBid = msg.value;

        _track(msg.sender);
        _record(msg.sender, msg.value, "bid");

        emit HighestBidIncreased(msg.sender, msg.value);
    }

    function withdrawRefund() public {
        uint256 amount = refunds[msg.sender];
        require(amount > 0, "no refund available");

        // Xoa trang thai TRUOC khi chuyen tien
        refunds[msg.sender] = 0;
        msg.sender.transfer(amount);

        emit RefundWithdrawn(msg.sender, amount);
    }

    function endAuction() public onlyOwner {
        require(auctionEndTime > 0, "auction not started");
        require(now >= auctionEndTime, "auction not yet ended");
        require(!ended, "auction already ended");

        ended = true;
        emit AuctionEnded(highestBidder, highestBid);
    }

    function claimProceeds() public onlyOwner {
        require(ended, "auction not ended");
        uint256 amount = highestBid;
        require(amount > 0, "nothing to claim");

        highestBid = 0;
        msg.sender.transfer(amount);
    }

    function refundOf(address bidder) public view returns (uint256) {
        return refunds[bidder];
    }

}
