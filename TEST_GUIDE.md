# 🧪 Test Suite - Foundry ile Çalıştırma Rehberi

## 📋 Test Dosyaları

```
test/
├─ AdExchange.t.sol      (25 tests) - Master kontrat testleri
├─ Bidder.t.sol          (25 tests) - Bidder kontrat testleri  
└─ Integration.t.sol     (10 tests) - Complete flow testleri
```

**Toplam: 60+ test case**

---

## 🚀 Hızlı Başlangıç

### 1. Kurulum (İlk Kez)

```bash
# Foundry kurulumu (eğer yüklü değilse)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Proje klasöründe dependencies yükleme
cd bilbord
forge install

# Contracts derleme
forge build

# Başarılı derleme görmeli
# Kompilasyon hataları olmayacak
```

### 2. Tüm Testleri Çalıştırma

```bash
# ✅ Tüm testleri çalıştır
forge test

# Çıktı:
# Running 60 tests...
# [PASS] ...
# [PASS] ...
# Test Suite: passed 60, failed 0

# Verbose mode (tüm detayları göster)
forge test -vv

# Very verbose (gas sonuçlarını da göster)
forge test -vvv
```

---

## 🎯 Spesifik Test Kategorileri

### AdExchange Tests (25 test)

```bash
# Tüm AdExchange testlerini çalıştır
forge test --match-contract AdExchangeTest

# Sadece Deployment testleri
forge test --match-contract AdExchangeTest --match-test "testDeployment"

# Happy Path testleri
forge test --match-contract AdExchangeTest --match-test "testTriggerAuction\|testPlaceBid\|testResolveAuction\|testSettlePayment"

# Security testleri
forge test --match-contract AdExchangeTest --match-test "Unauthorized\|Closed\|Insufficient"

# Gas benchmarks
forge test --match-contract AdExchangeTest --match-test "Gas"
```

### Bidder Tests (25 test)

```bash
# Tüm Bidder testlerini çalıştır
forge test --match-contract BidderTest

# Budget yönetimi testleri
forge test --match-contract BidderTest --match-test "Budget"

# Strategy testleri
forge test --match-contract BidderTest --match-test "Strategy"

# Bidding logic testleri
forge test --match-contract BidderTest --match-test "placeBid"

# Callback testleri
forge test --match-contract BidderTest --match-test "Callback"

# Security testleri
forge test --match-contract BidderTest --match-test "Unauthorized\|Modifier\|Disabled"
```

### Integration Tests (10 test)

```bash
# Tüm integration testlerini çalıştır
forge test --match-contract IntegrationTest

# Complete flow test
forge test --match-contract IntegrationTest --match-test "Complete"

# Multiple auctions
forge test --match-contract IntegrationTest --match-test "Sequence\|Competition\|Multiple"

# Vickrey mechanism
forge test --match-contract IntegrationTest --match-test "Vickrey"

# Stress tests
forge test --match-contract IntegrationTest --match-test "Stress"
```

---

## 📊 Gaz Analizi

### Gaz Raporu (tüm operasyonlar)

```bash
# Gas report oluştur
forge test --gas-report

# Çıktı örneği:
# | Contract | Method | Calls | Avg | Median |
# |----------|--------|-------|-----|--------|
# | AdExchange | triggerAuction | 10 | 45123 | 45000 |
# | AdExchange | placeBid | 30 | 12456 | 12000 |
# | AdExchange | resolveAuction | 10 | 5234 | 5000 |
# | AdExchange | settlePayment | 10 | 35789 | 35000 |
# | Bidder | placeBid | 20 | 8900 | 8500 |
```

### Spesifik Gaz Benchmarks

```bash
# Sadece gaz benchmark testlerini çalıştır
forge test --match-test "Gas"

# Konsola gaz bilgisini yazdır (console.log kullanılıyor)
forge test --match-test "Gas" -vv
```

---

## 🔍 Detaylı Çıktı Örnekleri

### Verbose Output (-vv)

```bash
forge test --match-test "testCompleteAuctionFlow" -vv

# Çıktı:
# [PASS] IntegrationTest::testCompleteAuctionFlow (gas: 154892)
#   ├─ logs:
#   │  ├─ === TEST 1: Complete Auction Flow ===
#   │  ├─ ✓ Auction triggered: 0x123abc...
#   │  ├─ ✓ Nike bid: 0.00375 ETH
#   │  ├─ ✓ Coca-Cola bid: 0.0225 ETH
#   │  ├─ ✓ Apple bid: 0.015 ETH
#   │  ├─ ✓ Auction resolved
#   │  ├─ ✓ Payment settled
#   │  └─ Settlement amount (2nd price): 0.015 ETH
```

### Assertion Failures (-vvv)

```bash
# Eğer test başarısız olursa
forge test --match-test "testPlaceBid" -vvv

# Çıktı:
# [FAIL] AdExchangeTest::testPlaceBid (gas: 98123)
# 
# Error: Assertion failed: expected 0x00... but got 0x11...
# 
# Call trace:
# [0] ...
# ├─ [456] AdExchange.placeBid(...)
# ├─ [789] Assertion check
# └─ [FAIL] Test failed
```

---

## 🛠️ Gelişmiş Komutlar

### Fork Testing (Real Monad Testnet'e Karşı)

```bash
# Monad testnet'e karşı test çalıştır
forge test --fork-url https://testnet.monad.com

# Spesifik blok numarasından başlayarak test
forge test --fork-url $MONAD_RPC --fork-block-number 1000000
```

### Coverage Analizi

```bash
# Code coverage raporu
forge coverage

# HTML coverage raporu oluştur
forge coverage --report lcov

# Output: coverage/lcov.info (IDE'lerle entegre edilebilir)
```

### Trace (Hata Ayıklama)

```bash
# Test trace'i göster (call stack)
forge test --match-test "testPlaceBid" -vvv --trace

# Daha detaylı trace
forge test --match-test "testPlaceBid" --trace etherscan
```

---

## ✅ Test Kategorileri ve İçeriği

### TEST 1-4: Deployment Tests
```
✅ testDeploymentSuccess
✅ testBillboardRegistration
✅ testOracleAddressSetup
✅ testInitialState
```

### TEST 5-10: Happy Path (Başarılı Akış)
```
✅ testTriggerAuctionSuccess
✅ testPlaceBidSuccess
✅ testWinnerTrackingO1
✅ testResolveAuctionSuccess
✅ testSettlePaymentVickrey
✅ testCompleteAuctionFlow
```

### TEST 11-16: Security & Error Handling
```
✅ testTriggerAuctionUnauthorized
✅ testPlaceBidClosedAuction
✅ testPlaceBidInsufficientBudget
✅ testSettlePaymentNotClosed
✅ testRegisterBidderUnauthorized
✅ testRegisterBillboardUnauthorized
```

### TEST 17-20: Edge Cases
```
✅ testTriggerAuctionMaxDensity
✅ testParallelBidding
✅ testDoubleSpendPrevention
✅ testReservePriceEnforcement
```

### TEST 21-25: Gas Benchmarks
```
✅ testGasTriggerAuction
✅ testGasPlaceBid
✅ testGasResolveAuction
✅ testGasSettlePayment
✅ testGasFullAuctionCycle
```

### BIDDER TESTS 1-25
```
✅ Deployment
✅ Budget Management (deposit, withdraw, refill)
✅ Strategy Configuration
✅ Bidding Logic (calculations, caps, preferences)
✅ Callbacks (onWon, onLost)
✅ Security (authorization, modifiers)
✅ Edge Cases (receive, fallback)
```

### INTEGRATION TESTS 1-10
```
✅ Complete Auction Flow
✅ Multiple Auctions Sequence
✅ Three-Way Competition
✅ Low Density Filtered Bidding
✅ Budget Exhaustion
✅ Win/Loss Callbacks
✅ Vickrey Mechanism Details
✅ Revenue Tracking
✅ Stress Test - 10 Bidders
✅ Stress Test - 50 Auctions
```

---

## 📈 Test Coverage Hedefleri

```
Coverage Targets:
├─ Lines: 95%+ (kritik path'ler covered)
├─ Branches: 90%+ (error handling)
├─ Functions: 100% (all public functions)
└─ Statements: 95%+

Expected Results:
├─ All tests PASS ✓
├─ No gas limit exceeded
├─ Error messages clear and informative
└─ Performance meets targets (145K per auction)
```

---

## 🚨 Olası Test Hataları ve Çözümleri

### Error 1: "Cannot find contract"
```bash
# Sorunu: Contracts derlenmemiş
# Çözüm:
forge build
```

### Error 2: "Test failed: Assertion"
```bash
# Sorunu: Logic hatası
# Çözüm:
# 1. Console.log output'ını kontrol et
# 2. Stack trace'ı inceле (-vvv kullan)
# 3. Kontrat logic'ini debug et
```

### Error 3: "Out of gas"
```bash
# Sorunu: İşlem çok fazla gas harcanıyor
# Çözüm:
# 1. Optimizasyonları kontrol et
# 2. Storage access sayısını azalt
# 3. Loop'ları minimize et
```

### Error 4: "Revert: Only Owner"
```bash
# Sorunu: Test wrong account kullanıyor
# Çözüm:
vm.prank(owner);  // Correct account
```

---

## 📊 Başarılı Test Çıktısı Örneği

```
$ forge test

Compiling...
Compiled 8 Solidity files successfully

Running 60 tests...

[PASS] test/AdExchange.t.sol::AdExchangeTest::testDeploymentSuccess (gas: 12345)
[PASS] test/AdExchange.t.sol::AdExchangeTest::testTriggerAuctionSuccess (gas: 45123)
[PASS] test/AdExchange.t.sol::AdExchangeTest::testPlaceBidSuccess (gas: 12456)
[PASS] test/AdExchange.t.sol::AdExchangeTest::testWinnerTrackingO1 (gas: 18900)
[PASS] test/AdExchange.t.sol::AdExchangeTest::testSettlePaymentVickrey (gas: 35789)
[PASS] test/Bidder.t.sol::BidderTest::testDepositBudgetSuccess (gas: 8234)
[PASS] test/Bidder.t.sol::BidderTest::testPlaceBidCalculation (gas: 9876)
[PASS] test/Integration.t.sol::IntegrationTest::testCompleteAuctionFlow (gas: 154892)
[PASS] test/Integration.t.sol::IntegrationTest::testMultipleAuctionsSequence (gas: 234123)
[PASS] test/Integration.t.sol::IntegrationTest::testStress50Auctions (gas: 2456789)

... (50 more tests)

Test Suite Summary:
Passed 60 tests
Failed 0 tests
Total Gas Used: 15,234,567 gas

✓ All tests PASSED
```

---

## 🎯 Çalıştırma Planı (Step by Step)

### Adım 1: Temel Kurulum
```bash
forge build
# Derleme başarılı olmalı
```

### Adım 2: Hızlı Test
```bash
forge test --match-test "testDeployment"
# Deployment testleri geçmeli
```

### Adım 3: Happy Path
```bash
forge test --match-test "Complete"
# Integration test geçmeli
```

### Adım 4: Güvenlik Testleri
```bash
forge test --match-test "Unauthorized\|Revert"
# Tüm security testleri geçmeli
```

### Adım 5: Gaz Analizi
```bash
forge test --gas-report
# Gaz hedefleri meet edilmeli
```

### Adım 6: Stress Testleri
```bash
forge test --match-test "Stress"
# Yüksek yükü handle etmeli
```

### Adım 7: Tam Suite
```bash
forge test
# Tüm 60 test geçmeli
```

---

## 💡 Test Geliştirme İpuçları

### Yeni Test Yazma

```solidity
function testMyNewFeature() public {
    // Arrange
    setup();
    
    // Act
    bytes32 result = adExchange.someFunction();
    
    // Assert
    assertEq(result, expectedValue);
    
    // Console output
    console.log("Result:", uint256(result));
}
```

### Debug Etme

```solidity
// Console output ekle
console.log("Value:", someValue);
console.log("Address:", address(someAddress));
console.log("Bool:", someBool);

// Assertion ile stack trace
assertEq(actual, expected);

// Revert message'ı kontrol et
vm.expectRevert("Error message");
```

---

## 🏆 Test Success Criteria

- ✅ Tüm 60 test PASS
- ✅ Gas per auction < 150K
- ✅ Coverage > 95%
- ✅ No compiler warnings
- ✅ Security checks passed
- ✅ Performance benchmarks met

---

**Ready to test! Run `forge test` to begin.** 🧪
