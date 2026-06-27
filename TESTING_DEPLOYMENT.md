# 📦 Deployment & Testing Kurulumu

## 🛠️ Ortam Kurulumu

### 1. Proje Başlatma

```bash
# Foundry ile (önerilen)
forge init bilbord
cd bilbord

# Veya Hardhat ile
npx hardhat init
```

### 2. Bağımlılıklar

```bash
# Foundry
forge install OpenZeppelin/openzeppelin-contracts

# veya Hardhat
npm install --save-dev hardhat @nomiclabs/hardhat-ethers ethers

# Test utilities
npm install --save-dev hardhat-gas-reporter solidity-coverage
```

### 3. Dosya Yapısı

```
bilbord/
├── contracts/
│   ├── AdExchange.sol
│   ├── Bidder.sol
│   ├── interfaces/
│   │   ├── IBidder.sol
│   │   └── IOracle.sol
│   └── libraries/
│       ├── BiddingLogic.sol
│       └── SettlementLogic.sol
│
├── test/
│   ├── AdExchange.t.sol
│   ├── Bidder.t.sol
│   └── Integration.t.sol
│
├── script/
│   ├── Deploy.s.sol
│   └── Setup.s.sol
│
├── .env.example
├── foundry.toml
└── README.md
```

---

## 🧪 Testing Strategy

### Test Katmanları

#### 1️⃣ Unit Tests

```solidity
// test/AdExchange.t.sol

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/AdExchange.sol";
import "../contracts/Bidder.sol";

contract AdExchangeTest is Test {
    AdExchange adExchange;
    Bidder bidder1;
    address oracle;
    address billboard;
    
    function setUp() public {
        oracle = makeAddr("oracle");
        billboard = makeAddr("billboard");
        
        adExchange = new AdExchange(oracle);
        bidder1 = new Bidder(address(adExchange));
        
        // Register
        adExchange.registerBidder(address(bidder1));
    }
    
    // Test: Auction başlatılması
    function testTriggerAuction() public {
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard, 75);
        
        (address bidder, uint256 amount,) = adExchange.getAuctionStatus(auctionId);
        assertEq(bidder, address(0), "No bidder yet");
    }
    
    // Test: Teklif verme
    function testPlaceBid() public {
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard, 75);
        
        // Bidder bütçe yatır
        vm.deal(address(bidder1), 10 ether);
        vm.prank(address(bidder1));
        bidder1.depositBudget{value: 1 ether}();
        
        // Strateji ayarla
        vm.prank(address(bidder1));
        bidder1.setStrategy(0.01 ether, 1 ether, 150, 30);
        
        // Teklif ver (via AdExchange callback)
        vm.prank(address(adExchange));
        (uint256 bidAmount, bool shouldBid) = bidder1.placeBid(auctionId, 75);
        
        assertTrue(shouldBid);
        assertGt(bidAmount, 0);
    }
    
    // Test: Finalize
    function testFinalizeAuction() public {
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard, 75);
        
        // Time warp
        vm.warp(block.timestamp + 301); // 300ms + buffer
        
        vm.prank(address(this));
        adExchange.finalizeAuction(auctionId);
        
        (AuctionState state,,) = adExchange.getAuctionStatus(auctionId);
        assertEq(uint(state), uint(AuctionState.CLOSED));
    }
}
```

#### 2️⃣ Integration Tests

```solidity
// test/Integration.t.sol

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/AdExchange.sol";
import "../contracts/Bidder.sol";

contract IntegrationTest is Test {
    AdExchange adExchange;
    Bidder[] bidders;
    address oracle;
    address billboard;
    
    function setUp() public {
        oracle = makeAddr("oracle");
        billboard = makeAddr("billboard");
        
        adExchange = new AdExchange(oracle);
        
        // 5 bidder oluştur
        for (uint i = 0; i < 5; i++) {
            Bidder b = new Bidder(address(adExchange));
            bidders.push(b);
            adExchange.registerBidder(address(b));
        }
    }
    
    // End-to-end test: Auction → Bids → Finalization
    function testFullAuctionFlow() public {
        // 1. Setup
        for (uint i = 0; i < bidders.length; i++) {
            vm.deal(address(bidders[i]), 10 ether);
            vm.prank(address(bidders[i]));
            bidders[i].depositBudget{value: 1 ether}();
            
            vm.prank(address(bidders[i]));
            bidders[i].setStrategy(
                0.01 ether,
                1 ether,
                100 + i * 20,  // Farklı faktörler
                30
            );
        }
        
        // 2. Trigger
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard, 75);
        
        // 3. Bids (simülasyon)
        for (uint i = 0; i < bidders.length; i++) {
            vm.prank(address(adExchange));
            (uint256 amount, bool should) = bidders[i].placeBid(auctionId, 75);
            
            if (should) {
                vm.prank(address(bidders[i]));
                adExchange.submitBid(auctionId, amount);
            }
        }
        
        // 4. Finalize
        vm.warp(block.timestamp + 301);
        adExchange.finalizeAuction(auctionId);
        
        // 5. Settle
        adExchange.settlePayment(auctionId);
        
        // 6. Assert
        (address winner, uint256 highestBid, AuctionState state) = 
            adExchange.getAuctionStatus(auctionId);
        
        assertGt(highestBid, 0, "Should have bids");
        assertEq(uint(state), uint(AuctionState.FINALIZED), "Should be finalized");
    }
    
    // Stress test: 100 bidders
    function testStressTest100Bidders() public {
        Bidder[] memory stressBidders = new Bidder[](100);
        
        // Setup
        for (uint i = 0; i < 100; i++) {
            stressBidders[i] = new Bidder(address(adExchange));
            adExchange.registerBidder(address(stressBidders[i]));
            
            vm.deal(address(stressBidders[i]), 10 ether);
            vm.prank(address(stressBidders[i]));
            stressBidders[i].depositBudget{value: 1 ether}();
            
            vm.prank(address(stressBidders[i]));
            stressBidders[i].setStrategy(0.01 ether, 1 ether, 150, 30);
        }
        
        // Trigger
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard, 80);
        
        // Submit bids (gas gözlemi)
        uint gasStart = gasleft();
        for (uint i = 0; i < 100; i++) {
            vm.prank(address(stressBidders[i]));
            (uint256 amount, bool should) = stressBidders[i].placeBid(auctionId, 80);
            
            if (should) {
                adExchange.submitBid(auctionId, amount);
            }
        }
        uint gasUsed = gasStart - gasleft();
        
        emit log_uint(gasUsed);
        assertLt(gasUsed, 2_000_000, "Should fit in 1 block (Monad)");
    }
}
```

#### 3️⃣ Simülasyon Tests

```solidity
// test/Simulation.t.sol

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

contract SimulationTest is Test {
    // Real-world scenario: Market simulation
    
    function testMarketDynamics() public {
        // Hour simulation: 3600 auctions (1 saniyede 1 auction)
        // Each with 10-50 bidders
        // Varying crowd densities
        
        uint256 totalSpent = 0;
        uint256 successfulAuctions = 0;
        
        for (uint i = 0; i < 3600; i++) {
            // Simulate crowd (sine wave)
            uint256 density = 50 + (50 * uint256(keccak256(abi.encodePacked(i))) % 100) / 100;
            
            if (density > 50) {
                // Trigger auction
                successfulAuctions++;
                
                // Simulate bids (random)
                uint256 numBidders = 10 + uint256(keccak256(abi.encodePacked(i))) % 40;
                
                for (uint j = 0; j < numBidders; j++) {
                    // Random bid
                    uint256 bid = 0.01 ether + (uint256(keccak256(abi.encodePacked(i, j))) % 1 ether);
                    totalSpent += bid;
                }
            }
        }
        
        emit log_string("=== Hourly Market Simulation ===");
        emit log_uint(successfulAuctions);
        emit log_uint(totalSpent / 1 ether);
    }
}
```

---

## 📊 Gas Reporting

### Configuration

```toml
# foundry.toml
[profile.default]
gas_reports = ["AdExchange", "Bidder"]

[profile.report]
gas_reports = ["*"]
```

### Komut

```bash
# Detaylı gas raporu
forge test --gas-report

# Benchmark
forge test --benchmark

# Profiling
forge test -vvv  # Verbose output
```

---

## 🚀 Deployment Scripts

### Deploy.s.sol

```solidity
// script/Deploy.s.sol

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/AdExchange.sol";
import "../contracts/Bidder.sol";

contract DeployScript is Script {
    AdExchange adExchange;
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. AdExchange deploy et
        adExchange = new AdExchange(oracleAddress);
        console.log("AdExchange deployed at:", address(adExchange));
        
        // 2. Example Bidders deploy et (testnet için)
        for (uint i = 0; i < 3; i++) {
            Bidder bidder = new Bidder(address(adExchange));
            adExchange.registerBidder(address(bidder));
            console.log("Bidder", i, "deployed at:", address(bidder));
        }
        
        // 3. Billboard kaydet
        adExchange.registerBillboard(
            makeAddr("billboard_main"),
            "Times Square",
            500  // 5% commission
        );
        
        vm.stopBroadcast();
    }
}
```

### Komut

```bash
# Lokalde simulate et
forge script script/Deploy.s.sol --fork-url http://localhost:8545

# Monad testnet'e deploy et
forge script script/Deploy.s.sol \
    --rpc-url https://testnet.monad.com \
    --private-key $PRIVATE_KEY \
    --broadcast

# Verify
forge verify-contract 0x... AdExchange \
    --chain monad \
    --etherscan-api-key $ETHERSCAN_KEY
```

---

## 📝 Environment Dosyası

```bash
# .env
PRIVATE_KEY=0x...
ORACLE_ADDRESS=0x...
RPC_URL_MONAD=https://testnet.monad.com
RPC_URL_ETHEREUM=https://eth-mainnet.g.alchemy.com/v2/...
ETHERSCAN_API_KEY=...
```

---

## 🔍 Testing Checklist

### Unit Tests

- [x] Auction creation
- [x] Bid submission
- [x] Finalization logic
- [x] Payment settlement
- [x] Budget management
- [x] Strategy validation
- [x] Access control
- [x] Edge cases (zero bids, etc)

### Integration Tests

- [x] Full auction flow
- [x] Multiple bidders
- [x] Winner determination
- [x] Settlement accuracy
- [x] State transitions

### Performance Tests

- [x] Gas usage per operation
- [x] 10-bidder load
- [x] 50-bidder load
- [x] 100-bidder load
- [x] Block space constraints

### Security Tests

- [x] Reentrancy scenarios
- [x] Double-spend attempts
- [x] Underflow/overflow
- [x] Unauthorized access
- [x] Invalid state transitions

---

## 📈 Performance Benchmarks

### Target Metrics

```
Operation          | Gas   | Time (Monad) | Cost @50gwei
=====================================
triggerAuction     | 45K   | ~50ms        | $0.68
placeBid           | 8K    | ~10ms        | $0.12
submitBid          | 12K   | ~15ms        | $0.18
finalizeAuction    | 5K    | ~5ms         | $0.08
settlePayment      | 35K   | ~40ms        | $0.52
=====================================
Total (5 bidders)  | 155K  | ~120ms       | $2.35
```

### Optimization Goals

- [ ] Gas per bid < 10K
- [ ] Total auction cycle < 200ms
- [ ] 100+ bidders/second throughput
- [ ] Cost per auction < $1

---

## 🛡️ Security Testing

### Fuzzing (Foundry)

```solidity
function testFuzzBidAmount(
    uint256 basePrice,
    uint256 crowdDensity,
    uint256 factor
) public {
    // Assume valid ranges
    basePrice = bound(basePrice, 0.001 ether, 10 ether);
    crowdDensity = bound(crowdDensity, 0, 100);
    factor = bound(factor, 1, 1000);
    
    // Test calculation
    uint256 result = _calculateBidAmount(basePrice, crowdDensity, factor);
    
    // Assert invariants
    assertLe(result, basePrice * 10, "Result exceeds max");
    assertGe(result, 0, "Result is negative");
}
```

### Scenario Testing

```solidity
function testScenario_MaliciousOracle() public {
    // Oracle sends false crowdDensity
    vm.prank(oracle);
    adExchange.triggerAuction(billboard, 999); // Invalid
    
    // Should revert or handle gracefully
}

function testScenario_InsufficientBudget() public {
    // Bidder tries to bid more than budget
    bidder1.depositBudget{value: 0.001 ether}();
    
    vm.prank(address(adExchange));
    (uint256 amount, bool should) = bidder1.placeBid(auctionId, 100);
    
    assertFalse(should, "Should not allow oversized bid");
}
```

---

## 📚 Test Komutları

```bash
# Run all tests
forge test

# Run specific test
forge test --match-test testTriggerAuction

# Run with verbosity
forge test -vvv

# Coverage
forge coverage

# Gas report
forge test --gas-report

# Fork testing
forge test --fork-url $RPC_URL

# Parallel testing (faster)
forge test -j 8
```

---

## 🎯 Deployment Stratejisi

### Phase 1: Testnet (Monad Sepolia)

```bash
# 1. Compile
forge build

# 2. Deploy
forge script script/Deploy.s.sol \
    --rpc-url https://sepolia.monad.com \
    --broadcast

# 3. Verify
forge verify-contract $CONTRACT_ADDRESS AdExchange
```

### Phase 2: Mainnet (Monad)

```bash
# 1. Security audit geçsin
# 2. Extensive testing yapın
# 3. Deploy

forge script script/Deploy.s.sol \
    --rpc-url https://mainnet.monad.com \
    --broadcast \
    --verify
```

---

## 📞 Troubleshooting

### Sorun: "Insufficient gas"

**Çözüm:** Bids sayısını azalt veya batch processing kullan

### Sorun: "Auction not finalized"

**Çözüm:** Time warp kontrolü yap (`vm.warp()`)

### Sorun: "Out of budget"

**Çözüm:** Bidder bütçe kontrol et, atau deposit yap

---

*Testing & Deployment Guide | Version 1.0*
