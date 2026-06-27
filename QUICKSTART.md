# 🚀 Hızlı Başlangıç Rehberi

## Proje Yapısı

```
bilbord/
├── contracts/
│   ├── AdExchange.sol          ← Master açık artırma kontratı
│   ├── Bidder.sol              ← Marka bidder template'i
│   ├── interfaces/
│   │   ├── IBidder.sol         ← Bidder arayüzü
│   │   └── IOracle.sol         ← Oracle arayüzü
│   └── libraries/
│       └── BiddingLogic.sol    ← Gas-optimized yardımcılar
│
├── ARCHITECTURE.md             ← Detaylı sistem mimarisi
├── DEPLOYMENT.md               ← Deploy adımları
└── TESTING.md                  ← Test stratejileri
```

## Temel Akış

### 1. Deployment Sırası

```bash
# 1. AdExchange deploy et
adExchange = deploy AdExchange(oracleAddress)

# 2. Marka Bidder'ları deploy et
bidder1 = deploy Bidder(adExchange.address)
bidder2 = deploy Bidder(adExchange.address)

# 3. AdExchange'de bidder'ları kaydet
adExchange.registerBidder(bidder1.address)
adExchange.registerBidder(bidder2.address)

# 4. Billboard'ları kaydet
adExchange.registerBillboard(billboardId, location, commissionFee)
```

### 2. Normal Operasyon

```
Oracle (Off-Chain)
    ↓ (kalabalık > 50%)
triggerAuction(billboardId, crowdDensity)
    ↓
[Bidders receive requestBidFromBidder]
    ↓ (paralel)
placeBid() → calculateBidAmount() → submitBid()
    ↓
[Wait 300ms]
    ↓
finalizeAuction(auctionId)
    ↓
settlePayment(auctionId)
    ↓
Kazanan: 2. fiyat öder
```

## Önemli Sayılar

| Parametre | Değer | Neden |
|-----------|-------|-------|
| Auction Duration | 100-500ms | Monad block time |
| Crowd Density Threshold | 50% | ROI cut-off |
| Reserve Price | 0.005 ETH | Spam prevention |
| Max Bid Factor | 10x | Bid amplification |
| Commission Fee | 5-10% (500-1000 bps) | Platform revenue |
| Min Bid Amount | 0.0001 ETH | Dust prevention |

## Gas Tahminleri

| Operasyon | Gas | Yorum |
|-----------|-----|-------|
| triggerAuction | 45,000 | Auction create + emit |
| placeBid (via requestBid) | 8,000 | Light write |
| submitBid | 12,000 | Array push + mapping update |
| finalizeAuction | 5,000 | State update |
| settlePayment | 35,000 | Callbacks + transfers |
| **Toplam (1 auction)** | **105,000** | ~0.3 USD @ 50 gwei |

## Teklif Hesaplama Örneği

```javascript
// Frontend'de göstermek için

function calculateBidAmount(strategy, crowdDensity, billboardMultiplier = 1.0) {
    const baseBid = strategy.basePrice;
    const densityFactor = crowdDensity / 100;
    const amountFactor = strategy.crowdDensityFactor / 100;
    
    let bid = baseBid * densityFactor * amountFactor * billboardMultiplier;
    
    // Sınırlandır
    bid = Math.min(bid, strategy.maxPrice);
    bid = Math.max(bid, strategy.basePrice * 0.1); // Min bid
    
    return bid;
}

// Örnek
calculateBidAmount(
    { basePrice: 0.01, maxPrice: 1, crowdDensityFactor: 150 },
    75,  // 75% yoğunluk
    1.2  // Premium location
)
// = 0.01 * 0.75 * 1.5 * 1.2 = 0.0135 ETH
```

## Debugging Tips

### Auction'u test etmek:

```solidity
// Test script
function testAuctionFlow() public {
    // 1. Setup
    bytes32 auctionId = adExchange.triggerAuction(billboard, 75);
    
    // 2. Kontrol et
    (address bidder, uint256 amount,) = adExchange.getAuctionStatus(auctionId);
    assertEq(bidder, address(0)); // Henüz kazanan yok
    
    // 3. Teklif ver
    vm.prank(bidder1);
    bidder1.placeBid(auctionId, 75); // → otomatik submitBid çağırır
    
    // 4. Sonlandır
    vm.warp(block.timestamp + 301); // 300ms + 1
    adExchange.finalizeAuction(auctionId);
    
    // 5. Ödeme
    adExchange.settlePayment(auctionId);
    
    // 6. Kontrol
    assertEq(adExchange.auctionSettlements(auctionId), expectedAmount);
}
```

## İçinde Yaygın Hatalar

### ❌ HATA 1: Auction zamanını ms cinsinden yönetmek

```solidity
// HATA
auction.duration = 300;  // ms (ama block.timestamp saniye!)
require(block.timestamp >= auction.startTime + auction.duration);
// Bu sadece 300 saniye sonra doğru olur!
```

**FİX:**
```solidity
auction.duration = 300; // ms mantıksal olarak
// finalizeAuction'da:
require(block.timestamp >= auction.startTime + (auction.duration / 1000));
// Veya ms'yi saniyeye çevir:
auction.durationInSeconds = (duration * 1000) / 1000; // 300ms = 0.3s
```

### ❌ HATA 2: Teklifleri array'de toplamak

```solidity
// HATA - O(n) iteration
function findWinner() external view {
    for (uint i = 0; i < bids.length; i++) {  // Maliyetli!
        // ...
    }
}

// FİX - O(1) tracking
highestBidAmount = bidAmount; // submitBid'de update et
```

### ❌ HATA 3: Bütçeyi tekrar tahsis etme

```solidity
// HATA
placeBid() {
    budget.spent += bidAmount;
    // Ardından:
    onAuctionLost() {
        budget.spent -= bidAmount; // Ama başka bir auction'da harcandı?
    }
}

// FİX
placeBid() {
    auctionBudgetAllocation[auctionId] = bidAmount; // Per-auction track
}

onAuctionLost() {
    delete auctionBudgetAllocation[auctionId]; // Serbest bırak
}
```

## Sonraki Adımlar

1. ✅ **Görev 1:** Sistem Tasarımı ← **TÜM**
2. 📋 **Görev 2:** Core implementasyon (triggerAuction + placeBid + finalizeAuction)
3. 🧪 **Görev 3:** Hardhat/Foundry test suite
4. 📊 **Görev 4:** Oracle mock + integration
5. 🔒 **Görev 5:** Security audit + optimization
6. 🚀 **Görev 6:** Testnet deployment

---

## Faydalı Kaynaklar

- **Monad EVM Docs:** https://docs.monadlabs.com/
- **Solidity Best Practices:** https://docs.soliditylang.org/en/latest/security-considerations.html
- **OpenZeppelin Contracts:** https://github.com/OpenZeppelin/openzeppelin-contracts
- **Foundry Testing:** https://book.getfoundry.sh/
- **Auction Theory:** https://en.wikipedia.org/wiki/Vickrey_auction

---

## İletişim & Sorular

Kod tasarımı hakkında sorular? Bu dosyadaki spesifik örnekleri referans al!

**Önemli:** Tüm struct'lar ve function signature'lar `AdExchange.sol` ve `Bidder.sol`'da bulunabilir.
