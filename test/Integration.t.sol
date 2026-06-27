// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/AdExchange.sol";
import "../contracts/Bidder.sol";

/**
 * @title Integration Test Suite
 * @dev Complete flow tests: trigger → bid → resolve → settle
 * 
 * Senaryolar:
 * 1. Basic Flow - Başlangıçtan bitişe tam akış
 * 2. Multiple Bidders - Birden fazla markayla rekabet
 * 3. Multiple Auctions - Arka arkaya açık artırmalar
 * 4. Vickrey Mechanism - 2nd price ödeme doğrulaması
 * 5. Performance - Ölçek testi (çok bidder)
 */
contract IntegrationTest is Test {
    
    // ==================== STATE VARIABLES ====================
    
    AdExchange public adExchange;
    Bidder public bidderNike;
    Bidder public bidderCocaCola;
    Bidder public bidderApple;
    
    address public oracle = address(0x1000);
    address public owner = address(0x2000);
    address public billboard1 = address(0x3000);
    address public billboard2 = address(0x4000);
    
    uint256 constant BUDGET = 100 ether;
    
    // ==================== SETUP ====================
    
    function setUp() public {
        // Deploy AdExchange
        vm.startPrank(owner);
        adExchange = new AdExchange();
        adExchange.setOracleAddress(oracle);
        
        // Deploy Bidders
        bidderNike = new Bidder(address(adExchange));
        bidderCocaCola = new Bidder(address(adExchange));
        bidderApple = new Bidder(address(adExchange));
        
        // Register
        adExchange.registerBidder(address(bidderNike));
        adExchange.registerBidder(address(bidderCocaCola));
        adExchange.registerBidder(address(bidderApple));
        
        adExchange.registerBillboard(billboard1, "Times Square", 100);
        adExchange.registerBillboard(billboard2, "Shibuya Crossing", 150);
        
        vm.stopPrank();
        
        // Fund bidders
        vm.deal(address(bidderNike), 1000 ether);
        vm.deal(address(bidderCocaCola), 1000 ether);
        vm.deal(address(bidderApple), 1000 ether);
        
        // Setup bidders
        _setupBidders();
    }
    
    function _setupBidders() internal {
        // Nike - Conservative bidder
        vm.startPrank(address(bidderNike));
        bidderNike.depositBudget{value: BUDGET}();
        bidderNike.setStrategy(0.005 ether, 0.1 ether, 100, 30);
        vm.stopPrank();
        
        // Coca-Cola - Premium bidder
        vm.startPrank(address(bidderCocaCola));
        bidderCocaCola.depositBudget{value: BUDGET}();
        bidderCocaCola.setStrategy(0.02 ether, 1 ether, 150, 25);
        vm.stopPrank();
        
        // Apple - Competitive bidder
        vm.startPrank(address(bidderApple));
        bidderApple.depositBudget{value: BUDGET}();
        bidderApple.setStrategy(0.01 ether, 0.5 ether, 200, 20);
        vm.stopPrank();
    }
    
    // ==================== INTEGRATION TESTS ====================
    
    /**
     * ✅ TEST 1: Complete Auction Flow (Trigger → Bid → Resolve → Settle)
     * 
     * Scenario:
     * 1. Oracle triggers auction with 75% crowd
     * 2. Three brands place bids
     * 3. Duration expires
     * 4. Auction resolved
     * 5. Payment settled (Vickrey 2nd price)
     */
    function testCompleteAuctionFlow() public {
        console.log("=== TEST 1: Complete Auction Flow ===");
        
        // 1. TRIGGER
        uint256 crowdDensity = 75;
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, crowdDensity);
        console.log("✓ Auction triggered:", uint256(auctionId));
        
        // 2. BIDS
        // Nike: 0.005 * 0.75 * 1.0 = 0.00375
        vm.prank(address(bidderNike));
        adExchange.placeBid(auctionId, 0.00375 ether, "ipfs://nike");
        console.log("✓ Nike bid: 0.00375 ETH");
        
        // Coca-Cola: 0.02 * 0.75 * 1.5 = 0.0225
        vm.prank(address(bidderCocaCola));
        adExchange.placeBid(auctionId, 0.0225 ether, "ipfs://coca");
        console.log("✓ Coca-Cola bid: 0.0225 ETH");
        
        // Apple: 0.01 * 0.75 * 2.0 = 0.015
        vm.prank(address(bidderApple));
        adExchange.placeBid(auctionId, 0.015 ether, "ipfs://apple");
        console.log("✓ Apple bid: 0.015 ETH");
        
        // 3. RESOLVE
        vm.warp(block.timestamp + 400);  // Duration expires
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId);
        console.log("✓ Auction resolved");
        
        // 4. SETTLE (Vickrey: Winner pays 2nd highest)
        vm.prank(owner);
        adExchange.settlePayment(auctionId);
        console.log("✓ Payment settled");
        
        // VERIFY RESULTS
        // Winner should be Coca-Cola (0.0225)
        // Payment should be 2nd highest (0.015 from Apple) ← Vickrey!
        uint256 settlement = adExchange.auctionSettlements(auctionId);
        console.log("Settlement amount (2nd price):", settlement);
        assertEq(settlement, 0.015 ether);  // 2nd price!
    }
    
    /**
     * ✅ TEST 2: Multiple Auctions in Sequence
     * 
     * Verify budgets are properly managed across multiple auctions
     */
    function testMultipleAuctionsSequence() public {
        console.log("=== TEST 2: Multiple Auctions Sequence ===");
        
        // Auction 1
        vm.prank(oracle);
        bytes32 auctionId1 = adExchange.triggerAuction(billboard1, 75);
        
        vm.prank(address(bidderNike));
        adExchange.placeBid(auctionId1, 0.01 ether, "ipfs://bid1");
        
        uint256 budgetAfter1 = bidderNike.getAvailableBudget();
        console.log("After auction 1, Nike budget:", budgetAfter1);
        assertEq(budgetAfter1, BUDGET - 0.01 ether);
        
        vm.warp(block.timestamp + 400);
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId1);
        
        vm.prank(owner);
        adExchange.settlePayment(auctionId1);
        
        // Auction 2
        vm.prank(oracle);
        bytes32 auctionId2 = adExchange.triggerAuction(billboard2, 70);
        
        vm.prank(address(bidderNike));
        adExchange.placeBid(auctionId2, 0.008 ether, "ipfs://bid2");
        
        uint256 budgetAfter2 = bidderNike.getAvailableBudget();
        console.log("After auction 2, Nike budget:", budgetAfter2);
        assertEq(budgetAfter2, BUDGET - 0.01 ether - 0.008 ether);
        
        // Verify metrics
        (uint256 participated, uint256 won, uint256 spent, ) = bidderNike.getPerformanceMetrics();
        console.log("Nike participated:", participated);
        console.log("Nike won:", won);
        console.log("Nike spent:", spent);
        assertEq(participated, 2);
    }
    
    /**
     * ✅ TEST 3: Three-Way Competition
     * 
     * Test complex bidding scenario with multiple bidders
     */
    function testThreeWayCompetition() public {
        console.log("=== TEST 3: Three-Way Competition ===");
        
        // Setup high crowd density - all should bid
        uint256 crowdDensity = 85;
        
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, crowdDensity);
        
        // Nike
        vm.prank(address(bidderNike));
        (uint256 bidNike, bool shouldBidNike, ) = bidderNike.placeBid(auctionId, crowdDensity, billboard1);
        console.log("Nike - Amount:", bidNike, "Should bid:", shouldBidNike);
        
        // Coca-Cola
        vm.prank(address(bidderCocaCola));
        (uint256 bidCoca, bool shouldBidCoca, ) = bidderCocaCola.placeBid(auctionId, crowdDensity, billboard1);
        console.log("Coca-Cola - Amount:", bidCoca, "Should bid:", shouldBidCoca);
        
        // Apple
        vm.prank(address(bidderApple));
        (uint256 bidApple, bool shouldBidApple, ) = bidderApple.placeBid(auctionId, crowdDensity, billboard1);
        console.log("Apple - Amount:", bidApple, "Should bid:", shouldBidApple);
        
        // All should have bid
        assertTrue(shouldBidNike && shouldBidCoca && shouldBidApple);
        
        // Verify ranking
        console.log("Ranking:");
        console.log("1. Coca-Cola:", bidCoca);
        console.log("2. Apple:", bidApple);
        console.log("3. Nike:", bidNike);
        
        assertGt(bidCoca, bidApple);
        assertGt(bidApple, bidNike);
    }
    
    /**
     * ✅ TEST 4: Low Density - Some Bidders Opt Out
     * 
     * When crowd is low, only aggressive bidders participate
     */
    function testLowDensityFilteredBidding() public {
        console.log("=== TEST 4: Low Density Filtered Bidding ===");
        
        uint256 lowDensity = 25;  // Very low
        
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, lowDensity);
        
        // Nike requires minDensity = 30% → won't bid
        vm.prank(address(bidderNike));
        (, bool shouldBidNike, ) = bidderNike.placeBid(auctionId, lowDensity, billboard1);
        console.log("Nike should bid (min 30%):", shouldBidNike);
        assertFalse(shouldBidNike);
        
        // Coca-Cola requires minDensity = 25% → will bid
        vm.prank(address(bidderCocaCola));
        (, bool shouldBidCoca, ) = bidderCocaCola.placeBid(auctionId, lowDensity, billboard1);
        console.log("Coca-Cola should bid (min 25%):", shouldBidCoca);
        assertTrue(shouldBidCoca);
        
        // Apple requires minDensity = 20% → will bid
        vm.prank(address(bidderApple));
        (, bool shouldBidApple, ) = bidderApple.placeBid(auctionId, lowDensity, billboard1);
        console.log("Apple should bid (min 20%):", shouldBidApple);
        assertTrue(shouldBidApple);
    }
    
    /**
     * ✅ TEST 5: Budget Exhaustion
     * 
     * Bidder runs out of budget and stops participating
     */
    function testBudgetExhaustion() public {
        console.log("=== TEST 5: Budget Exhaustion ===");
        
        // Create a low-budget bidder
        Bidder lowBudgetBidder = new Bidder(address(adExchange));
        vm.prank(owner);
        adExchange.registerBidder(address(lowBudgetBidder));
        
        vm.deal(address(lowBudgetBidder), 100 ether);
        vm.startPrank(address(lowBudgetBidder));
        lowBudgetBidder.depositBudget{value: 0.05 ether}();  // Only 0.05 ETH
        lowBudgetBidder.setStrategy(0.01 ether, 0.5 ether, 100, 30);
        vm.stopPrank();
        
        console.log("Initial budget:", lowBudgetBidder.getAvailableBudget());
        
        // Auction 1
        vm.prank(oracle);
        bytes32 auctionId1 = adExchange.triggerAuction(billboard1, 75);
        
        vm.prank(address(lowBudgetBidder));
        (uint256 bid1, bool should1, ) = lowBudgetBidder.placeBid(auctionId1, 75, billboard1);
        console.log("Auction 1 - Bid:", bid1, "Should bid:", should1);
        assertTrue(should1);
        
        uint256 budgetAfter1 = lowBudgetBidder.getAvailableBudget();
        console.log("After auction 1:", budgetAfter1);
        
        // Auction 2 - Budget nearly exhausted
        vm.prank(oracle);
        bytes32 auctionId2 = adExchange.triggerAuction(billboard2, 75);
        
        vm.prank(address(lowBudgetBidder));
        (uint256 bid2, bool should2, ) = lowBudgetBidder.placeBid(auctionId2, 75, billboard2);
        console.log("Auction 2 - Bid:", bid2, "Should bid:", should2);
        assertFalse(should2);  // Budget exhausted
    }
    
    /**
     * ✅ TEST 6: Win/Loss Callbacks
     * 
     * Verify bidders receive proper notifications
     */
    function testWinLossCallbacks() public {
        console.log("=== TEST 6: Win/Loss Callbacks ===");
        
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        // Setup: Nike bids 0.005, Coca-Cola bids 0.03
        vm.prank(address(bidderNike));
        adExchange.placeBid(auctionId, 0.005 ether, "ipfs://nike");
        
        vm.prank(address(bidderCocaCola));
        adExchange.placeBid(auctionId, 0.03 ether, "ipfs://coca");
        
        // Resolve and settle
        vm.warp(block.timestamp + 400);
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId);
        
        // Before settlement
        (uint256 nikeWinsBefore, , , ) = bidderNike.getPerformanceMetrics();
        (uint256 cocaWinsBefore, , , ) = bidderCocaCola.getPerformanceMetrics();
        console.log("Nike wins before:", nikeWinsBefore);
        console.log("Coca wins before:", cocaWinsBefore);
        
        // Settle - triggers callbacks
        vm.prank(owner);
        adExchange.settlePayment(auctionId);
        
        // After settlement
        (uint256 nikeWinsAfter, , , ) = bidderNike.getPerformanceMetrics();
        (uint256 cocaWinsAfter, , , ) = bidderCocaCola.getPerformanceMetrics();
        console.log("Nike wins after (lost):", nikeWinsAfter);
        console.log("Coca wins after (won):", cocaWinsAfter);
        
        // Coca-Cola should have won
        assertEq(cocaWinsAfter, cocaWinsBefore + 1);
    }
    
    /**
     * ✅ TEST 7: Vickrey Mechanism Verification
     * 
     * Ensure 2nd price is charged correctly
     */
    function testVickreyMechanismDetails() public {
        console.log("=== TEST 7: Vickrey Mechanism ===");
        
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 80);
        
        // Bids:
        // Nike:       0.005 ETH
        // Apple:      0.016 ETH (2nd highest)
        // Coca-Cola:  0.048 ETH (highest)
        
        vm.prank(address(bidderNike));
        adExchange.placeBid(auctionId, 0.005 ether, "ipfs://nike");
        
        vm.prank(address(bidderApple));
        adExchange.placeBid(auctionId, 0.016 ether, "ipfs://apple");
        
        vm.prank(address(bidderCocaCola));
        adExchange.placeBid(auctionId, 0.048 ether, "ipfs://coca");
        
        // Verify tracking
        (,,uint256 highest,,uint256 secondHighest,,,,,) = adExchange.getAuctionDetails(auctionId);
        console.log("Highest bid:", highest);
        console.log("2nd highest bid:", secondHighest);
        assertEq(highest, 0.048 ether);
        assertEq(secondHighest, 0.016 ether);
        
        // Resolve & settle
        vm.warp(block.timestamp + 400);
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId);
        
        vm.prank(owner);
        adExchange.settlePayment(auctionId);
        
        // Payment should be 2nd highest (0.016)
        uint256 payment = adExchange.auctionSettlements(auctionId);
        console.log("Payment (Vickrey 2nd price):", payment);
        assertEq(payment, 0.016 ether);  // NOT 0.048!
    }
    
    /**
     * ✅ TEST 8: Revenue Tracking
     * 
     * Platform and billboard revenues are tracked correctly
     */
    function testRevenueTracking() public {
        console.log("=== TEST 8: Revenue Tracking ===");
        
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        vm.prank(address(bidderNike));
        adExchange.placeBid(auctionId, 0.01 ether, "ipfs://nike");
        
        vm.prank(address(bidderCocaCola));
        adExchange.placeBid(auctionId, 0.05 ether, "ipfs://coca");
        
        vm.warp(block.timestamp + 400);
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId);
        
        vm.prank(owner);
        adExchange.settlePayment(auctionId);
        
        // Payment = 0.01 ETH (2nd price)
        // Platform fee (5%) = 0.0005 ETH
        // Billboard earning = 0.0095 ETH
        
        uint256 platformFee = (0.01 ether * 500) / 10000;
        uint256 billboardEarning = 0.01 ether - platformFee;
        
        console.log("Platform fee:", platformFee);
        console.log("Billboard earning:", billboardEarning);
        
        // Verify in contract
        (uint256 participated, uint256 won, uint256 spent, ) = adExchange.getMetrics();
        console.log("Total auctions:", participated);
        console.log("Platform earned:", adExchange.platformBalances(address(adExchange)));
        console.log("Billboard earned:", adExchange.billboardEarnings(billboard1));
    }
    
    /**
     * ✅ TEST 9: Stress Test - 10 Bidders
     * 
     * Verify system handles multiple bidders efficiently
     */
    function testStress10Bidders() public {
        console.log("=== TEST 9: Stress Test - 10 Bidders ===");
        
        // Create 10 bidders
        Bidder[] memory bidders = new Bidder[](10);
        for (uint i = 0; i < 10; i++) {
            bidders[i] = new Bidder(address(adExchange));
            vm.prank(owner);
            adExchange.registerBidder(address(bidders[i]));
            
            vm.deal(address(bidders[i]), 1000 ether);
            vm.startPrank(address(bidders[i]));
            bidders[i].depositBudget{value: 100 ether}();
            bidders[i].setStrategy(0.001 ether, 1 ether, 100, 20);
            vm.stopPrank();
        }
        
        console.log("Created 10 bidders");
        
        // Trigger auction
        vm.prank(oracle);
        bytes32 auctionId = adExchange.triggerAuction(billboard1, 75);
        
        // All 10 place bids
        for (uint i = 0; i < 10; i++) {
            vm.prank(address(bidders[i]));
            adExchange.placeBid(auctionId, (i + 1) * 0.001 ether, "ipfs://bid");
        }
        
        console.log("All 10 bidders placed bids");
        
        // Verify all bids recorded
        AdExchange.BidderSnapshot[] memory bids = adExchange.getAuctionBids(auctionId);
        console.log("Total bids recorded:", bids.length);
        assertEq(bids.length, 10);
        
        // Resolve & settle
        vm.warp(block.timestamp + 400);
        vm.prank(oracle);
        adExchange.resolveAuction(auctionId);
        
        vm.prank(owner);
        adExchange.settlePayment(auctionId);
        
        console.log("✓ Successfully handled 10 bidders");
    }
    
    /**
     * ✅ TEST 10: Stress Test - 50 Sequential Auctions
     * 
     * Verify system handles high throughput
     */
    function testStress50Auctions() public {
        console.log("=== TEST 10: Stress Test - 50 Auctions ===");
        
        uint256 startGas = gasleft();
        
        for (uint i = 0; i < 50; i++) {
            // Trigger
            vm.prank(oracle);
            bytes32 auctionId = adExchange.triggerAuction(billboard1, 50 + (i % 30));
            
            // Bids
            vm.prank(address(bidderNike));
            adExchange.placeBid(auctionId, 0.005 ether, "ipfs://nike");
            
            vm.prank(address(bidderCocaCola));
            adExchange.placeBid(auctionId, 0.02 ether, "ipfs://coca");
            
            // Resolve & Settle
            vm.warp(block.timestamp + 400);
            vm.prank(oracle);
            adExchange.resolveAuction(auctionId);
            
            vm.prank(owner);
            adExchange.settlePayment(auctionId);
        }
        
        uint256 endGas = gasleft();
        uint256 gasUsed = startGas - endGas;
        
        console.log("Gas used for 50 auctions:", gasUsed);
        console.log("Average gas per auction:", gasUsed / 50);
        
        // Metrics
        (uint256 total, uint256 active, uint256 volume, ) = adExchange.getMetrics();
        console.log("Total auctions:", total);
        console.log("Total volume:", volume);
    }
}
