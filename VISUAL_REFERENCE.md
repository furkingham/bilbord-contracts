# 📊 Visual Overview & Quick Reference

## System Timeline

```
SECOND RESOLUTION:
├─ 0ms    Oracle detects crowd
├─ 50ms   triggerAuction() → Auction ACTIVE
├─ 100ms  Bidder1 placeBid() → 0.0135 ETH
├─ 150ms  Bidder2 placeBid() → 0.0120 ETH
├─ 200ms  Bidder3 placeBid() → 0.0118 ETH
├─ 350ms  Time expired
├─ 360ms  finalizeAuction() → CLOSED
│         Winner: Bidder1 (0.0135 ETH bid)
│         Second: Bidder2 (0.0120 ETH)
├─ 370ms  settlePayment()
│         Bidder1 pays: 0.0120 ETH (2nd price)
│         Platform fee: 0.0006 ETH
│         Billboard owner: 0.0114 ETH
└─ 400ms  Ready for next auction
```

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    COMPLETE DATA FLOW                           │
└─────────────────────────────────────────────────────────────────┘

INPUT (Off-Chain):
  Kalabalık Yoğunluğu: 0-100%
      ↓
Oracle Service → Eşik Kontrolü (>50%?) → triggerAuction()
      ↓
AdExchange Event: AuctionStarted ────→ External listeners
      ↓
Parallel Bidder Callbacks:
  ├─ Bidder1.placeBid(auctionId, crowdDensity)
  ├─ Bidder2.placeBid(auctionId, crowdDensity)
  └─ BidderN.placeBid(auctionId, crowdDensity)
      ↓
Strategy Execution (inside Bidder):
  basePrice × (density/100) × (factor/100) × preference
      ↓
Budget Check:
  if (calculatedBid > unallocatedBalance) → return (0, false)
  else → reserve budget
      ↓
submitBid() for each bidder
  ├─ Update Auction.highestBidder
  ├─ Update Auction.highestBidAmount
  ├─ Update Auction.secondHighestBid
  └─ Emit BidPlaced event
      ↓
Wait 300ms
      ↓
finalizeAuction() → State = CLOSED
      ↓
settlePayment():
  1. settlementAmount = secondHighestBid
  2. platformFee = settlementAmount × 5%
  3. billboardPayment = settlementAmount - platformFee
  4. Transfer to winner (via balance tracking)
  5. Transfer to billboard owner
  6. onAuctionWon() callback to winner
  7. onAuctionLost() callbacks to losers
      ↓
OUTPUT:
  ├─ Winner notification
  ├─ Loser notifications
  ├─ Platform balance +platformFee
  ├─ Billboard balance +billboardPayment
  └─ Next auction ready
```

## Struct Memory Layout

```
AUCTION STRUCT (Optimized):
┌────────────────────────────────────────────────────────────────┐
│ Slot 0: bytes32 auctionId              (32 bytes)             │
├────────────────────────────────────────────────────────────────┤
│ Slot 1: address highestBidder (20) + state (1) + bool (1)     │
│         (10 bytes padding)                                     │
├────────────────────────────────────────────────────────────────┤
│ Slot 2: uint256 highestBidAmount       (32 bytes)             │
├────────────────────────────────────────────────────────────────┤
│ Slot 3: uint256 secondHighestBid       (32 bytes)             │
├────────────────────────────────────────────────────────────────┤
│ Slot 4: uint256 startTime              (32 bytes)             │
├────────────────────────────────────────────────────────────────┤
│ Slot 5: uint256 duration               (32 bytes)             │
├────────────────────────────────────────────────────────────────┤
│ Slot 6: uint256 crowdDensity           (32 bytes)             │
├────────────────────────────────────────────────────────────────┤
│ Slot 7: address billboardId (20) + padding (12)               │
├────────────────────────────────────────────────────────────────┤
│ Slot 8: uint256 reservePrice           (32 bytes)             │
└────────────────────────────────────────────────────────────────┘
TOTAL: 9 slots × 32 bytes = 288 bytes (OK - single storage read)
```

## Key Struct Definitions

### Auction Structure
```javascript
{
  auctionId: bytes32,              // Unique identifier
  startTime: number,               // Unix timestamp
  duration: number,                // Milliseconds (100-500)
  crowdDensity: 0-100,            // Percentage
  
  highestBidder: address,          // Current winner
  highestBidAmount: wei,           // Winning bid
  secondHighestBid: wei,           // 2nd price (Vickrey)
  
  state: INACTIVE|ACTIVE|CLOSED|FINALIZED,
  billboardId: address,            // Which billboard
  reservePrice: wei                // Minimum acceptable
}
```

### BiddingStrategy Structure
```javascript
{
  basePrice: wei,                  // 0.01 ETH typical
  maxPrice: wei,                   // 1 ETH typical
  crowdDensityFactor: 0-1000,     // 150 = 1.5x multiplier
  minCrowdDensity: 0-100,         // 30% minimum threshold
  budgetAllocation: wei,           // Per-auction limit
  isActive: boolean
}
```

### Budget Structure
```javascript
{
  totalBudget: wei,                // Total deposited
  spentAmount: wei,                // Amount used so far
  unallocatedBalance: wei,         // Available to bid
  lastRefillTime: number,          // Daily reset timestamp
  isActive: boolean
}
```

## Gas Cost Breakdown (Detailed)

```
OPERATION: triggerAuction(billboard, 78)
├─ SSTORE auctionId to storage        ~20,000 gas
├─ SSTORE startTime, duration         ~10,000 gas
├─ SSTORE crowdDensity               ~2,000 gas
├─ Loop through bidders (N=5)
│  └─ Call requestBidFromBidder × 5   ~5,000 each = 25,000
├─ Emit AuctionStarted event          ~2,000 gas
└─ Total: ~59,000 gas (actual ~45k with optimizations)

OPERATION: submitBid(auctionId, 0.0117 ether)
├─ SLOAD auction struct              ~2,100 gas
├─ Comparison + update highest       ~3,000 gas
├─ Array push (auctionBids)          ~5,000 gas
├─ Emit BidPlaced event              ~2,000 gas
└─ Total: ~12,100 gas

OPERATION: finalizeAuction(auctionId)
├─ SLOAD + time check                ~2,100 gas
├─ State update                      ~2,900 gas
├─ Emit event                        ~2,000 gas
└─ Total: ~7,000 gas (actual ~5k)

OPERATION: settlePayment(auctionId)
├─ SLOAD auction                     ~2,100 gas
├─ Calculate fees                    ~1,000 gas
├─ Update platform balance           ~3,000 gas
├─ Update billboard balance          ~3,000 gas
├─ Call onAuctionWon callback        ~15,000 gas
├─ Call onAuctionLost × 4            ~12,000 gas (3k each)
├─ Emit PaymentSettled event         ~2,000 gas
└─ Total: ~38,100 gas (actual ~35k)

FULL AUCTION CYCLE (5 bidders):
triggerAuction: 45,000
submitBid × 5: 60,000
finalizeAuction: 5,000
settlePayment: 35,000
────────────────
TOTAL: 145,000 gas (~$2.17 @ 50 gwei, $3000/ETH)
```

## Bidding Strategy Examples

```
SCENARIO 1: Nike (Low-Volume Bidder)
Strategy:
├─ basePrice = 0.005 ETH
├─ maxPrice = 0.1 ETH
├─ crowdDensityFactor = 100 (1x, no amplification)
├─ minCrowdDensity = 40%

Bid calculation @ 75% crowd:
0.005 × 0.75 × 1.0 = 0.00375 ETH

────────────────────────────────

SCENARIO 2: Coca-Cola (Premium Bidder)
Strategy:
├─ basePrice = 0.02 ETH
├─ maxPrice = 1.0 ETH
├─ crowdDensityFactor = 150 (1.5x, amplified)
├─ minCrowdDensity = 20%
├─ billboardPref[timesSquare] = 2.0 (premium location)

Bid calculation @ 75% crowd:
0.02 × 0.75 × 1.5 × 2.0 = 0.045 ETH

────────────────────────────────

SCENARIO 3: Apple (Competitive Bidder)
Strategy:
├─ basePrice = 0.01 ETH
├─ maxPrice = 0.5 ETH
├─ crowdDensityFactor = 200 (2x, aggressive)
├─ minCrowdDensity = 30%
├─ billboardPref[timesSquare] = 1.5 (premium)

Bid calculation @ 75% crowd:
0.01 × 0.75 × 2.0 × 1.5 = 0.0225 ETH

────────────────────────────────

AUCTION RESULT @ 75% CROWD:
1st: Coca-Cola 0.045 ETH  ← WINNER (pays 2nd price)
2nd: Apple     0.0225 ETH ← Sets payment amount
3rd: Nike      0.00375 ETH

Winner pays: 0.0225 ETH (2nd price)
Platform fee (5%): 0.001125 ETH
Billboard owner: 0.021375 ETH
```

## Storage Efficiency Comparison

```
BAD DESIGN (Multiple slots per auction):
┌─────────────────────────────────────┐
│ Slot 0: address highestBidder       │
│ Slot 1: uint256 highestBidAmount    │
│ Slot 2: uint256 secondHighestBid    │
│ Slot 3: uint256 crowdDensity        │
│ Slot 4: AuctionState state          │
│ Slot 5: bool isFinalized            │
└─────────────────────────────────────┘
6 separate slots = 6 SLOAD/SSTORE operations
Gas cost: ~5,000 × 6 = 30,000 gas

GOOD DESIGN (Packed storage):
┌─────────────────────────────────────┐
│ Slot 0: bytes32 auctionId           │
│ Slot 1: address (20) + state (1)    │ ← PACKED
│         + bool (1) + padding (10)   │
│ Slot 2: uint256 highestBidAmount    │
│ Slot 3: uint256 secondHighestBid    │
│ ... more fields ...                 │
└─────────────────────────────────────┘
Multiple fields per slot = Fewer SLOAD/SSTORE
Gas cost: ~5,000 × 2 = 10,000 gas (67% savings!)
```

## Monad Parallelization Benefits

```
ETHEREUM (Sequential):
TX1: Bidder1.placeBid() → 35,000 gas
TX2: Bidder2.placeBid() → 35,000 gas
TX3: Bidder3.placeBid() → 35,000 gas
Total: 3 sequential transactions = 105,000 gas + overhead

MONAD (Parallel):
┌─────────────────────┐
│ Bidder1: submitBid()│ ──→ Update state[bidder1]
├─────────────────────┤
│ Bidder2: submitBid()│ ──→ Update state[bidder2]  (PARALLEL!)
├─────────────────────┤
│ Bidder3: submitBid()│ ──→ Update state[bidder3]  (PARALLEL!)
└─────────────────────┘
Single batch transaction, different state keys
No conflicts → ALL EXECUTE IN PARALLEL
Total: 1 transaction + overhead, 3x faster actual execution!
```

## Vickrey Auction Mechanism

```
STEP-BY-STEP:

1. GATHERING BIDS (Hidden)
   Bidder A thinks: value = $10
   Bidder B thinks: value = $12
   Bidder C thinks: value = $8

2. SUBMITTING BIDS
   Bidder A bids: $10 (truthful)
   Bidder B bids: $12 (truthful)
   Bidder C bids: $8 (truthful)

3. DETERMINING WINNER
   Highest bid = $12 (Bidder B)
   Second-highest = $10 (Bidder A)

4. PAYING (KEY DIFFERENCE)
   Winner (B) pays: SECOND HIGHEST PRICE = $10
   (Not $12!)

5. OUTCOME
   Bidder B:
   ├─ Gets what they wanted ✓
   ├─ Pays exactly $10 (what Bidder A was willing to pay)
   ├─ No regret, no overbid
   └─ Net benefit: $12 - $10 = $2

6. INCENTIVE ANALYSIS
   If Bidder B had bid $15 instead:
   ├─ Still wins (still higher than A's $10)
   ├─ But still pays $10
   ├─ No advantage!
   └─ So why lie? No reason!

CONCLUSION: Truthful bidding is dominant strategy ✓
```

## Security Patterns

```
REENTRANCY PROTECTION:

❌ VULNERABLE:
function settlePayment() {
    (bool success, ) = winner.call{value: amount}("");
    // Attacker can call settlePayment() again here!
    auction.state = FINALIZED;
}

✅ SAFE (Checks-Effects-Interactions):
function settlePayment() {
    require(auction.state == CLOSED);
    
    uint256 paymentAmount = auction.secondHighestBid;
    auction.state = FINALIZED;  // ← State updated FIRST
    
    // Now external call (attacker re-enters, but state already changed)
    (bool success, ) = winner.call{value: paymentAmount}("");
}

DOUBLE-SPEND PREVENTION:

❌ VULNERABLE:
mapping(uint256 => bool) received;
function claimRefund(uint256 auctionId) {
    require(!received[auctionId]);
    // Attacker calls twice in same tx!
    winner.transfer(amount);
    received[auctionId] = true;  // Too late!
}

✅ SAFE:
mapping(uint256 => bool) received;
function claimRefund(uint256 auctionId) {
    require(!received[auctionId]);
    received[auctionId] = true;  // ← Set FIRST
    winner.transfer(amount);     // Then external call
}
```

## File Size & Complexity

```
CONTRACT SIZES (estimated):

AdExchange.sol
├─ Interface definitions: ~200 lines
├─ State variables: ~400 lines
├─ Main functions: ~600 lines
├─ View functions: ~300 lines
├─ Admin functions: ~200 lines
└─ TOTAL: ~1,700 lines
   
   Bytecode: ~20-25 KB (fits in Ethereum limit)
   Deployment gas: ~2.5M gas

Bidder.sol
├─ Structs: ~200 lines
├─ State variables: ~300 lines
├─ Budget functions: ~250 lines
├─ Strategy functions: ~200 lines
├─ Bidding logic: ~400 lines
├─ View functions: ~300 lines
└─ TOTAL: ~1,650 lines
   
   Bytecode: ~18-22 KB
   Deployment gas: ~2.2M gas per instance

TOTAL COMPLEXITY:
├─ Functions: ~45 (public/external)
├─ Events: ~12
├─ Modifiers: ~5
├─ Structs: ~8
└─ Libraries: 0 (inline for efficiency)
```

## Quick Decision Tree

```
QUESTION: "Should we use an array or mapping?"

Is it indexed by integer? (0, 1, 2, ...)
├─ YES  → Array (iteration support needed)
└─ NO   → Mapping (fast lookup by key)

Need to iterate over all items?
├─ YES  → Array + Separate mapping for tracking
└─ NO   → Pure Mapping is fine

Frequent deletions?
├─ YES  → Mapping (no "hole" issues)
└─ NO   → Either works

Expected size?
├─ 1-10 items    → Array is fine
├─ 10-100 items  → Mapping better
└─ 100+ items    → Mapping essential
```

## Deployment Checklist

```
PRE-DEPLOYMENT:
☐ All tests pass
☐ Gas reports reviewed
☐ Security audit completed
☐ Oracle endpoint verified
☐ Testnet fully operational

DEPLOYMENT:
☐ Deploy AdExchange
☐ Deploy Sample Bidders (for testing)
☐ Register Bidders in AdExchange
☐ Register Billboards
☐ Initialize Oracle connection
☐ Configure fee structures

POST-DEPLOYMENT:
☐ Verify contracts on Monad Explorer
☐ Monitor first 10 auctions
☐ Validate payment flows
☐ Check gas consumption
☐ Alert on anomalies

GO-LIVE:
☐ Open to public bidders
☐ Scale from 5 → 50 → 500 billboards
☐ Continuous monitoring
☐ Performance metrics tracking
```

---

This visual reference complements the detailed documentation in:
- **ARCHITECTURE.md** (comprehensive technical details)
- **QUICKSTART.md** (developer guide)
- **TESTING_DEPLOYMENT.md** (implementation guide)

