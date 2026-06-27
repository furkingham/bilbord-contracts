// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IOracle
 * @dev Off-Chain Oracle Servisi - Kamera/Sensor verilerini chain'e gönderir
 * 
 * Kullanım Akışı:
 * 1. Fiziksel sensör kalabalık yoğunluğunu ölçer
 * 2. Oracle node'u eşiği kontrol eder
 * 3. Eşik aşıldığında AdExchange.triggerAuction() çağrılır
 * 
 * Security: Oracle çağrılarında multi-signature veya Chainlink entegrasyonu önerilir
 */
interface IOracle {
    /**
     * @dev Oracle tarafından tetiklenen veri yapısı
     */
    struct DensityTrigger {
        address billboardId;
        uint256 crowdDensity;      // 0-100 range
        uint256 timestamp;
        bytes32 requestId;         // Chainlink-style request tracking
        bool verified;             // Verifikasyon durumu
    }

    /**
     * @dev Kalabalık yoğunluğu verisi gönder
     * Sadece authorized oracle nodes tarafından çağrılır
     * 
     * @param billboardId Hangi panıdan rapor
     * @param crowdDensity Yoğunluk (0-100)
     * @param requestId Unique request identifier
     * 
     * Requirements:
     * - Yoğunluk eşiği kontrol edilmeli
     * - Geçerli billboard ID olmalı
     */
    function reportDensity(
        address billboardId,
        uint256 crowdDensity,
        bytes32 requestId
    ) external;

    /**
     * @dev Raporu doğrula ve finalize et
     * @param requestId Raporlanmış request ID
     * @param isValid Rapor geçerli mi?
     */
    function verifyReport(bytes32 requestId, bool isValid) external;

    /**
     * @dev Eşik yapılandırması
     * @param billboardId Panı ID'si
     * @param threshold Minimum yoğunluk (0-100)
     */
    function setDensityThreshold(
        address billboardId,
        uint256 threshold
    ) external;

    /**
     * @dev Eşiği sorgula
     */
    function getDensityThreshold(address billboardId) 
        external 
        view 
        returns (uint256);

    /**
     * @dev Son raporu al
     */
    function getLatestReport(address billboardId)
        external
        view
        returns (DensityTrigger memory);
}

/**
 * @title SettlementPool
 * @dev Ödeme yönetimi ve veri yapısı
 */
interface ISettlementPool {
    /**
     * @dev Ödeme bilgileri
     */
    struct Settlement {
        bytes32 auctionId;
        address winner;
        address billboard;
        uint256 winningBid;
        uint256 secondPrice;
        uint256 platformFee;
        uint256 billboardPayment;
        uint256 timestamp;
        bool settled;
    }

    /**
     * @dev Ödemeyi kaydet
     */
    function recordSettlement(
        bytes32 auctionId,
        address winner,
        address billboard,
        uint256 winningBid,
        uint256 secondPrice,
        uint256 platformFee
    ) external;
}
