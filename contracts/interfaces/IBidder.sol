// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IBidder
 * @dev Marka/Bidder kontratlarının arayüzü - Otomatik teklif stratejisi
 * 
 * Bu arayüz sayesinde AdExchange, herhangi bir bidder kontratı ile iletişim kurabilir.
 * Her marka bu arayüzü implement eden kendi akıllı kontratını deploy eder.
 */
interface IBidder {
    
    // ==================== EVENTS ====================
    
    /**
     * @dev Teklif verme isteği geldiğinde emit edilir
     */
    event BidRequested(
        bytes32 indexed auctionId,
        uint256 crowdDensity,
        uint256 timestamp
    );

    /**
     * @dev Müzayedayı kazandığında
     */
    event AuctionWon(
        bytes32 indexed auctionId,
        uint256 winningBid,
        uint256 settledPrice
    );

    /**
     * @dev Müzayedayı kaybetttiğinde
     */
    event AuctionLost(
        bytes32 indexed auctionId,
        uint256 participatedBid
    );

    // ==================== CORE FUNCTIONS ====================

    /**
     * @dev Ad Exchange tarafından çağrılır. Marka kendi teklif stratejisini kontrol eder
     * 
     * Bu fonksiyon synchronously çağrılır ve çok hızlı respond etmeli (<100ms)
     * 
     * @param auctionId Açık artırma ID'si
     * @param crowdDensity Kalabalık yoğunluğu (0-100)
     * @param billboardId Reklam panı adresi
     * 
     * @return bidAmount Teklif tutarı (wei cinsinden). 0 = teklif yok
     * @return shouldBid Teklif vermek isteyip istemediği (true = verilsin, false = verilmesin)
     * @return adURI Reklam content URI'sı (IPFS, Arweave, vb.)
     * 
     * Requirements:
     * - Bütçe yeterli olmalı
     * - Strateji aktif olmalı
     * - Kalabalık yoğunluğu threshold'u aşmalı
     */
    function placeBid(
        bytes32 auctionId,
        uint256 crowdDensity,
        address billboardId
    ) external returns (
        uint256 bidAmount, 
        bool shouldBid,
        string memory adURI
    );

    /**
     * @dev Açık artırma kazanıldığında AdExchange tarafından çağrılır
     * 
     * @param auctionId Açık artırma ID'si
     * @param finalPrice Kazanılan fiyat (Vickrey - 2nd price)
     * @param billboardId Hangi billboard
     */
    function onAuctionWon(
        bytes32 auctionId,
        uint256 finalPrice,
        address billboardId
    ) external;

    /**
     * @dev Açık artırma kaybedildiğinde AdExchange tarafından çağrılır
     * 
     * @param auctionId Açık artırma ID'si
     * @param billboardId Hangi billboard
     */
    function onAuctionLost(
        bytes32 auctionId,
        address billboardId
    ) external;

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @dev Marka bütçesini sorgula
     * @return availableBudget Kullanılabilir bütçe (wei)
     */
    function getAvailableBudget() external view returns (uint256);

    /**
     * @dev Toplam harcanan tutarı sorgula
     */
    function getTotalSpent() external view returns (uint256);

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
            uint256 winRate  // basis points (10000 = 100%)
        );

    /**
     * @dev Marka sahibi
     */
    function owner() external view returns (address);
}
