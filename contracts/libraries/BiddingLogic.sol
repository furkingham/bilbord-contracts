// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BiddingLibrary
 * @dev Gas-optimized calculation utilities for bidding mechanism
 * 
 * OPTIMIZATION FOCUS:
 * - Minimal storage reads
 * - Efficient mathematical operations
 * - Inline assembly where beneficial
 */
library BiddingLibrary {
    
    /**
     * @dev Calculate bid amount with crowd density multiplier
     * 
     * Formula: basePrice * (density/100) * (factor/100) * preference
     * 
     * @param basePrice Base bid amount
     * @param crowdDensity Crowd percentage (0-100)
     * @param densityFactor Amplification factor (100-1000)
     * @param preferenceMultiplier Location preference (100-1000)
     * @param maxPrice Maximum allowed bid
     * 
     * @return calculatedBid Final bid amount, capped at maxPrice
     */
    function calculateBidAmount(
        uint256 basePrice,
        uint256 crowdDensity,
        uint256 densityFactor,
        uint256 preferenceMultiplier,
        uint256 maxPrice
    ) internal pure returns (uint256) {
        unchecked {
            // 1. Apply density (crowdDensity / 100)
            uint256 result = basePrice * crowdDensity / 100;
            
            // 2. Apply factor (factor / 100)
            result = result * densityFactor / 100;
            
            // 3. Apply preference (prefer / 100)
            result = result * preferenceMultiplier / 100;
            
            // 4. Cap at max
            if (result > maxPrice) {
                result = maxPrice;
            }
            
            return result;
        }
    }

    /**
     * @dev Calculate Vickrey payment (2nd price)
     * 
     * In Vickrey auction, winner pays 2nd highest bid
     * This is economically efficient and incentive compatible
     * 
     * @param highestBid The winning bid
     * @param secondHighestBid The runner-up bid
     * 
     * @return paymentAmount Amount winner should pay
     */
    function calculateVickreyPayment(
        uint256 highestBid,
        uint256 secondHighestBid
    ) internal pure returns (uint256) {
        // Use 2nd highest if available, else use highest
        // (happens when only 1 bidder)
        return secondHighestBid > 0 ? secondHighestBid : highestBid;
    }

    /**
     * @dev Calculate platform fee
     * 
     * @param amount Base amount
     * @param feePercentage Fee in basis points (500 = 5%)
     * 
     * @return fee Fee amount
     * @return remainder Amount after fee
     */
    function calculateFee(
        uint256 amount,
        uint256 feePercentage
    ) internal pure returns (uint256 fee, uint256 remainder) {
        unchecked {
            fee = amount * feePercentage / 10000;
            remainder = amount - fee;
        }
    }

    /**
     * @dev Check if bid is within valid range
     * 
     * @param bidAmount Amount to validate
     * @param minBid Minimum allowed bid
     * @param maxBid Maximum allowed bid
     * @param reservePrice Auction reserve price
     * 
     * @return isValid True if bid is valid
     */
    function isValidBid(
        uint256 bidAmount,
        uint256 minBid,
        uint256 maxBid,
        uint256 reservePrice
    ) internal pure returns (bool) {
        return bidAmount >= minBid &&
               bidAmount <= maxBid &&
               bidAmount >= reservePrice &&
               bidAmount > 0;
    }

    /**
     * @dev Check if crowd density is sufficient
     * 
     * @param density Current crowd density (0-100)
     * @param threshold Minimum required density
     * 
     * @return isSufficient True if density meets threshold
     */
    function isDensitySufficient(
        uint256 density,
        uint256 threshold
    ) internal pure returns (bool) {
        return density >= threshold && density <= 100;
    }

    /**
     * @dev Generate auction ID from parameters
     * 
     * @param billboard Billboard address
     * @param nonce Unique nonce (block number or counter)
     * @param timestamp Block timestamp
     * 
     * @return auctionId Unique auction identifier
     */
    function generateAuctionId(
        address billboard,
        uint256 nonce,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(billboard, nonce, timestamp));
    }

    /**
     * @dev Validate auction timing
     * 
     * @param startTime Auction start timestamp
     * @param durationMs Duration in milliseconds
     * @param currentTime Current block timestamp
     * 
     * @return isActive True if auction is still active
     * @return timeRemaining Seconds remaining (0 if expired)
     */
    function getAuctionTiming(
        uint256 startTime,
        uint256 durationMs,
        uint256 currentTime
    ) internal pure returns (bool isActive, uint256 timeRemaining) {
        // Convert ms to seconds
        uint256 durationSeconds = durationMs / 1000;
        uint256 elapsedSeconds = currentTime - startTime;
        
        if (elapsedSeconds >= durationSeconds) {
            return (false, 0);
        }
        
        timeRemaining = durationSeconds - elapsedSeconds;
        return (true, timeRemaining);
    }
}

/**
 * @title SettlementLibrary
 * @dev Payment and settlement calculation utilities
 */
library SettlementLibrary {
    
    /**
     * @dev Settlement details struct
     */
    struct SettlementDetails {
        uint256 paymentAmount;      // Amount winner pays
        uint256 platformFee;        // Platform revenue
        uint256 billboardPayment;   // Billboard owner earning
    }

    /**
     * @dev Calculate complete settlement
     * 
     * Vickrey: Winner pays 2nd highest price
     * Platform takes percentage cut
     * Billboard owner gets remainder
     * 
     * @param winningBid Winning bid amount
     * @param secondPrice Second highest price (Vickrey)
     * @param platformFeeBps Platform fee in basis points
     * 
     * @return details Complete settlement breakdown
     */
    function calculateSettlement(
        uint256 winningBid,
        uint256 secondPrice,
        uint256 platformFeeBps
    ) internal pure returns (SettlementDetails memory details) {
        // Payment amount (Vickrey)
        uint256 paymentAmount = secondPrice > 0 ? secondPrice : winningBid;
        
        // Platform fee
        uint256 platformFee = (paymentAmount * platformFeeBps) / 10000;
        
        // Billboard payment
        uint256 billboardPayment = paymentAmount - platformFee;
        
        details = SettlementDetails({
            paymentAmount: paymentAmount,
            platformFee: platformFee,
            billboardPayment: billboardPayment
        });
    }

    /**
     * @dev Validate settlement amounts
     * 
     * @param paymentAmount Amount to be paid
     * @param platformFee Platform fee
     * @param billboardPayment Billboard earning
     * 
     * @return isValid True if settlement is valid
     */
    function isValidSettlement(
        uint256 paymentAmount,
        uint256 platformFee,
        uint256 billboardPayment
    ) internal pure returns (bool) {
        return paymentAmount > 0 &&
               platformFee + billboardPayment == paymentAmount;
    }

    /**
     * @dev Calculate ROI for advertiser
     * 
     * @param spent Amount spent on advertising
     * @param impressions Number of ad impressions
     * @param engagements Number of engagements
     * 
     * @return cpc Cost per engagement
     */
    function calculateMetrics(
        uint256 spent,
        uint256 impressions,
        uint256 engagements
    ) internal pure returns (
        uint256 cpc,  // Cost per engagement
        uint256 cpi   // Cost per impression
    ) {
        if (engagements > 0) {
            cpc = spent / engagements;
        }
        if (impressions > 0) {
            cpi = spent / impressions;
        }
    }
}
