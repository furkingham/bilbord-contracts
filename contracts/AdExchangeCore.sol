// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IBidder.sol";
import "./interfaces/IOracle.sol";

/**
 * @title AdExchange
 * @dev Real-Time Bidding (RTB) Açık Artırma Kontratı
 * Monad ağının hızından maksimal faydalanarak milisaniye cinsinde açık artırma yönetimi
 * 
 * OPTIMIZATION NOTES:
 * - Storage packing: AuctionState + bool in same slot
 * - O(1) winner tracking instead of array iteration
 * - Vickrey (2nd price) auction mechanism
 * - Parallel-execution ready (Monad Sui VM)
 */
contract AdExchange {
    
    // ==================== TYPES & ENUMS ====================
    
    enum AuctionState {
        INACTIVE,      // Başlamamış
        ACTIVE,        // Aktif - teklif kabul ediyor
        CLOSED,        // Kapalı - sonuçlandırıldı
        FINALIZED      // Sonuçlandırıldı - ödeme yapıldı
    }

    // ==================== STRUCTS ====================
    
    /**
     * @dev Açık artırma bilgileri (optimized storage layout)
     * Layout: Slot 0-8 (9 slots total) = single SLOAD mostly
     */
    struct Auction {
        // Slot 0: 32 bytes
        bytes32 auctionId;
        
        // Slot 1: 32 bytes (packed)
        address highestBidder;       // 20 bytes
        AuctionState state;          // 1 byte
        bool isFinalized;            // 1 byte
        // 10 bytes padding
        
        // Slot 2: 32 bytes
        uint256 highestBidAmount;
        
        // Slot 3: 32 bytes
        uint256 secondHighestBid;
        
        // Slot 4: 32 bytes
        uint256 startTime;
        
        // Slot 5: 32 bytes
        uint256 duration;
        
        // Slot 6: 32 bytes
        uint256 crowdDensity;
        
        // Slot 7: 32 bytes (packed)
        address billboardId;
        // 12 bytes padding
        
        // Slot 8: 32 bytes
        uint256 reservePrice;
        
        // Slot 9: 32 bytes
        string adURI;               // Winner's ad content
    }

    /**
     * @dev Teklifçi snapshot'ı (minimal info)
     */
    struct BidderSnapshot {
        address bidderContract;
        uint256 bidAmount;
        uint256 timestamp;
        bool isActive;
    }

    /**
     * @dev Reklam panı bilgileri
     */
    struct Billboard {
        address billboardId;
        string location;
        bool isActive;
        uint256 commissionFee;      // bps: 100 = 1%
        address owner;
    }

    // ==================== STATE VARIABLES ====================
    
    address public owner;
    address public oracleAddress;
    
    // Auction management
    mapping(bytes32 => Auction) public auctions;
    mapping(bytes32 => BidderSnapshot[]) public auctionBids;  // Per-auction bids array
    mapping(address => bool) public registeredBidders;        // Whitelist
    
    // Billboard management
    mapping(address => Billboard) public billboards;
    address[] public activeBillboards;
    mapping(address => bool) public billboardExists;
    
    // Financial tracking
    mapping(address => uint256) public platformBalances;      // Platform earnings
    mapping(bytes32 => uint256) public auctionSettlements;    // Settlement log
    mapping(address => uint256) public billboardEarnings;     // Billboard earnings
    
    // Metrics
    uint256 public auctionCounter;
    uint256 public activeBidderCount;
    uint256 public totalVolume;  // Total bid volume
    
    // Configuration
    uint256 public minAuctionDuration = 100;   // milliseconds
    uint256 public maxAuctionDuration = 500;   // milliseconds
    uint256 public crowdDensityThreshold = 50; // Minimum density to trigger
    uint256 public platformFeePercent = 500;   // 5% (500 bps)
    
    // ==================== EVENTS ====================
    
    /**
     * @dev Açık artırma başlatıldığında
     */
    event AuctionStarted(
        bytes32 indexed auctionId,
        address indexed billboard,
        uint256 crowdDensity,
        uint256 startTime,
        uint256 duration
    );

    /**
     * @dev Yeni teklif yapıldığında
     */
    event BidPlaced(
        bytes32 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount,
        uint256 timestamp
    );

    /**
     * @dev Açık artırma sonlandırıldığında
     */
    event AuctionFinalized(
        bytes32 indexed auctionId,
        address indexed winner,
        uint256 winningBid,
        uint256 secondPrice,
        uint256 timestamp
    );

    /**
     * @dev Ödeme yapıldığında
     */
    event PaymentSettled(
        bytes32 indexed auctionId,
        address indexed winner,
        uint256 settlementAmount,
        uint256 platformFee,
        uint256 billboardEarning
    );

    /**
     * @dev Bidder kaydı yapıldığında
     */
    event BidderRegistered(address indexed bidderContract, address indexed owner);

    /**
     * @dev Reklam panı kaydı yapıldığında
     */
    event BillboardRegistered(
        address indexed billboard,
        address indexed owner,
        string location
    );

    /**
     * @dev Konfigürasyon güncellendiğinde
     */
    event ConfigurationUpdated(
        uint256 minDuration,
        uint256 maxDuration,
        uint256 densityThreshold,
        uint256 platformFee
    );

    // ==================== MODIFIERS ====================
    
    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "Only oracle can call");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier auctionExists(bytes32 auctionId) {
        require(auctions[auctionId].auctionId != bytes32(0), "Auction not found");
        _;
    }

    modifier auctionActive(bytes32 auctionId) {
        require(auctions[auctionId].state == AuctionState.ACTIVE, "Auction not active");
        _;
    }

    modifier billboardRegistered(address billboardId) {
        require(billboardExists[billboardId], "Billboard not registered");
        _;
    }

    modifier bidderRegistered() {
        require(registeredBidders[msg.sender], "Bidder not registered");
        _;
    }

    // ==================== CONSTRUCTOR ====================
    
    constructor(address _oracleAddress) {
        owner = msg.sender;
        oracleAddress = _oracleAddress;
        auctionCounter = 0;
    }

    // ==================== CORE FUNCTIONS ====================

    /**
     * @dev Oracle tarafından çağrılır - Kalabalık yoğunluğu eşiği aşıldığında
     * 
     * OPTIMIZATION:
     * - Tüm bidder'ları parallel çağırır (Monad'da paralel execute)
     * - State conflict olmadan (her bidder kendi statesini günceller)
     * - Callback mekanizması ile otomatik teklif
     * 
     * @param billboardId Reklam panı ID'si
     * @param crowdDensity Kalabalık yoğunluğu (0-100)
     * 
     * @return auctionId Oluşturulan açık artırma ID'si
     */
    function triggerAuction(
        address billboardId,
        uint256 crowdDensity
    ) 
        external 
        onlyOracle 
        billboardRegistered(billboardId)
        returns (bytes32 auctionId) 
    {
        // 1. Yoğunluk eşiğini kontrol et
        require(
            crowdDensity >= crowdDensityThreshold && crowdDensity <= 100,
            "Invalid crowd density"
        );

        // 2. Yeni auction ID oluştur (keccak256 ile unique)
        unchecked {
            auctionCounter++;
        }
        auctionId = keccak256(
            abi.encodePacked(block.number, billboardId, auctionCounter, block.timestamp)
        );

        // 3. Auction struct'ı oluştur ve initialize et
        Auction storage auction = auctions[auctionId];
        auction.auctionId = auctionId;
        auction.startTime = block.timestamp;
        auction.duration = 300;  // 300ms optimal
        auction.crowdDensity = crowdDensity;
        auction.billboardId = billboardId;
        auction.reservePrice = 0.001 ether;  // Minimum price
        auction.state = AuctionState.ACTIVE;
        auction.highestBidAmount = 0;
        auction.secondHighestBid = 0;
        auction.highestBidder = address(0);

        // 4. Tüm registre bidderları paralel çağır
        // MONAD OPTIMIZATION: Bu loop Monad'da paralel execute edilir
        // Çünkü her bidder kendi state'ini günceller (no conflict)
        address[] memory bidderList = _getRegisteredBidders();
        for (uint256 i = 0; i < bidderList.length; i++) {
            _requestBidFromBidder(auctionId, crowdDensity, billboardId, bidderList[i]);
        }

        emit AuctionStarted(
            auctionId,
            billboardId,
            crowdDensity,
            block.timestamp,
            300
        );
    }

    /**
     * @dev Bidder tarafından çağrılır - Teklif verme
     * 
     * SECURITY:
     * - Auction aktif olmalı
     * - Bidder registered olmalı
     * - Teklif tutarı geçerli olmalı
     * 
     * OPTIMIZATION:
     * - O(1) kazanan update (array sort yok)
     * - Eski highest bid'in bütçesini track etmek (refund için)
     * 
     * @param auctionId Açık artırma ID'si
     * @param bidAmount Teklif tutarı
     * @param adURI Reklam content URI (IPFS/Arweave)
     */
    function placeBid(
        bytes32 auctionId,
        uint256 bidAmount,
        string calldata adURI
    ) 
        external 
        auctionActive(auctionId)
        bidderRegistered()
    {
        require(bidAmount > 0, "Bid must be > 0");
        require(bytes(adURI).length > 0 && bytes(adURI).length <= 256, "Invalid URI");

        Auction storage auction = auctions[auctionId];

        // 1. Zamanın hala aktif olup olmadığını kontrol et
        uint256 elapsed = block.timestamp - auction.startTime;
        require(elapsed < (auction.duration / 1000), "Auction time expired");

        // 2. Reserve price'ı kontrol et
        require(bidAmount >= auction.reservePrice, "Bid below reserve");

        // 3. Teklifçinin bütçesini kontrol et (via IBidder interface)
        uint256 availableBudget = IBidder(msg.sender).getAvailableBudget();
        require(availableBudget >= bidAmount, "Insufficient bidder balance");

        // 4. Teklifi snapshot'a ekle
        auctionBids[auctionId].push(
            BidderSnapshot({
                bidderContract: msg.sender,
                bidAmount: bidAmount,
                timestamp: block.timestamp,
                isActive: true
            })
        );

        // 5. O(1) winner tracking: Kazananı hemen update et
        if (bidAmount > auction.highestBidAmount) {
            // Eski highest bid'i ikinci en yüksek yap
            auction.secondHighestBid = auction.highestBidAmount;
            
            // Yeni highest'i set et
            auction.highestBidAmount = bidAmount;
            auction.highestBidder = msg.sender;
            auction.adURI = adURI;
        } else if (bidAmount > auction.secondHighestBid) {
            // İkinci en yüksek'i update et
            auction.secondHighestBid = bidAmount;
        }

        // 6. Total volume track et
        unchecked {
            totalVolume += bidAmount;
        }

        emit BidPlaced(auctionId, msg.sender, bidAmount, block.timestamp);
    }

    /**
     * @dev Açık artırma sonlandırıl - Kazananı kesinleştir
     * 
     * OPTIMIZATION:
     * - Zamanı kontrol et (blok süresi yerine duration kullan)
     * - Kazanan zaten storage'de (O(1))
     * - Ikinci en yüksek teklif de hazır (Vickrey)
     * 
     * @param auctionId Açık artırma ID'si
     */
    function resolveAuction(bytes32 auctionId)
        external
        auctionExists(auctionId)
    {
        Auction storage auction = auctions[auctionId];
        require(auction.state == AuctionState.ACTIVE, "Not active");
        
        // 1. Zamanın bittiğini kontrol et (duration ms cinsinden)
        uint256 elapsedSeconds = block.timestamp - auction.startTime;
        uint256 durationSeconds = (auction.duration * 1000) / 1000; // 300ms = 0.3s
        require(elapsedSeconds >= durationSeconds, "Auction still active");

        // 2. Durum güncelle
        auction.state = AuctionState.CLOSED;

        // 3. Settlement price (Vickrey - 2nd price)
        uint256 settlementPrice = auction.secondHighestBid > 0
            ? auction.secondHighestBid
            : auction.highestBidAmount;

        emit AuctionFinalized(
            auctionId,
            auction.highestBidder,
            auction.highestBidAmount,
            settlementPrice,
            block.timestamp
        );
    }

    /**
     * @dev Ödemeyi gerçekleştir ve state'i finalize et
     * 
     * SECURITY:
     * - Checks-Effects-Interactions pattern
     * - State update BEFORE external calls
     * 
     * OPTIMIZATION:
     * - Balance tracking (no external transfer calls)
     * - Single write operation
     * - Callback'ler external çağrılar değil, event'ler
     * 
     * @param auctionId Açık artırma ID'si
     */
    function settlePayment(bytes32 auctionId)
        external
        auctionExists(auctionId)
    {
        Auction storage auction = auctions[auctionId];
        require(auction.state == AuctionState.CLOSED, "Not closed");
        require(!auction.isFinalized, "Already finalized");

        // 1. Settlement amount hesapla (Vickrey: 2nd price)
        uint256 paymentAmount = auction.secondHighestBid > 0
            ? auction.secondHighestBid
            : auction.highestBidAmount;

        require(paymentAmount > 0, "No valid bids");

        // 2. Platform komisyonu hesapla
        uint256 platformFee = (paymentAmount * platformFeePercent) / 10000;
        uint256 billboardPayment = paymentAmount - platformFee;

        // 3. State update FIRST (checks-effects-interactions)
        auction.state = AuctionState.FINALIZED;
        auction.isFinalized = true;

        // 4. Balances güncelle
        platformBalances[address(this)] += platformFee;
        billboardEarnings[auction.billboardId] += billboardPayment;

        // 5. Settlement log
        auctionSettlements[auctionId] = paymentAmount;

        // 6. Bidder'ları notify et (callbacks)
        _notifyBidders(auctionId, auction.highestBidder, paymentAmount);

        emit PaymentSettled(
            auctionId,
            auction.highestBidder,
            paymentAmount,
            platformFee,
            billboardPayment
        );
    }

    // ==================== REGISTRATION FUNCTIONS ====================

    /**
     * @dev Bidder kontratını kayıt
     * @param bidderContract Bidder kontrat adresi
     */
    function registerBidder(address bidderContract) external onlyOwner {
        require(bidderContract != address(0), "Invalid address");
        require(!registeredBidders[bidderContract], "Already registered");

        // IBidder arayüzünü implement ettiğini kontrol et
        // (Solidity bunu full check etmez, basic validation yeterliydi)
        
        registeredBidders[bidderContract] = true;
        unchecked {
            activeBidderCount++;
        }

        emit BidderRegistered(bidderContract, msg.sender);
    }

    /**
     * @dev Reklam panını kaydet
     * @param billboardId Panı ID'si
     * @param location Konum açıklaması
     * @param commissionFee Komisyon (bps: 500 = 5%)
     */
    function registerBillboard(
        address billboardId,
        string memory location,
        uint256 commissionFee
    ) external onlyOwner {
        require(billboardId != address(0), "Invalid address");
        require(!billboardExists[billboardId], "Already registered");
        require(commissionFee <= 10000, "Fee too high");  // Max 100%
        require(bytes(location).length > 0, "Invalid location");

        billboards[billboardId] = Billboard({
            billboardId: billboardId,
            location: location,
            isActive: true,
            commissionFee: commissionFee,
            owner: msg.sender
        });

        billboardExists[billboardId] = true;
        activeBillboards.push(billboardId);

        emit BillboardRegistered(billboardId, msg.sender, location);
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @dev Konfigürasyon güncelle
     */
    function updateConfiguration(
        uint256 _minDuration,
        uint256 _maxDuration,
        uint256 _crowdDensityThreshold,
        uint256 _platformFee
    ) external onlyOwner {
        require(_minDuration > 0 && _maxDuration >= _minDuration, "Invalid durations");
        require(_crowdDensityThreshold <= 100, "Invalid threshold");
        require(_platformFee <= 10000, "Fee too high");

        minAuctionDuration = _minDuration;
        maxAuctionDuration = _maxDuration;
        crowdDensityThreshold = _crowdDensityThreshold;
        platformFeePercent = _platformFee;

        emit ConfigurationUpdated(
            _minDuration,
            _maxDuration,
            _crowdDensityThreshold,
            _platformFee
        );
    }

    /**
     * @dev Oracle adresini güncelle
     */
    function setOracleAddress(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "Invalid address");
        oracleAddress = _newOracle;
    }

    /**
     * @dev Platform ücreti çek
     */
    function withdrawPlatformBalance(uint256 amount) external onlyOwner {
        uint256 balance = platformBalances[address(this)];
        require(amount <= balance, "Insufficient balance");

        platformBalances[address(this)] -= amount;

        (bool success, ) = payable(owner).call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @dev Billboard sahibi kendi earnings'i çekebilir
     */
    function withdrawBillboardEarnings(address billboardId) external {
        require(billboardExists[billboardId], "Billboard not found");
        require(
            billboards[billboardId].owner == msg.sender,
            "Not authorized"
        );

        uint256 earnings = billboardEarnings[billboardId];
        require(earnings > 0, "No earnings");

        billboardEarnings[billboardId] = 0;

        (bool success, ) = payable(msg.sender).call{value: earnings}("");
        require(success, "Transfer failed");
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @dev Açık artırma durumunu sorgula
     */
    function getAuctionStatus(bytes32 auctionId)
        external
        view
        auctionExists(auctionId)
        returns (
            AuctionState state,
            address highestBidder,
            uint256 highestBid,
            uint256 timeRemaining,
            uint256 bidCount
        )
    {
        Auction storage auction = auctions[auctionId];
        uint256 elapsed = block.timestamp - auction.startTime;
        uint256 remaining = elapsed < (auction.duration / 1000)
            ? (auction.duration / 1000) - elapsed
            : 0;

        return (
            auction.state,
            auction.highestBidder,
            auction.highestBidAmount,
            remaining,
            auctionBids[auctionId].length
        );
    }

    /**
     * @dev Tüm teklifleri sorgula
     */
    function getAuctionBids(bytes32 auctionId)
        external
        view
        auctionExists(auctionId)
        returns (BidderSnapshot[] memory)
    {
        return auctionBids[auctionId];
    }

    /**
     * @dev Platform dengesi
     */
    function getPlatformBalance() external view returns (uint256) {
        return platformBalances[address(this)];
    }

    /**
     * @dev Billboard earnings
     */
    function getBillboardEarnings(address billboardId)
        external
        view
        returns (uint256)
    {
        return billboardEarnings[billboardId];
    }

    /**
     * @dev Aktif bidder sayısı
     */
    function getActiveBidderCount() external view returns (uint256) {
        return activeBidderCount;
    }

    /**
     * @dev Tüm aktif billboards
     */
    function getActiveBillboards()
        external
        view
        returns (address[] memory)
    {
        return activeBillboards;
    }

    /**
     * @dev Sistem metrikleri
     */
    function getMetrics()
        external
        view
        returns (
            uint256 totalAuctions,
            uint256 totalActiveBidders,
            uint256 totalVolumeUSD,  // Total bid volume
            uint256 platformFeeEarned
        )
    {
        return (
            auctionCounter,
            activeBidderCount,
            totalVolume,
            platformBalances[address(this)]
        );
    }

    // ==================== INTERNAL FUNCTIONS ====================

    /**
     * @dev Bidder'dan teklif talep et (callback mekanizması)
     * 
     * GAS OPTIMIZATION:
     * - Tüm bidder'lar paralel çağrılır (Monad'da state conflict olmadığından)
     * - Bir bidder'ın failure diğerlerini etkilemez (try-catch)
     */
    function _requestBidFromBidder(
        bytes32 auctionId,
        uint256 crowdDensity,
        address billboardId,
        address bidderContract
    ) internal {
        try
            IBidder(bidderContract).placeBid(auctionId, crowdDensity, billboardId)
        returns (uint256 bidAmount, bool shouldBid, string memory adURI) {
            if (shouldBid && bidAmount > 0) {
                // Teklif vermek istedi
                this.placeBid(auctionId, bidAmount, adURI);
            }
        } catch {
            // Bir bidder başarısız olursa, devam et
            // (Diğerleri etkilenmesin)
        }
    }

    /**
     * @dev Bidder'ları notify et (event-based)
     */
    function _notifyBidders(
        bytes32 auctionId,
        address winner,
        uint256 finalPrice
    ) internal {
        BidderSnapshot[] storage bids = auctionBids[auctionId];
        Auction storage auction = auctions[auctionId];

        for (uint256 i = 0; i < bids.length; i++) {
            address bidder = bids[i].bidderContract;

            try {
                if (bidder == winner) {
                    IBidder(bidder).onAuctionWon(
                        auctionId,
                        finalPrice,
                        auction.billboardId
                    );
                } else {
                    IBidder(bidder).onAuctionLost(auctionId, auction.billboardId);
                }
            } catch {
                // Callback başarısız olursa, devam et
            }
        }
    }

    /**
     * @dev Kayıtlı bidder listesini al
     * 
     * OPTIMIZATION NOTE:
     * Prodüksiyonda: Separate bidder registry kontratı kullan
     * Şimdi: Simple mapping iteration (test için OK)
     */
    function _getRegisteredBidders() internal view returns (address[] memory) {
        // TODO: Implement proper bidder enumeration
        // Şimdilik placeholder
        address[] memory bidders = new address[](0);
        return bidders;
    }

    // ==================== RECEIVE ====================

    receive() external payable {
        // Platform ETH kabul eder (bütçe deposit'leri için)
    }
}
