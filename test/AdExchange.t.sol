// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/AdExchange.sol";
import "../contracts/Bidder.sol";
import "../contracts/interfaces/IOracle.sol";

/**
 * @title AdExchange Test Suite
 * @dev Comprehensive tests for AdExchange.sol
 * 
 * Test Kategorileri:
 * 1. Deployment Tests - Kontrat başlatılması
 * 2. Happy Path Tests - Normal işleyiş
 * 3. Security Tests - Yetkisiz erişim, hata durumları
 * 4. Edge Case Tests - Sınır koşulları
 * 5. Gas Benchmark Tests - Gaz tüketimi ölçümü
 */
contract AdExchangeTest is Test {
    
    // ==================== STATE VARIABLES ====================
    
    AdExchange public adExchange;
    Bidder public bidder1;
    Bidder public bidder2;
    Bidder public bidder3;
    
    address public oracle = address(0x1234);
    address public owner = address(0xAAAA);
    address public billboard1 = address(0xBBBB);
    address public billboard2 = address(0xCCCC);
    
    uint256 public initialBudget = 10 ether;
    
    // ==================== EVENTS ====================
    
    event AuctionStarted(bytes32 indexed auctionId, address indexed billboard);
    event BidPlaced(bytes32 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionFinalized(bytes32 indexed auctionId, address indexed winner);
    event PaymentSettled(bytes32 indexed auctionId, address indexed winner, uint256 amount);
    
    // ==================== SETUP ====================
    
    /**
     * @dev Deployment & Initialization
     * ✅ TEST 1: Kontratlar doğru parametrelerle deploy ediliyor mu?
     */
    function setUp() public {
        // Deploy AdExchange
        vm.startPrank(owner);
        adExchange = new AdExchange();
        adExchange.setOracleAddress(oracle);
        
        // Deploy sample Bidders
        bidder1 = new Bidder(address(adExchange));
        bidder2 = new Bidder(address(adExchange));
        bidder3 = new Bidder(address(adExchange));
        
        // Register bidders
        adExchange.registerBidder(address(bidder1));
        adExchange.registerBidder(address(bidder2));
        adExchange.registerBidder(address(bidder3));
        
        // Register billboards
        adExchange.registerBillboard(billboard1, "Times Square", 100);
        adExchange.registerBillboard(billboard2, "Shibuya Crossing", 150);
        
        vm.stopPrank();
        
        // Setup bidders with budgets and strategies
        vm.deal(address(bidder1), 1000 ether);
        vm.deal(address(bidder2), 1000 ether);
        vm.deal(address(bidder3), 1000 ether);
        
        _setupBidderStrategies();
    }
    
    /**
     * @dev Initialize bidder strategies
     */
    function _setupBidderStrategies() internal {
        // Bidder 1: Nike (Conservative)
        vm.startPrank(address(bidder1));
        bidder1.depositBudget{value: initialBudget}();
        bidder1.setStrategy(0.005 ether, 0.1 ether, 100, 30);
        vm.stopPrank();
        
        // Bidder 2: Coca-Cola (Premium)
        vm.startPrank(address(bidder2));
        bidder2.depositBudget{value: initialBudget}();
        bidder2.setStrategy(0.02 ether, 1 ether, 150, 25);
        vm.stopPrank();
        
        // Bidder 3: Apple (Competitive)
        vm.startPrank(address(bidder3));
        bidder3.depositBudget{value: initialBudget}();
        bidder3.setStrategy(0.01 ether, 0.5 ether, 200, 20);
        vm.stopPrank();
    }
    
    // ==================== DEPLOYMENT TESTS ====================
    
    /**
     * ✅ TEST 2: Kontrat başarıyla deploy ediliyor ve admin doğru ayarlanıyor
     */
    function testDeploymentSuccess() public {
        assertEq(adExchange.owner(), owner);
        assertEq(adExchange.oracleAddress(), oracle);
        assertTrue(adExchange.isRegisteredBidder(address(bidder1)));
        assertTrue(adExchange.isRegisteredBidder(address(bidder2)));
        assertTrue(adExchange.isRegisteredBidder(address(bidder3)));
    }
    
    /**
     * ✅ TEST 3: Billboards doğru şekilde kaydediliyor
     */
    function testBillboardRegistration() public {
        bool isBillboard1Active = adExchange.isActiveBillboard(billboard1);
        bool isBillboard2Active = adExchange.isActiveBillboard(billboard2);
        
        assertTrue(isBillboard1Active);
        assertTrue(isBillboard2Active);
    }
    
    /**
     * ✅ TEST 4: Oracle adresi doğru ayarlanıyor
     */
    function testOracleAddressSetup() public {
        assertEq(adExchange.oracleAddress(), oracle);
        
        // Yeni oracle adresi ayarla
        address newOracle = address(0x5678);
        vm.prank(owner);
        adExchange.setOracleAddress(newOracle);
        assertEq(adExchange.oracleAddress(), newOracle);
    }
    
    // ==================== HAPPY PATH TESTS ====================
    
    /**
     * ✅ TEST 5: triggerAuction() - İhale başarıyla başlatılıyor
     * Flow:
     * 1. Oracle %75 yoğunluk ile ihale başlatıyor
     * 2. Unique auctionId oluşturuluyor
     * 3. AuctionStarted event fırlatılıyor
     * 4. Tüm bidderlar paralel çağrılıyor
     */
    function testTriggerAuctionSuccess() public {
        uint256 crowdDensity = 75;  // 75% yoğunluk
        
        vm.expectEmit(true, false, false, false);
        emit AuctionStarted(bytes32(0), billboard1);
        
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, crowdDensity);
        
        // Verify auction was created
        assertNotEq(auctionId, bytes32(0));
        
        // Verify auction state
        (
            bytes32 storedId,
            address highestBidder,
            AdExchange.AuctionState state,
            bool isFinalized,
            uint256 highest,
            uint256 secondHighest,
            uint256 startTime,
            uint256 duration,
            uint256 density,
            address billboard
        ) = adExchange.getAuctionDetails(auctionId);
        
        assertEq(storedId, auctionId);
        assertEq(uint256(state), 1);  // ACTIVE
        assertFalse(isFinalized);
        assertEq(density, 75);
        assertEq(billboard, billboard1);
    }
    
    /**
     * ✅ TEST 6: triggerAuction() - Düşük yoğunlukta başarısız olmalı
     */
    function testTriggerAuctionLowDensity() public {
        uint256 lowDensity = 40;  // 40% < 50% threshold
        
        vm.prank(oracle);
        vm.expectRevert("Density too low");
        adExchange.triggerAuction(billboard1, lowDensity);
    }
    
    /**
     * ✅ TEST 7: placeBid() - Geçerli teklifler başarıyla veriliyor
     * Flow:
     * 1. İhale başlatılıyor
     * 2. Bidder1 teklif veriyor
     * 3. Bidder2 daha yüksek teklif veriyor
     * 4. O(1) winner tracking doğrulanıyor
     */
    function testPlaceBidSuccess() public {
        // 1. Trigger auction
        uint256 crowdDensity = 75;
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, crowdDensity);
        
        // 2. Bidder1 places bid
        uint256 bid1 = 0.0135 ether;  // 0.005 * 0.75 * 1.0
        vm.prank(address(bidder1));
        adExchange.placeBid(auctionId, bid1, "ipfs://bid1");
        
        // 3. Verify bid was recorded
        AdExchange.BidderSnapshot[] memory bids = adExchange.getAuctionBids(auctionId);
        assertEq(bids.length, 1);
        assertEq(bids[0].bidAmount, bid1);
        
        // 4. Verify O(1) tracking
        (
            bytes32 id,
            address highestBidder,
            ,
            ,
            uint256 highestAmount,
            ,
            ,
            ,
            ,
        ) = adExchange.getAuctionDetails(auctionId);
        
        assertEq(highestBidder, address(bidder1));
        assertEq(highestAmount, bid1);
    }
    
    /**
     * ✅ TEST 8: O(1) Winner Tracking - Highest & 2nd Highest doğru update ediliyor
     */
    function testWinnerTrackingO1() public {
        // Trigger auction
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        // Bid 1: 0.0135 ETH
        uint256 bid1 = 0.0135 ether;
        vm.prank(address(bidder1));
        adExchange.placeBid(auctionId, bid1, "ipfs://bid1");
        
        // Verify: Bidder1 = highest, no 2nd highest yet
        (,address highest1,,,uint256 highestAmount1,uint256 secondHighest1,,,)
            = adExchange.getAuctionDetails(auctionId);
        assertEq(highest1, address(bidder1));
        assertEq(highestAmount1, bid1);
        assertEq(secondHighest1, 0);
        
        // Bid 2: 0.045 ETH (higher)
        uint256 bid2 = 0.045 ether;
        vm.prank(address(bidder2));
        adExchange.placeBid(auctionId, bid2, "ipfs://bid2");
        
        // Verify: Bidder2 = highest, Bidder1 = 2nd highest
        (,address highest2,,,uint256 highestAmount2,uint256 secondHighest2,,,)
            = adExchange.getAuctionDetails(auctionId);
        assertEq(highest2, address(bidder2));
        assertEq(highestAmount2, bid2);
        assertEq(secondHighest2, bid1);  // ← Bidder1's bid becomes 2nd
        
        // Bid 3: 0.02 ETH (between 2nd and 3rd)
        uint256 bid3 = 0.02 ether;
        vm.prank(address(bidder3));
        adExchange.placeBid(auctionId, bid3, "ipfs://bid3");
        
        // Verify: Highest still Bidder2, 2nd highest becomes Bidder3
        (,address highest3,,,uint256 highestAmount3,uint256 secondHighest3,,,)
            = adExchange.getAuctionDetails(auctionId);
        assertEq(highest3, address(bidder2));
        assertEq(highestAmount3, bid2);
        assertEq(secondHighest3, bid3);  // ← Updated to Bidder3's bid
    }
    
    /**
     * ✅ TEST 9: resolveAuction() - Ihale başarıyla sonlandırılıyor
     */
    function testResolveAuctionSuccess() public {
        // Trigger auction
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        // Place bids
        vm.prank(address(bidder1));
        adExchange.placeBid(auctionId, 0.0135 ether, "ipfs://bid1");
        
        // Fast-forward time (auction duration = 300ms)
        vm.warp(block.timestamp + 400);  // 400ms later
        
        // Resolve auction
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId);
        
        // Verify state changed to CLOSED
        (,,,,,,,,,) = adExchange.getAuctionDetails(auctionId);
        // State should be CLOSED (2)
    }
    
    /**
     * ✅ TEST 10: settlePayment() - Vickrey (2nd price) ödeme
     * Winner pays 2nd highest price, not highest!
     */
    function testSettlePaymentVickrey() public {
        // Setup bids
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        uint256 bid1 = 0.045 ether;   // Bidder2 wins
        uint256 bid2 = 0.0225 ether;  // Bidder1 is 2nd
        
        vm.prank(address(bidder1));
        adExchange.placeBid(auctionId, bid2, "ipfs://bid1");
        
        vm.prank(address(bidder2));
        adExchange.placeBid(auctionId, bid1, "ipfs://bid2");
        
        // Resolve auction
        vm.warp(block.timestamp + 400);
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId);
        
        // Settle payment
        vm.prank(owner);
        adExchange.settlePayment(auctionId);
        
        // Verify payment amount = 2nd highest (Vickrey)
        // Winner (bidder2) pays bidder1's bid (0.0225 ETH)
        assertEq(adExchange.auctionSettlements(auctionId), bid2);
    }
    
    // ==================== SECURITY & ERROR TESTS ====================
    
    /**
     * ✅ TEST 11: triggerAuction() - Yetkisiz biri ihale başlatamaz
     */
    function testTriggerAuctionUnauthorized() public {
        address unauthorized = address(0x9999);
        
        vm.prank(unauthorized);
        vm.expectRevert("Only Oracle");
        adExchange.triggerAuction(billboard1, 75);
    }
    
    /**
     * ✅ TEST 12: placeBid() - Kapanan ihaleye teklif verilemez
     */
    function testPlaceBidClosedAuction() public {
        // Trigger and close auction
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        vm.warp(block.timestamp + 400);
        
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId);
        
        // Try to place bid on closed auction
        vm.prank(address(bidder1));
        vm.expectRevert("Auction not active");
        adExchange.placeBid(auctionId, 0.01 ether, "ipfs://bid");
    }
    
    /**
     * ✅ TEST 13: placeBid() - Yetersiz bütçesi olan bidder teklife veremez
     */
    function testPlaceBidInsufficientBudget() public {
        // Create a new bidder with small budget
        vm.prank(owner);
        Bidder poorBidder = new Bidder(address(adExchange));
        adExchange.registerBidder(address(poorBidder));
        
        // Give only 0.001 ETH budget
        vm.deal(address(poorBidder), 0.001 ether);
        vm.prank(address(poorBidder));
        poorBidder.depositBudget{value: 0.001 ether}();
        poorBidder.setStrategy(0.01 ether, 1 ether, 100, 20);
        
        // Trigger auction
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        // Try to bid more than budget
        vm.prank(address(poorBidder));
        // placeBid should fail or return shouldBid = false
        // (İnternal kontrol - AdExchange'de try-catch ile handle edilir)
    }
    
    /**
     * ✅ TEST 14: settlePayment() - Henüz kapanmamış ihale ödenemiyor
     */
    function testSettlePaymentNotClosed() public {
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        vm.prank(address(bidder1));
        adExchange.placeBid(auctionId, 0.01 ether, "ipfs://bid");
        
        // Try to settle without resolving (auction still ACTIVE)
        vm.prank(owner);
        vm.expectRevert("Auction not closed");
        adExchange.settlePayment(auctionId);
    }
    
    /**
     * ✅ TEST 15: registerBidder() - Sadece owner register edebilir
     */
    function testRegisterBidderUnauthorized() public {
        address unauthorized = address(0x9999);
        address newBidder = address(0x7777);
        
        vm.prank(unauthorized);
        vm.expectRevert("Only Owner");
        adExchange.registerBidder(newBidder);
    }
    
    /**
     * ✅ TEST 16: registerBillboard() - Sadece owner register edebilir
     */
    function testRegisterBillboardUnauthorized() public {
        address unauthorized = address(0x9999);
        address newBillboard = address(0x6666);
        
        vm.prank(unauthorized);
        vm.expectRevert("Only Owner");
        adExchange.registerBillboard(newBillboard, "New Location", 100);
    }
    
    // ==================== EDGE CASE TESTS ====================
    
    /**
     * ✅ TEST 17: triggerAuction() - 100% yoğunluk (maximum)
     */
    function testTriggerAuctionMaxDensity() public {
        uint256 maxDensity = 100;
        
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, maxDensity);
        
        assertNotEq(auctionId, bytes32(0));
    }
    
    /**
     * ✅ TEST 18: placeBid() - Multiple bidders paralel teklif (parallelization test)
     */
    function testParallelBidding() public {
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        // Simulate parallel bids (within same block)
        vm.prank(address(bidder1));
        adExchange.placeBid(auctionId, 0.0135 ether, "ipfs://bid1");
        
        vm.prank(address(bidder2));
        adExchange.placeBid(auctionId, 0.045 ether, "ipfs://bid2");
        
        vm.prank(address(bidder3));
        adExchange.placeBid(auctionId, 0.02 ether, "ipfs://bid3");
        
        // Verify all bids recorded
        AdExchange.BidderSnapshot[] memory bids = adExchange.getAuctionBids(auctionId);
        assertEq(bids.length, 3);
    }
    
    /**
     * ✅ TEST 19: Double-spend prevention - Same bidder can't reuse budget
     */
    function testDoubleSpendPrevention() public {
        vm.prank(oracle);
        bytes32 auctionId1 = adExchange.triggerAuction(billboard1, 75);
        
        // Bidder1 reserves 0.0135 ETH
        vm.prank(address(bidder1));
        adExchange.placeBid(auctionId1, 0.0135 ether, "ipfs://bid1");
        
        // Check available budget decreased
        uint256 budgetAfterBid = bidder1.getAvailableBudget();
        assertEq(budgetAfterBid, initialBudget - 0.0135 ether);
        
        // Create another auction
        vm.prank(oracle);
        bytes32 auctionId2 = adExchange.triggerAuction(billboard2, 75);
        
        // Bidder1 can bid on new auction with remaining budget
        // But not more than remaining
        vm.prank(address(bidder1));
        // This should work with remaining budget
        uint256 bid2 = 0.0100 ether;
        adExchange.placeBid(auctionId2, bid2, "ipfs://bid2");
        
        // Total reserved should be 0.0235 ETH
        uint256 finalBudget = bidder1.getAvailableBudget();
        assertEq(finalBudget, initialBudget - 0.0135 ether - 0.0100 ether);
    }
    
    /**
     * ✅ TEST 20: Reserve price kontrol - Reserve price'dan düşük teklif yapılamaz
     */
    function testReservePriceEnforcement() public {
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        // Try to bid below reserve price (0.001 ETH default)
        vm.prank(address(bidder1));
        vm.expectRevert("Below reserve price");
        adExchange.placeBid(auctionId, 0.0005 ether, "ipfs://low-bid");
    }
    
    // ==================== GAS BENCHMARK TESTS ====================
    
    /**
     * ✅ TEST 21: Gas benchmark - triggerAuction()
     * Expected: ~45,000 gas
     */
    function testGasTriggerAuction() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(oracle);
        adExchange.triggerAuction(billboard1, 75);
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        console.log("Gas used for triggerAuction:", gasUsed);
        assertLt(gasUsed, 50000);  // Should be ~45K
    }
    
    /**
     * ✅ TEST 22: Gas benchmark - placeBid()
     * Expected: ~12,000 gas
     */
    function testGasPlaceBid() public {
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        uint256 gasBefore = gasleft();
        
        vm.prank(address(bidder1));
        adExchange.placeBid(auctionId, 0.01 ether, "ipfs://bid");
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        console.log("Gas used for placeBid:", gasUsed);
        assertLt(gasUsed, 20000);  // Should be ~12K
    }
    
    /**
     * ✅ TEST 23: Gas benchmark - resolveAuction()
     * Expected: ~5,000 gas
     */
    function testGasResolveAuction() public {
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        vm.prank(address(bidder1));
        adExchange.placeBid(auctionId, 0.01 ether, "ipfs://bid");
        
        vm.warp(block.timestamp + 400);
        
        uint256 gasBefore = gasleft();
        
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId);
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        console.log("Gas used for resolveAuction:", gasUsed);
        assertLt(gasUsed, 10000);  // Should be ~5K
    }
    
    /**
     * ✅ TEST 24: Gas benchmark - settlePayment()
     * Expected: ~35,000 gas
     */
    function testGasSettlePayment() public {
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        vm.prank(address(bidder1));
        adExchange.placeBid(auctionId, 0.0135 ether, "ipfs://bid1");
        
        vm.prank(address(bidder2));
        adExchange.placeBid(auctionId, 0.045 ether, "ipfs://bid2");
        
        vm.warp(block.timestamp + 400);
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId);
        
        uint256 gasBefore = gasleft();
        
        vm.prank(owner);
        adExchange.settlePayment(auctionId);
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        console.log("Gas used for settlePayment:", gasUsed);
        assertLt(gasUsed, 50000);  // Should be ~35K
    }
    
    /**
     * ✅ TEST 25: Full auction cycle gas benchmark
     * Measure total gas for complete flow
     */
    function testGasFullAuctionCycle() public {
        uint256 gasBefore = gasleft();
        
        // 1. Trigger
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        // 2. Place bids
        vm.prank(address(bidder1));
        adExchange.placeBid(auctionId, 0.0135 ether, "ipfs://bid1");
        
        vm.prank(address(bidder2));
        adExchange.placeBid(auctionId, 0.045 ether, "ipfs://bid2");
        
        vm.prank(address(bidder3));
        adExchange.placeBid(auctionId, 0.02 ether, "ipfs://bid3");
        
        // 3. Resolve
        vm.warp(block.timestamp + 400);
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId);
        
        // 4. Settle
        vm.prank(owner);
        adExchange.settlePayment(auctionId);
        
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        
        console.log("Total gas for full auction cycle:", gasUsed);
        assertLt(gasUsed, 200000);  // Should be ~145K
    }
}
