// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IBidder.sol";

/**
 * @title Bidder
 * @dev Marka/İşletme tarafından deploy edilen otomatik teklif kontratı
 * Önceden ayarlanmış stratejilere göre otomatik olarak teklif verir
 */
contract Bidder is IBidder {
    
    // ==================== STRUCTS ====================
    
    /**
     * @dev Teklif stratejisi
     */
    struct BiddingStrategy {
        uint256 basePrice;           // Temel fiyat
        uint256 maxPrice;            // Maksimum teklif fiyatı
        uint256 crowdDensityFactor;  // Yoğunluğa göre çarpan (örn. 150 = %1.5x)
        bool isActive;               // Stratejinin aktif olup olmadığı
        uint256 minCrowdDensity;     // Minimum kalabalık yoğunluğu (threshold)
        uint256 budgetAllocation;    // Bu teklif için tahsis edilen bütçe
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

    /**
     * @dev Bütçe bilgileri
     */
    struct Budget {
        uint256 totalBudget;         // Toplam yatırılan bütçe
        uint256 spentAmount;         // Harcanan tutar
        uint256 unallocatedBalance;  // Tahsis edilmemiş bakiye
        uint256 lastRefillTime;      // Son doldurma zamanı
        bool isActive;
    }

    // ==================== STATE VARIABLES ====================
    
    address public owner;
    address public adExchange;       // AdExchange kontrat adresi
    
    // Strateji yönetimi
    BiddingStrategy public strategy;
    mapping(address => uint256) public billboardPreferences;  // Billboard tercihini belirler
    
    // Bütçe yönetimi
    Budget public budget;
    mapping(bytes32 => uint256) public auctionBudgetAllocation;  // Müzayedaya tahsis edilen bütçe
    
    // Geçmiş takibi
    BidHistory[] public bidHistory;
    mapping(bytes32 => uint256) public auctionResults;  // Müzayedanın sonucu (0 = kaybetti, amount = kazandı)
    
    // Performans metrikleri
    uint256 public totalAuctionsParticipated;
    uint256 public totalAuctionsWon;
    uint256 public totalSpent;
    
    // ==================== EVENTS ====================
    
    /**
     * @dev Strateji güncellendi
     */
    event StrategyUpdated(
        uint256 basePrice,
        uint256 maxPrice,
        uint256 crowdDensityFactor,
        uint256 minCrowdDensity
    );

    /**
     * @dev Bütçe yatırıldı
     */
    event BudgetDeposited(
        address indexed depositor,
        uint256 amount,
        uint256 totalBudget
    );

    /**
     * @dev Bütçe çekildi
     */
    event BudgetWithdrawn(
        address indexed recipient,
        uint256 amount,
        uint256 remainingBudget
    );

    /**
     * @dev Teklif yapıldı (AdExchange tarafından çağrılır)
     */
    event BidSubmitted(
        bytes32 indexed auctionId,
        uint256 bidAmount,
        uint256 crowdDensity
    );

    /**
     * @dev Müzayedayı kazandı
     */
    event AuctionWon(
        bytes32 indexed auctionId,
        uint256 winAmount,
        address indexed billboard
    );

    /**
     * @dev Müzayedayı kaybetti
     */
    event AuctionLost(
        bytes32 indexed auctionId,
        address indexed billboard
    );

    /**
     * @dev Ödeme geri alındı
     */
    event SettlementReceived(
        bytes32 indexed auctionId,
        uint256 settlementAmount,
        uint256 refundedAmount
    );

    // ==================== MODIFIERS ====================
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyAdExchange() {
        require(msg.sender == adExchange, "Only AdExchange contract");
        _;
    }

    modifier budgetAvailable(uint256 amount) {
        require(budget.unallocatedBalance >= amount, "Insufficient budget");
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
        
        // Varsayılan strateji
        strategy = BiddingStrategy({
            basePrice: 0.01 ether,
            maxPrice: 1 ether,
            crowdDensityFactor: 150,  // %1.5x çarpan
            isActive: false,
            minCrowdDensity: 30,      // %30 üzerinde
            budgetAllocation: 0
        });
        
        // Varsayılan bütçe
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
        require(msg.value > 0, "Must deposit amount > 0");
        
        budget.totalBudget += msg.value;
        budget.unallocatedBalance += msg.value;
        budget.lastRefillTime = block.timestamp;
        budget.isActive = true;
        
        emit BudgetDeposited(msg.sender, msg.value, budget.totalBudget);
    }

    /**
     * @dev Bütçe çek (gazma kullanılmayan)
     */
    function withdrawBudget(uint256 amount) external onlyOwner {
        require(amount <= budget.unallocatedBalance, "Amount exceeds unallocated balance");
        
        budget.unallocatedBalance -= amount;
        budget.totalBudget -= amount;
        
        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit BudgetWithdrawn(owner, amount, budget.unallocatedBalance);
    }

    /**
     * @dev Günlük bütçe yenileme (opsiyonel - sürekli kampanya için)
     */
    function refillBudget() external onlyOwner {
        require(budget.totalBudget > 0, "No budget set");
        
        uint256 timeSinceLastRefill = block.timestamp - budget.lastRefillTime;
        require(timeSinceLastRefill >= 1 days, "Can only refill once per day");
        
        // Harcanan bütçeyi resetle
        budget.spentAmount = 0;
        budget.unallocatedBalance = budget.totalBudget;
        budget.lastRefillTime = block.timestamp;
    }

    // ==================== STRATEGY FUNCTIONS ====================

    /**
     * @dev Teklif stratejisini ayarla
     */
    function setStrategy(
        uint256 basePrice,
        uint256 maxPrice,
        uint256 crowdDensityFactor,
        uint256 minCrowdDensity
    ) external onlyOwner {
        require(basePrice > 0 && maxPrice >= basePrice, "Invalid prices");
        require(crowdDensityFactor > 0 && crowdDensityFactor <= 1000, "Invalid factor"); // 0-10x
        require(minCrowdDensity >= 0 && minCrowdDensity <= 100, "Invalid density");
        
        strategy.basePrice = basePrice;
        strategy.maxPrice = maxPrice;
        strategy.crowdDensityFactor = crowdDensityFactor;
        strategy.minCrowdDensity = minCrowdDensity;
        strategy.isActive = true;
        
        emit StrategyUpdated(basePrice, maxPrice, crowdDensityFactor, minCrowdDensity);
    }

    /**
     * @dev Belirli bir billboard için tercih ayarla
     */
    function setBillboardPreference(
        address billboard,
        uint256 preferenceMultiplier  // 100 = normal, 150 = 1.5x teklif ver
    ) external onlyOwner {
        require(preferenceMultiplier > 0 && preferenceMultiplier <= 1000, "Invalid multiplier");
        billboardPreferences[billboard] = preferenceMultiplier;
    }

    // ==================== CORE BIDDING LOGIC ====================

    /**
     * @dev IBidder arayüzü - AdExchange tarafından çağrılır
     * Marka kendi teklif stratejisini burada uygular
     */
    function placeBid(
        bytes32 auctionId,
        uint256 crowdDensity
    ) external onlyAdExchange override returns (uint256 bidAmount, bool shouldBid) {
        // 1. Strateji kontrol et (aktif mi, kalabalık yoğunluğu yeterli mi)
        // 2. Teklif miktarını hesapla: basePrice * (crowdDensity / 100) * (crowdDensityFactor / 100)
        // 3. Bütçe yeterli mi kontrol et
        // 4. Billboard tercihini uygula
        // 5. Maksimum fiyat sınırını kontrol et
        // 6. Bütçeyi tahsis et
    }

    /**
     * @dev IBidder arayüzü - Açık artırma kazanıldığında
     */
    function onAuctionWon(
        bytes32 auctionId,
        uint256 winAmount
    ) external onlyAdExchange override {
        // 1. Harcanan tutarı güncelle
        // 2. Tahsis edilen bütçeyi sil
        // 3. Sonucu kaydet
        // 4. Event emit et
    }

    /**
     * @dev IBidder arayüzü - Açık artırma kaybedildiğinde
     */
    function onAuctionLost(bytes32 auctionId) external onlyAdExchange override {
        // 1. Tahsis edilen bütçeyi serbest bırak
        // 2. Sonucu kaydet
        // 3. Event emit et
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
     * @dev Mevcut bütçeyi görüntüle
     */
    function getAvailableBudget() external view override returns (uint256) {
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
            uint256 totalSpent,
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
            rate  // basis points (100 = 1%)
        );
    }

    /**
     * @dev Teklif geçmişini görüntüle
     */
    function getBidHistory() 
        external 
        view 
        returns (BidHistory[] memory) 
    {
        return bidHistory;
    }

    /**
     * @dev Belirli bir teklif geçmişi
     */
    function getBidHistoryCount() external view returns (uint256) {
        return bidHistory.length;
    }

    // ==================== INTERNAL FUNCTIONS ====================

    /**
     * @dev Teklif miktarını hesapla
     */
    function _calculateBidAmount(
        uint256 crowdDensity,
        address billboard
    ) internal view returns (uint256) {
        // 1. Temel fiyat * kalabalık yoğunluğu çarpanı
        // 2. Billboard tercihini uygula
        // 3. Maksimum fiyat sınırını uygula
    }

    /**
     * @dev Teklif geçmişine ekle
     */
    function _recordBid(
        bytes32 auctionId,
        uint256 bidAmount
    ) internal {
        bidHistory.push(BidHistory({
            auctionId: auctionId,
            bidAmount: bidAmount,
            timestamp: block.timestamp,
            won: false,
            settlementAmount: 0
        }));
        totalAuctionsParticipated++;
    }
}
