# FreshFoodSupplyChain  
**License:** MIT  
**Solidity version:** ^0.8.19  
**File name:** `FreshFoodSupplyChain.sol`  
**Contract:** `FreshFoodSupplyChain`

## Overview
`FreshFoodSupplyChain` is Solidity smart contract for tracking perishable produce (fresh food) across a supply chain — Farmer → Transporter → Warehouse → Retailer → Consumer.

Key capabilities:
- Role-based user registration (Farmer, Transporter, Warehouse, Retailer, Consumer)
- Product lifecycle and ownership transfer
- Environmental logging (temperature, humidity) with automatic violation detection
- Simple escrow mechanism: buyer pays contract; funds released to seller after buyer confirms receipt
- On-chain transaction logs and events for auditing

## Files
- `FreshFoodSupplyChain.sol` — the main smart contract.
- (Optional) `README.md` — this file.

## Requirements
- Solidity compiler `^0.8.19`
- Remix IDE (web) or Hardhat/Foundry local environment for development/testing
- MetaMask or another Web3 wallet for interacting with deployed contract

## Quick Remix deployment
1. Open [Remix](https://remix.ethereum.org).
2. Create a new file `FreshFoodSupplyChain.sol` and paste the contract code.
3. Under `Solidity Compiler` choose `0.8.19+` and compile.
4. Under `Deploy & Run Transactions` choose an environment (e.g., JavaScript VM for quick testing).
5. Deploy the contract — the deploying account becomes `admin`.

## Typical workflow / example usage
1. **Register users (admin only)**
   - `registerUser(address userAddr, Role role, string name)`
   - Roles: `0=None`, `1=Farmer`, `2=Transporter`, `3=Warehouse`, `4=Retailer`, `5=Consumer`.
2. **Create product (Farmer)**  
   - `createProduct(pid, name, description, expiry, priceWei, minTemp, maxTemp, batch, offChainHash)`
   - Example: `pid = "P-001"`, `expiry = block.timestamp + 30 days`, `priceWei = 1 ether`
3. **List for sale (owner)**
   - `listForSale(pid, priceWei)`
4. **Buyer pays escrow**
   - `payForProduct(pid)` — call with `msg.value == priceWei`
5. **Seller marks shipped**
   - `markShipped(pid)` — only current owner (seller)
6. **Buyer confirms receipt**
   - `confirmReceived(pid)` — transfers ownership to buyer and releases escrow to seller
7. **Environmental logging**
   - `logEnvironment(pid, temperature, humidity, location)` — any registered user can log; violation changes product state to `Violated`
8. **Admin actions**
   - `refundBuyer(pid, buyer)` — refunds escrow in disputes
   - `recallProduct(pid, reason)`

## Important functions & events
- `registerUser`, `unregisterUser` (admin)
- `createProduct`, `listForSale`, `payForProduct`, `markShipped`, `confirmReceived`
- `logEnvironment`
- Events: `UserRegistered`, `ProductCreated`, `ProductListed`, `ProductPaid`, `ProductShipped`, `ProductReceived`, `FundsReleased`, `FundsRefunded`, `EnvLogged`, `TemperatureViolation`, `ProductRecalled`

## Gas & security notes
- Escrow balances are stored per product; when releasing/refunding, contract uses `.call{value: amount}("")` — always check returned `bool` and handle failures.
- Avoid storing large arrays on-chain if the assignment scales; `envLogs` and `txns` arrays can grow large and are gas-costly — acceptable for assignment/testing but consider off-chain logging + on-chain hash for production.
- Use access control carefully — the admin can refund and recall; choose admin account responsibly.
- Input validation: the contract checks ranges for temperature and expiry but you should also validate off-chain data integrity.

## Testing suggestions
- Use the Remix JS VM to test flows with multiple accounts:
  - Account[0] = admin
  - Account[1] = Farmer
  - Account[2] = Retailer (buyer)
- Test the happy path: create → list → pay → ship → receive (funds go to seller).
- Test edge cases:
  - Temperature violation sets `Violated` state and prevents listing/transfer.
  - Refund path: admin refunds buyer if `confirmReceived` isn't called.
  - Invalid expiry / invalid price / invalid role actions.

## Extensions (optional if you want to expand)
- Integrate OpenZeppelin `Ownable` and role-based `AccessControl`.
- Replace ETH escrow with ERC20 token payments (use `SafeERC20`).
- Save only hashed environmental summary on-chain (store full logs off-chain).
- Add event-based off-chain indexing (The Graph) to query logs cheaply.

## Grading checklist (suggested for submission)
- Include `FreshFoodSupplyChain.sol` and `README.md`.
- Provide a short walkthrough in README showing addresses & example inputs you used in Remix.
- Show a few transaction screenshots from Remix (create, pay, ship, confirm).
- Explain any deviations or extra features you added.

## License
MIT — feel free to adapt for your assignment.

