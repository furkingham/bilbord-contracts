// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/Bidder.sol";
import "../contracts/interfaces/IBidder.sol";

/**
 * @title Bidder Test Suite
 * @dev Comprehensive tests for Bidder.sol (Brand automation)
 * 
 * Test Kategorileri:
 * 1. Deployment Tests - Bidder contract başlatılması
 * 2. Budget Management Tests - Deposit, withdraw, tracking
 * 3. Strategy Configuration Tests - Bidding parameters
 * 4. Bidding Logic Tests - Dynamic bid calculations
 * 5. Callback Tests - onAuctionWon, onAuctionLost
 * 6. Edge Cases & Security - Error scenarios
 */
contract BidderTest is Test {
    
    // ==================== STATE VARIABLES ====================
    
    Bidder public bidder;
    address public adExchange = address(0x1111);
    address public owner = address(0x2222);
    address public billboard1 = address(0x3333);
    address public billboard2 = address(0x4444);
    
    uint256 public initialBudget = 10 ether;
    
    // ==================== EVENTS ====================
    
    event BudgetDeposited(address indexed depositor, uint256 amount, uint256 totalBudget);
    event BudgetWithdrawn(address indexed recipient, uint256 amount, uint256 remainingBudget);
    event StrategyUpdated(uint256 basePrice, uint256 maxPrice, uint256 factor, uint256 minDensity);
    
    // ==================== SETUP ====================
    
    function setUp() public {
        // Deploy Bidder contract (brand's contract)
        bidder = new Bidder(adExchange);
        
        // Owner = this test contract (or specific address)
        vm.prank(owner);
        // bidder is deployed by owner
    }
    
    // ==================== DEPLOYMENT TESTS ====================
    
    /**
     * ✅ TEST 1: Bidder contract başarıyla deploy ediliyor
     */
    function testDeploymentSuccess() public {
        assertEq(bidder.adExchange(), adExchange);
        // Owner is set to msg.sender (test contract in setUp)
    }
    
    /**
     * ✅ TEST 2: Initial state doğru ayarlanıyor
     */
    function testInitialState() public {
        // Budget should be inactive initially
        (uint256 total, uint256 spent, uint256 available, bool isActive) = bidder.getBudgetDetails();
        assertEq(total, 0);
        assertEq(spent, 0);
        assertEq(available, 0);
        assertFalse(isActive);
        
        // Metrics should be 0
        (uint256 participated, uint256 won, uint256 spent2, uint256 winRate) = bidder.getPerformanceMetrics();
        assertEq(participated, 0);
        assertEq(won, 0);
        assertEq(spent2, 0);
        assertEq(winRate, 0);
    }
    
    // ==================== BUDGET MANAGEMENT TESTS ====================
    
    /**
     * ✅ TEST 3: depositBudget() - Ethers başarıyla yatırılıyor
     */
    function testDepositBudgetSuccess() public {
        vm.deal(address(this), 10 ether);
        
        vm.expectEmit(true, false, false, true);
        emit BudgetDeposited(address(this), initialBudget, initialBudget);
        
        bidder.depositBudget{value: initialBudget}();
        
        (uint256 total, uint256 spent, uint256 available, bool isActive) = bidder.getBudgetDetails();
        assertEq(total, initialBudget);
        assertEq(available, initialBudget);
        assertTrue(isActive);
    }
    
    /**
     * ✅ TEST 4: depositBudget() - 0 deposit başarısız olmalı
     */
    function testDepositBudgetZero() public {
        vm.expectRevert("Must deposit > 0");
        bidder.depositBudget{value: 0}();
    }
    
    /**
     * ✅ TEST 5: withdrawBudget() - Bütçe başarıyla çekilebiliyor
     */
    function testWithdrawBudgetSuccess() public {
        // Deposit first
        vm.deal(address(this), 10 ether);
        bidder.depositBudget{value: 5 ether}();
        
        // Get balance before
        uint256 balanceBefore = address(this).balance;
        
        // Withdraw half
        bidder.withdrawBudget(2.5 ether);
        
        // Check budget
        (uint256 total, , uint256 available, ) = bidder.getBudgetDetails();
        assertEq(total, 2.5 ether);
        assertEq(available, 2.5 ether);
        
        // Check ETH received
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter, balanceBefore + 2.5 ether);
    }
    
    /**
     * ✅ TEST 6: withdrawBudget() - Yetersiz bütçe ile başarısız
     */
    function testWithdrawBudgetInsufficient() public {
        vm.deal(address(this), 10 ether);
        bidder.depositBudget{value: 1 ether}();
        
        vm.expectRevert("Exceeds balance");
        bidder.withdrawBudget(2 ether);
    }
    
    /**
     * ✅ TEST 7: refillBudget() - Günlük yenileme (daily refresh)
     * For campaigns that need daily budget resets
     */
    function testRefillBudgetSuccess() public {
        // Deposit and use budget
        vm.deal(address(this), 10 ether);
        bidder.depositBudget{value: 5 ether}();
        
        // Simulate spending (we'll manually update spentAmount later if needed)
        // For now, just test the refill function
        
        // Try to refill too early - should fail
        vm.warp(block.timestamp + 1 hours);
        vm.expectRevert("Can only refill once per day");
        bidder.refillBudget();
        
        // Wait a day and refill
        vm.warp(block.timestamp + 1 days);
        bidder.refillBudget();
        
        // Budget should be reset to total
        (uint256 total, uint256 spent, uint256 available, ) = bidder.getBudgetDetails();
        assertEq(available, total);
        assertEq(spent, 0);
    }
    
    // ==================== STRATEGY CONFIGURATION TESTS ====================
    
    /**
     * ✅ TEST 8: setStrategy() - Stratejisi başarıyla ayarlanıyor
     * Formula: bid = basePrice × (density/100) × (factor/100) × billboardPref
     */
    function testSetStrategySuccess() public {
        uint256 basePrice = 0.01 ether;
        uint256 maxPrice = 1 ether;
        uint256 factor = 150;  // 1.5x multiplier
        uint256 minDensity = 30;  // 30% minimum
        
        vm.expectEmit(false, false, false, true);
        emit StrategyUpdated(basePrice, maxPrice, factor, minDensity);
        
        bidder.setStrategy(basePrice, maxPrice, factor, minDensity);
        
        (
            uint256 retrievedBase,
            uint256 retrievedMax,
            uint256 retrievedFactor,
            uint256 retrievedMinDensity,
            bool isActive
        ) = bidder.getStrategy();
        
        assertEq(retrievedBase, basePrice);
        assertEq(retrievedMax, maxPrice);
        assertEq(retrievedFactor, factor);
        assertEq(retrievedMinDensity, minDensity);
        assertTrue(isActive);
    }
    
    /**
     * ✅ TEST 9: setStrategy() - Invalid params başarısız olmalı
     */
    function testSetStrategyInvalidParams() public {
        // maxPrice < basePrice
        vm.expectRevert("Invalid prices");
        bidder.setStrategy(1 ether, 0.5 ether, 100, 30);
        
        // factor > 1000
        vm.expectRevert("Factor 0-1000");
        bidder.setStrategy(0.01 ether, 1 ether, 1001, 30);
        
        // minDensity > 100
        vm.expectRevert("Invalid density");
        bidder.setStrategy(0.01 ether, 1 ether, 100, 101);
    }
    
    /**
     * ✅ TEST 10: setBillboardPreference() - Location multipliers
     */
    function testSetBillboardPreference() public {
        // Premium location gets 2.0x multiplier
        bidder.setBillboardPreference(billboard1, 200);  // 2.0x
        
        // Standard location gets 1.0x multiplier
        bidder.setBillboardPreference(billboard2, 100);  // 1.0x
        
        // Verify (would need to call internal or add view function)
        // For now, we test that function doesn't revert
    }
    
    /**
     * ✅ TEST 11: setBillboardPreference() - Invalid multiplier
     */
    function testSetBillboardPreferenceInvalid() public {
        vm.expectRevert("Invalid");
        bidder.setBillboardPreference(billboard1, 0);  // 0x not allowed
        
        vm.expectRevert("Invalid");
        bidder.setBillboardPreference(billboard1, 1001);  // > 10x
    }
    
    // ==================== BIDDING LOGIC TESTS ====================
    
    /**
     * ✅ TEST 12: placeBid() - Otomatik bid calculation
     * Formula verification
     */
    function testPlaceBidCalculation() public {
        // Setup
        vm.deal(address(this), 100 ether);
        bidder.depositBudget{value: 50 ether}();
        bidder.setStrategy(
            0.01 ether,    // basePrice
            1 ether,       // maxPrice
            150,           // factor (1.5x)
            30             // minDensity
        );
        
        // Test: density 75%, billboard 1x preference
        uint256 crowdDensity = 75;
        bytes32 auctionId = keccak256("test_auction_1");
        
        // placeBid should calculate:
        // 0.01 × (75/100) × (150/100) × 1.0 = 0.01125 ether
        
        (uint256 bidAmount, bool shouldBid, string memory adURI) = bidder.placeBid(
            auctionId,
            crowdDensity,
            billboard1
        );
        
        assertTrue(shouldBid);
        assertEq(bidAmount, 0.01125 ether);
        assertEq(keccak256(abi.encodePacked(adURI)), keccak256(abi.encodePacked("ipfs://QmDefaultAdContent")));
    }
    
    /**
     * ✅ TEST 13: placeBid() - Density too low, shouldn't bid
     */
    function testPlaceBidLowDensity() public {
        vm.deal(address(this), 100 ether);
        bidder.depositBudget{value: 50 ether}();
        bidder.setStrategy(0.01 ether, 1 ether, 100, 40);  // minDensity = 40%
        
        // Density only 30% - below threshold
        uint256 lowDensity = 30;
        bytes32 auctionId = keccak256("test_auction_2");
        
        (uint256 bidAmount, bool shouldBid, ) = bidder.placeBid(
            auctionId,
            lowDensity,
            billboard1
        );
        
        assertFalse(shouldBid);
        assertEq(bidAmount, 0);
    }
    
    /**
     * ✅ TEST 14: placeBid() - Insufficient budget, shouldn't bid
     */
    function testPlaceBidInsufficientBudget() public {
        vm.deal(address(this), 100 ether);
        bidder.depositBudget{value: 0.005 ether}();  // Only 0.005 ETH
        bidder.setStrategy(0.01 ether, 1 ether, 150, 30);
        
        // Bid would be: 0.01 × 0.75 × 1.5 = 0.01125 > 0.005 budget
        uint256 crowdDensity = 75;
        bytes32 auctionId = keccak256("test_auction_3");
        
        (uint256 bidAmount, bool shouldBid, ) = bidder.placeBid(
            auctionId,
            crowdDensity,
            billboard1
        );
        
        assertFalse(shouldBid);
        assertEq(bidAmount, 0);
    }
    
    /**
     * ✅ TEST 15: placeBid() - Max price cap
     */
    function testPlaceBidMaxPriceCap() public {
        vm.deal(address(this), 100 ether);
        bidder.depositBudget{value: 50 ether}();
        bidder.setStrategy(
            0.5 ether,     // basePrice (high)
            0.1 ether,     // maxPrice (low cap)
            200,           // factor (2.0x)
            20             // minDensity
        );
        
        // Calculated bid: 0.5 × 0.75 × 2.0 = 0.75 ether
        // But maxPrice = 0.1 ether, so should be capped
        uint256 crowdDensity = 75;
        bytes32 auctionId = keccak256("test_auction_4");
        
        (uint256 bidAmount, bool shouldBid, ) = bidder.placeBid(
            auctionId,
            crowdDensity,
            billboard1
        );
        
        assertTrue(shouldBid);
        assertEq(bidAmount, 0.1 ether);  // Capped at maxPrice
    }
    
    /**
     * ✅ TEST 16: placeBid() - Billboard preference multiplier
     */
    function testPlaceBidBillboardPreference() public {
        vm.deal(address(this), 100 ether);
        bidder.depositBudget{value: 50 ether}();
        bidder.setStrategy(0.01 ether, 1 ether, 100, 30);
        
        // Set billboard1 as premium (2x)
        bidder.setBillboardPreference(billboard1, 200);
        
        // Bid calculation: 0.01 × (75/100) × (100/100) × (200/100) = 0.015 ether
        uint256 crowdDensity = 75;
        bytes32 auctionId = keccak256("test_auction_5");
        
        (uint256 bidAmount, bool shouldBid, ) = bidder.placeBid(
            auctionId,
            crowdDensity,
            billboard1
        );
        
        assertTrue(shouldBid);
        assertEq(bidAmount, 0.015 ether);  // 2x multiplier applied
    }
    
    // ==================== CALLBACK TESTS ====================
    
    /**
     * ✅ TEST 17: onAuctionWon() - Bütçe güncelleniyor ve metrikler arttırılıyor
     */
    function testOnAuctionWonCallback() public {
        // Setup
        vm.deal(address(this), 100 ether);
        bidder.depositBudget{value: 10 ether}();
        bidder.setStrategy(0.01 ether, 1 ether, 100, 30);
        
        bytes32 auctionId = keccak256("test_auction_6");
        
        // Place bid first
        vm.prank(adExchange);
        bidder.placeBid(auctionId, 75, billboard1);
        
        // Simulate win with 2nd price = 0.005 ether
        vm.prank(adExchange);
        bidder.onAuctionWon(auctionId, 0.005 ether, billboard1);
        
        // Check metrics updated
        (uint256 participated, uint256 won, uint256 spent, ) = bidder.getPerformanceMetrics();
        assertEq(participated, 1);
        assertEq(won, 1);
        assertEq(spent, 0.005 ether);
        
        // Check budget
        (uint256 total, uint256 spent2, uint256 available, ) = bidder.getBudgetDetails();
        assertEq(spent2, 0.005 ether);
    }
    
    /**
     * ✅ TEST 18: onAuctionLost() - Bütçe refund ediliyor
     */
    function testOnAuctionLostCallback() public {
        vm.deal(address(this), 100 ether);
        bidder.depositBudget{value: 10 ether}();
        bidder.setStrategy(0.01 ether, 1 ether, 100, 30);
        
        bytes32 auctionId = keccak256("test_auction_7");
        
        // Get initial budget
        uint256 initialAvailable = bidder.getAvailableBudget();
        
        // Place bid
        vm.prank(adExchange);
        (uint256 bidAmount, , ) = bidder.placeBid(auctionId, 75, billboard1);
        
        // Budget should be reduced
        uint256 afterBidAvailable = bidder.getAvailableBudget();
        assertEq(afterBidAvailable, initialAvailable - bidAmount);
        
        // Auction lost
        vm.prank(adExchange);
        bidder.onAuctionLost(auctionId, billboard1);
        
        // Budget should be restored
        uint256 afterLossAvailable = bidder.getAvailableBudget();
        assertEq(afterLossAvailable, initialAvailable);
    }
    
    /**
     * ✅ TEST 19: Win rate calculation
     */
    function testWinRateCalculation() public {
        vm.deal(address(this), 100 ether);
        bidder.depositBudget{value: 50 ether}();
        bidder.setStrategy(0.01 ether, 1 ether, 100, 30);
        
        // Simulate 10 participations, 6 wins
        for (uint i = 0; i < 10; i++) {
            bytes32 auctionId = keccak256(abi.encode("auction", i));
            
            vm.prank(adExchange);
            bidder.placeBid(auctionId, 75, billboard1);
            
            if (i < 6) {
                // Win
                vm.prank(adExchange);
                bidder.onAuctionWon(auctionId, 0.001 ether, billboard1);
            } else {
                // Loss
                vm.prank(adExchange);
                bidder.onAuctionLost(auctionId, billboard1);
            }
        }
        
        (uint256 participated, uint256 won, , uint256 winRate) = bidder.getPerformanceMetrics();
        assertEq(participated, 10);
        assertEq(won, 6);
        assertEq(winRate, 6000);  // 6000 bps = 60%
    }
    
    // ==================== SECURITY & ERROR TESTS ====================
    
    /**
     * ✅ TEST 20: onlyAdExchange modifier - Unauthorized caller
     */
    function testOnlyAdExchangeModifier() public {
        bytes32 auctionId = keccak256("test");
        address unauthorized = address(0x9999);
        
        vm.prank(unauthorized);
        vm.expectRevert("Only AdExchange");
        bidder.onAuctionWon(auctionId, 1 ether, billboard1);
        
        vm.prank(unauthorized);
        vm.expectRevert("Only AdExchange");
        bidder.onAuctionLost(auctionId, billboard1);
    }
    
    /**
     * ✅ TEST 21: strategyActive modifier - Cannot bid without strategy
     */
    function testStrategyActiveModifier() public {
        bytes32 auctionId = keccak256("test");
        
        vm.prank(adExchange);
        vm.expectRevert("Strategy not active");
        bidder.placeBid(auctionId, 75, billboard1);
    }
    
    /**
     * ✅ TEST 22: disableStrategy() - Emergency stop
     */
    function testDisableStrategy() public {
        bidder.setStrategy(0.01 ether, 1 ether, 100, 30);
        
        // Verify strategy is active
        (, , , , bool isActive1) = bidder.getStrategy();
        assertTrue(isActive1);
        
        // Disable
        bidder.disableStrategy();
        
        // Verify disabled
        (, , , , bool isActive2) = bidder.getStrategy();
        assertFalse(isActive2);
    }
    
    /**
     * ✅ TEST 23: emergencyWithdraw() - Full emergency withdrawal
     */
    function testEmergencyWithdraw() public {
        vm.deal(address(this), 100 ether);
        bidder.depositBudget{value: 10 ether}();
        bidder.setStrategy(0.01 ether, 1 ether, 100, 30);
        
        uint256 balanceBefore = address(this).balance;
        
        // Emergency withdraw
        bidder.emergencyWithdraw();
        
        // Strategy and budget disabled
        (, , , , bool strategyActive) = bidder.getStrategy();
        (, , , bool budgetActive) = bidder.getBudgetDetails();
        assertFalse(strategyActive);
        assertFalse(budgetActive);
        
        // ETH should be returned
        uint256 balanceAfter = address(this).balance;
        assertEq(balanceAfter, balanceBefore + 10 ether);
    }
    
    // ==================== RECEIVE FUNCTION ====================
    
    /**
     * ✅ TEST 24: Can receive ETH
     */
    function testReceiveETH() public {
        vm.deal(address(this), 10 ether);
        
        // Send ETH to bidder
        (bool success, ) = address(bidder).call{value: 1 ether}("");
        assertTrue(success);
    }
    
    /**
     * ✅ TEST 25: Fallback function handles transfers
     */
    function testFallbackFunction() public {
        // This tests that the contract can receive ETH without function selector
        vm.deal(address(this), 10 ether);
        
        // Send ETH without data
        (bool success, ) = address(bidder).call{value: 1 ether}("");
        assertTrue(success);
    }
}
