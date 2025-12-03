// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title FreshFoodSupplyChain
/// @author ChatGPT
/// @notice Tracks perishable produce from farmer -> consumer with escrow and environmental logging
contract FreshFoodSupplyChain {

    // --- Roles & Status ---
    enum Role { None, Farmer, Transporter, Warehouse, Retailer, Consumer }
    enum ProductState { Created, ForSale, Paid, Shipped, Received, Delivered, Recalled, Violated }

    // --- Data Structures ---
    struct User {
        address addr;
        Role role;
        string name;
        bool registered;
    }

    struct Product {
        string id;
        string name;
        string description;
        address payable owner;        // current owner (seller while listed)
        address payable seller;       // original seller of current listing
        uint256 createdAt;
        uint256 expiry;
        uint256 priceWei;             // listing price in wei
        int256 minTemp;
        int256 maxTemp;
        ProductState state;
        string batch;
        string offChainHash;
        bool exists;
    }

    struct EnvLog {
        int256 temperature;
        int256 humidity; // optional
        uint256 timestamp;
        address loggedBy;
        string location;
    }

    struct Txn {
        address from;
        address to;
        uint256 timestamp;
        ProductState state;
        string remark;
    }

    // --- State ---
    address public admin;
    mapping(address => User) public users;
    mapping(string => Product) private products;
    mapping(string => EnvLog[]) private envLogs;
    mapping(string => Txn[]) private txns;
    mapping(string => uint256) public escrowBalance; // productId -> wei held in escrow

    // events
    event UserRegistered(address indexed user, Role role, string name);
    event ProductCreated(string indexed pid, string name, address indexed owner);
    event ProductListed(string indexed pid, uint256 priceWei);
    event ProductPaid(string indexed pid, address indexed buyer, uint256 amount);
    event ProductShipped(string indexed pid, address indexed by);
    event ProductReceived(string indexed pid, address indexed by);
    event FundsReleased(string indexed pid, address indexed to, uint256 amount);
    event FundsRefunded(string indexed pid, address indexed to, uint256 amount);
    event EnvLogged(string indexed pid, int256 temp, int256 humidity, address indexed by);
    event TemperatureViolation(string indexed pid, int256 temp, int256 humidity);
    event ProductRecalled(string indexed pid, string reason);

    // modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }
    modifier onlyRegistered() {
        require(users[msg.sender].registered, "Not registered");
        _;
    }
    modifier onlyRole(Role r) {
        require(users[msg.sender].role == r, "Unauthorized role");
        _;
    }
    modifier productExists(string memory pid) {
        require(products[pid].exists, "Product not found");
        _;
    }
    modifier onlyProductOwner(string memory pid) {
        require(products[pid].owner == payable(msg.sender), "Not product owner");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    // --------------------
    // User management
    // --------------------
    function registerUser(address _addr, Role _role, string calldata _name) external onlyAdmin {
        require(_addr != address(0), "Zero address");
        require(_role != Role.None, "Choose a valid role");
        require(!users[_addr].registered, "Already registered");
        users[_addr] = User({ addr: _addr, role: _role, name: _name, registered: true });
        emit UserRegistered(_addr, _role, _name);
    }

    function unregisterUser(address _addr) external onlyAdmin {
        require(users[_addr].registered, "Not registered");
        delete users[_addr];
    }

    // --------------------
    // Product lifecycle
    // --------------------
    function createProduct(
        string calldata pid,
        string calldata name,
        string calldata description,
        uint256 expiry,
        uint256 priceWei,
        int256 minTemp,
        int256 maxTemp,
        string calldata batch,
        string calldata offChainHash
    ) external onlyRegistered onlyRole(Role.Farmer) {
        require(!products[pid].exists, "pid exists");
        require(expiry > block.timestamp, "Invalid expiry");
        require(minTemp <= maxTemp, "Invalid temp range");

        products[pid] = Product({
            id: pid,
            name: name,
            description: description,
            owner: payable(msg.sender),
            seller: payable(msg.sender),
            createdAt: block.timestamp,
            expiry: expiry,
            priceWei: priceWei,
            minTemp: minTemp,
            maxTemp: maxTemp,
            state: ProductState.Created,
            batch: batch,
            offChainHash: offChainHash,
            exists: true
        });

        txns[pid].push(Txn({ from: address(0), to: msg.sender, timestamp: block.timestamp, state: ProductState.Created, remark: "Created" }));
        emit ProductCreated(pid, name, msg.sender);
    }

    /// list product for sale by current owner
    function listForSale(string calldata pid, uint256 priceWei) external onlyRegistered productExists(pid) onlyProductOwner(pid) {
        Product storage p = products[pid];
        require(p.state != ProductState.Violated && p.state != ProductState.Recalled, "Not listable");
        p.priceWei = priceWei;
        p.seller = p.owner;
        p.state = ProductState.ForSale;
        txns[pid].push(Txn({ from: msg.sender, to: msg.sender, timestamp: block.timestamp, state: ProductState.ForSale, remark: "Listed for sale" }));
        emit ProductListed(pid, priceWei);
    }

    /// buyer pays escrow to contract (exact price)
    function payForProduct(string calldata pid) external payable onlyRegistered productExists(pid) {
        Product storage p = products[pid];
        require(p.state == ProductState.ForSale, "Not for sale");
        require(msg.value == p.priceWei, "Send exact listing price");
        require(users[msg.sender].role == Role.Retailer || users[msg.sender].role == Role.Consumer || users[msg.sender].role == Role.Warehouse, "Buyer role not permitted");

        // accept payment into escrow
        escrowBalance[pid] += msg.value;
        p.state = ProductState.Paid;
        // buyer becomes the "intended owner", but ownership transfer only on receipt
        txns[pid].push(Txn({ from: msg.sender, to: p.owner, timestamp: block.timestamp, state: ProductState.Paid, remark: "Paid into escrow" }));
        emit ProductPaid(pid, msg.sender, msg.value);
    }

    /// seller (current owner) marks shipped
    function markShipped(string calldata pid) external onlyRegistered productExists(pid) onlyProductOwner(pid) {
        Product storage p = products[pid];
        require(p.state == ProductState.Paid || p.state == ProductState.ForSale, "Cannot ship yet");
        p.state = ProductState.Shipped;
        txns[pid].push(Txn({ from: msg.sender, to: msg.sender, timestamp: block.timestamp, state: ProductState.Shipped, remark: "Shipped" }));
        emit ProductShipped(pid, msg.sender);
    }

    /// receiver confirms receipt -> ownership transfer + release funds
    /// buyer (who previously paid) calls this to claim & release funds to seller
    function confirmReceived(string calldata pid) external onlyRegistered productExists(pid) {
        Product storage p = products[pid];
        require(p.state == ProductState.Shipped, "Not shipped");
        // buyer must have paid escrow (escrowBalance>0)
        require(escrowBalance[pid] > 0, "No escrow found");

        address payable seller = p.seller;
        uint256 amount = escrowBalance[pid];

        // transfer ownership to msg.sender
        address payable previousOwner = p.owner;
        p.owner = payable(msg.sender);
        p.state = ProductState.Received;

        // clear escrow then send funds to seller
        escrowBalance[pid] = 0;

        (bool ok,) = seller.call{ value: amount }("");
        require(ok, "Payout failed");

        txns[pid].push(Txn({ from: previousOwner, to: msg.sender, timestamp: block.timestamp, state: ProductState.Received, remark: "Received by buyer; funds released" }));
        emit ProductReceived(pid, msg.sender);
        emit FundsReleased(pid, seller, amount);
    }

    /// admin can refund escrow to a buyer in a dispute
    function refundBuyer(string calldata pid, address payable buyer) external onlyAdmin productExists(pid) {
        uint256 bal = escrowBalance[pid];
        require(bal > 0, "No escrow to refund");
        escrowBalance[pid] = 0;
        (bool ok,) = buyer.call{ value: bal }("");
        require(ok, "Refund failed");
        txns[pid].push(Txn({ from: address(this), to: buyer, timestamp: block.timestamp, state: ProductState.ForSale, remark: "Refunded by admin" }));
        emit FundsRefunded(pid, buyer, bal);
    }

    /// mark product recalled
    function recallProduct(string calldata pid, string calldata reason) external onlyAdmin productExists(pid) {
        Product storage p = products[pid];
        p.state = ProductState.Recalled;
        txns[pid].push(Txn({ from: msg.sender, to: p.owner, timestamp: block.timestamp, state: ProductState.Recalled, remark: reason }));
        emit ProductRecalled(pid, reason);
    }

    // --------------------
    // Environmental logging
    // --------------------
    function logEnvironment(string calldata pid, int256 temperature, int256 humidity, string calldata location) external onlyRegistered productExists(pid) {
        Product storage p = products[pid];
        EnvLog memory l = EnvLog({ temperature: temperature, humidity: humidity, timestamp: block.timestamp, loggedBy: msg.sender, location: location });
        envLogs[pid].push(l);
        emit EnvLogged(pid, temperature, humidity, msg.sender);

        // violation detection
        if (temperature < p.minTemp || temperature > p.maxTemp) {
            p.state = ProductState.Violated;
            emit TemperatureViolation(pid, temperature, humidity);
        }
    }

    // --------------------
    // View helpers
    // --------------------
    function getProduct(string calldata pid) external view productExists(pid) returns (Product memory) {
        return products[pid];
    }

    function getEnvLogs(string calldata pid) external view productExists(pid) returns (EnvLog[] memory) {
        return envLogs[pid];
    }

    function getTxns(string calldata pid) external view productExists(pid) returns (Txn[] memory) {
        return txns[pid];
    }

    // --------------------
    // Admin helpers
    // --------------------
    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Zero address");
        admin = newAdmin;
    }

    // receive fallback so contract can accept refunds, tests
    receive() external payable {}
    fallback() external payable {}
}
