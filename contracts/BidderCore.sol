// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IBidder.sol";
import "./interfaces/IOracle.sol";

/**
 * @title Bidder
 * @dev Marka/İşletme tarafından deploy edilen otomatik teklif kontratı
 * Önceden ayarlanmış stratejilere göre otomatik olarak teklif verir
 * 
 * GAS OPTIMIZATION:
 * - Unchecked arithmetic for safe operations
 * - Direct memory writes
 * - Minimal storage writes
 * - Efficient budget tracking
 */
contract Bidder is IBidder {
    
    // ==================== STRUCTS ====================
    
    /**
     * @dev Teklif stratejisi (optimized storage)
     */
    struct BiddingStrategy {
        uint256 basePrice;           // 0.01 ether tipik
        uint256 maxPrice;            // 1 ether tipik
        uint256 crowdDensityFactor;  // 150 = 1.5x multiplier
        uint256 minCrowdDensity;     // 30% minimum threshold
        bool isActive;               // Strateji aktif mi
    }

    /**
     * @dev Bütçe bilgileri
     */
    struct Budget {
        uint256 totalBudget;         // Toplam yatırılan
        uint256 spentAmount;         // Harcanan
        uint256 unallocatedBalance;  // Kullanılabilir
        uint256 lastRefillTime;      // Son doldurma
        bool isActive;
    }

    /**
     * @dev Teklif geçmişi
     */
    struct BidHistory {
        bytes32 auctionId;
        uint256 bidAmount;
        uint256 timestamp;
        bool won;
        uint256 settlementAmount;
    }

    // ==================== STATE VARIABLES ====================
    
    address public owner;
    address public adExchange;
    
    // Strategy management
    BiddingStrategy public strategy;
    mapping(address => uint256) public billboardPreferences;  // Per-billboard multiplier
    
    // Budget management
    Budget public budget;
    mapping(bytes32 => uint256) public auctionBudgetAllocation;  // Per-auction reserve
    
    // History tracking
    BidHistory[] public bidHistory;
    mapping(bytes32 => bool) public auctionParticipated;
    mapping(bytes32 => bool) public auctionWon;
    
    // Performance metrics
    uint256 public totalAuctionsParticipated;
    uint256 public totalAuctionsWon;
    uint256 public totalSpent;
    
    // ==================== EVENTS ====================
    
    event StrategyUpdated(
        uint256 basePrice,
        uint256 maxPrice,
        uint256 crowdDensityFactor,
        uint256 minCrowdDensity
    );

    event BudgetDeposited(
        address indexed depositor,
        uint256 amount,
        uint256 totalBudget
    );

    event BudgetWithdrawn(
        address indexed recipient,
        uint256 amount,
        uint256 remainingBudget
    );

    // ==================== MODIFIERS ====================
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyAdExchange() {
        require(msg.sender == adExchange, "Only AdExchange");
        _;
    }

    modifier strategyActive() {
        require(strategy.isActive, "Strategy not active");
        require(budget.isActive, "Budget not active");
        _;
    }

    // ==================== CONSTRUCTOR ====================
    
    constructor(address _adExchange) {
        owner = msg.sender;
        adExchange = _adExchange;
        
        // Default strategy (inactive)
        strategy = BiddingStrategy({
            basePrice: 0.01 ether,
            maxPrice: 1 ether,
            crowdDensityFactor: 150,
            minCrowdDensity: 30,
            isActive: false
        });
        
        // Default budget
        budget = Budget({
            totalBudget: 0,
            spentAmount: 0,
            unallocatedBalance: 0,
            lastRefillTime: block.timestamp,
            isActive: false
        });
    }

    // ==================== BUDGET FUNCTIONS ====================

    /**
     * @dev Bütçe yatır
     */
    function depositBudget() external payable onlyOwner {
        require(msg.value > 0, "Must deposit > 0");
        
        unchecked {
            budget.totalBudget += msg.value;
            budget.unallocatedBalance += msg.value;
        }
        budget.lastRefillTime = block.timestamp;
        budget.isActive = true;
        
        emit BudgetDeposited(msg.sender, msg.value, budget.totalBudget);
    }

    /**
     * @dev Bütçe çek
     */
    function withdrawBudget(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount > 0");
        require(amount <= budget.unallocatedBalance, "Exceeds balance");
        
        unchecked {
            budget.unallocatedBalance -= amount;
            budget.totalBudget -= amount;
        }
        
        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit BudgetWithdrawn(owner, amount, budget.unallocatedBalance);
    }

    /**
     * @dev Günlük bütçe yenileme (continuous campaigns için)
     */
    function refillBudget() external onlyOwner {
        require(budget.totalBudget > 0, "No budget set");
        
        uint256 timeSinceLastRefill = block.timestamp - budget.lastRefillTime;
        require(timeSinceLastRefill >= 1 days, "Can only refill once per day");
        
        budget.spentAmount = 0;
        budget.unallocatedBalance = budget.totalBudget;
        budget.lastRefillTime = block.timestamp;
    }

    // ==================== STRATEGY FUNCTIONS ====================

    /**
     * @dev Teklif stratejisini ayarla
     * 
     * Formül:
     * Bid = min(basePrice * (density/100) * (factor/100) * billboardPref, maxPrice)
     * 
     * @param basePrice Temel teklif (0.005-0.02 ether)
     * @param maxPrice Maksimum teklif (0.1-1 ether)
     * @param crowdDensityFactor Yoğunluk çarpanı (100-200)
     * @param minCrowdDensity Minimum yoğunluk eşiği (20-40%)
     */
    function setStrategy(
        uint256 basePrice,
        uint256 maxPrice,
        uint256 crowdDensityFactor,
        uint256 minCrowdDensity
    ) external onlyOwner {
        require(basePrice > 0 && maxPrice >= basePrice, "Invalid prices");
        require(
            crowdDensityFactor > 0 && crowdDensityFactor <= 1000,
            "Factor 0-1000"
        );
        require(minCrowdDensity <= 100, "Invalid density");
        
        strategy.basePrice = basePrice;
        strategy.maxPrice = maxPrice;
        strategy.crowdDensityFactor = crowdDensityFactor;
        strategy.minCrowdDensity = minCrowdDensity;
        strategy.isActive = true;
        
        emit StrategyUpdated(basePrice, maxPrice, crowdDensityFactor, minCrowdDensity);
    }

    /**
     * @dev Billboard tercihini ayarla (location-based multiplier)
     * @param billboard Billboard adresi
     * @param preferenceMultiplier 100 = 1x (normal), 150 = 1.5x (premium)
     */
    function setBillboardPreference(
        address billboard,
        uint256 preferenceMultiplier
    ) external onlyOwner {
        require(preferenceMultiplier > 0 && preferenceMultiplier <= 1000, "Invalid");
        billboardPreferences[billboard] = preferenceMultiplier;
    }

    // ==================== CORE BIDDING LOGIC ====================

    /**
     * @dev AdExchange tarafından çağrılır - Otomatik teklif
     * 
     * GAS OPTIMIZATION:
     * - Memory-first calculation
     * - Single storage write (budget allocation)
     * - Early return if conditions not met
     * 
     * @param auctionId Açık artırma ID'si
     * @param crowdDensity Kalabalık yoğunluğu (0-100)
     * @param billboardId Billboard adresi
     * 
     * @return bidAmount Teklif tutarı (0 = no bid)
     * @return shouldBid Teklif verilsin mi
     * @return adURI Reklam content URI
     */
    function placeBid(
        bytes32 auctionId,
        uint256 crowdDensity,
        address billboardId
    )
        external
        override
        onlyAdExchange
        strategyActive()
        returns (
            uint256 bidAmount,
            bool shouldBid,
            string memory adURI
        )
    {
        // 1. Kalabalık yoğunluğu minimum threshold'u aşmalı
        if (crowdDensity < strategy.minCrowdDensity) {
            return (0, false, "");
        }

        // 2. Teklif miktarını hesapla (memory'de)
        uint256 calculatedBid = _calculateBidAmount(
            crowdDensity,
            billboardId
        );

        // 3. Bütçe yeterli mi
        if (calculatedBid > budget.unallocatedBalance) {
            return (0, false, "");
        }

        // 4. Maksimum fiyat kontrolü
        if (calculatedBid > strategy.maxPrice) {
            calculatedBid = strategy.maxPrice;
        }

        // 5. Bütçeyi tahsis et (storage write)
        budget.unallocatedBalance -= calculatedBid;
        auctionBudgetAllocation[auctionId] = calculatedBid;

        // 6. Metrics güncelle
        unchecked {
            totalAuctionsParticipated++;
        }
        auctionParticipated[auctionId] = true;

        // 7. Return
        return (
            calculatedBid,
            true,
            "ipfs://QmDefaultAdContent"  // Default placeholder
        );
    }

    /**
     * @dev AdExchange tarafından çağrılır - Kazanıldığında
     */
    function onAuctionWon(
        bytes32 auctionId,
        uint256 finalPrice,
        address billboardId
    ) external override onlyAdExchange {
        require(auctionParticipated[auctionId], "Not participated");
        
        // Harcanan tutarı güncelle
        unchecked {
            totalSpent += finalPrice;
            totalAuctionsWon++;
            budget.spentAmount += finalPrice;
        }
        
        auctionWon[auctionId] = true;
        
        // Geçmişe ekle
        _recordBidResult(auctionId, true, finalPrice);
        
        emit AuctionWon(auctionId, auctionBudgetAllocation[auctionId], finalPrice);
    }

    /**
     * @dev AdExchange tarafından çağrılır - Kaybedildiğinde
     */
    function onAuctionLost(
        bytes32 auctionId,
        address billboardId
    ) external override onlyAdExchange {
        require(auctionParticipated[auctionId], "Not participated");
        
        // Tahsis edilen bütçeyi serbest bırak
        uint256 allocatedAmount = auctionBudgetAllocation[auctionId];
        if (allocatedAmount > 0) {
            budget.unallocatedBalance += allocatedAmount;
            delete auctionBudgetAllocation[auctionId];
        }
        
        _recordBidResult(auctionId, false, 0);
        
        emit AuctionLost(auctionId, allocatedAmount);
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @dev Mevcut teklif stratejisini görüntüle
     */
    function getStrategy()
        external
        view
        returns (
            uint256 basePrice,
            uint256 maxPrice,
            uint256 crowdDensityFactor,
            uint256 minCrowdDensity,
            bool isActive
        )
    {
        return (
            strategy.basePrice,
            strategy.maxPrice,
            strategy.crowdDensityFactor,
            strategy.minCrowdDensity,
            strategy.isActive
        );
    }

    /**
     * @dev Mevcut kullanılabilir bütçeyi görüntüle
     */
    function getAvailableBudget() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return budget.unallocatedBalance;
    }

    /**
     * @dev Detaylı bütçe bilgisi
     */
    function getBudgetDetails()
        external
        view
        returns (
            uint256 total,
            uint256 spent,
            uint256 available,
            bool isActive
        )
    {
        return (
            budget.totalBudget,
            budget.spentAmount,
            budget.unallocatedBalance,
            budget.isActive
        );
    }

    /**
     * @dev Performans metrikleri
     */
    function getPerformanceMetrics()
        external
        view
        returns (
            uint256 auctionsParticipated,
            uint256 auctionsWon,
            uint256 totalSpentAmount,
            uint256 winRate
        )
    {
        uint256 rate = totalAuctionsParticipated > 0
            ? (totalAuctionsWon * 10000) / totalAuctionsParticipated
            : 0;

        return (
            totalAuctionsParticipated,
            totalAuctionsWon,
            totalSpent,
            rate
        );
    }

    /**
     * @dev Teklif geçmişi
     */
    function getBidHistory()
        external
        view
        returns (BidHistory[] memory)
    {
        return bidHistory;
    }

    /**
     * @dev Geçmiş boyutu
     */
    function getBidHistoryLength() external view returns (uint256) {
        return bidHistory.length;
    }

    // ==================== INTERNAL FUNCTIONS ====================

    /**
     * @dev Teklif miktarını hesapla
     * 
     * Formül:
     * baseBid = basePrice * (crowdDensity / 100) * (factor / 100)
     * withPreference = baseBid * billboardPreference / 100
     * final = min(withPreference, maxPrice)
     * 
     * GAS OPTIMIZATION:
     * - All calculations in memory
     * - Single multiplication pass
     * - Early capping
     */
    function _calculateBidAmount(
        uint256 crowdDensity,
        address billboard
    ) internal view returns (uint256) {
        // 1. Base calculation
        uint256 baseBid = strategy.basePrice;
        
        // 2. Crowd density multiplier
        baseBid = (baseBid * crowdDensity) / 100;
        
        // 3. Strategy factor
        baseBid = (baseBid * strategy.crowdDensityFactor) / 100;
        
        // 4. Billboard preference
        uint256 pref = billboardPreferences[billboard];
        if (pref == 0) {
            pref = 100; // Default 1x
        }
        baseBid = (baseBid * pref) / 100;
        
        // 5. Cap at max price
        if (baseBid > strategy.maxPrice) {
            baseBid = strategy.maxPrice;
        }
        
        return baseBid;
    }

    /**
     * @dev Teklif sonucunu kaydet
     */
    function _recordBidResult(
        bytes32 auctionId,
        bool won,
        uint256 settlementAmount
    ) internal {
        bidHistory.push(
            BidHistory({
                auctionId: auctionId,
                bidAmount: auctionBudgetAllocation[auctionId],
                timestamp: block.timestamp,
                won: won,
                settlementAmount: settlementAmount
            })
        );
    }

    // ==================== EMERGENCY FUNCTIONS ====================

    /**
     * @dev Marka sahibi tarafından stratejiyi deaktive et
     */
    function disableStrategy() external onlyOwner {
        strategy.isActive = false;
    }

    /**
     * @dev Acil durum: Kontratı disable et ve para çek
     */
    function emergencyWithdraw() external onlyOwner {
        strategy.isActive = false;
        budget.isActive = false;
        
        uint256 remaining = budget.unallocatedBalance;
        if (remaining > 0) {
            budget.unallocatedBalance = 0;
            (bool success, ) = payable(owner).call{value: remaining}("");
            require(success, "Emergency withdrawal failed");
        }
    }
}
