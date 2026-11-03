package com.demo.resortslite;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.session.data.redis.RedisIndexedSessionRepository;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpSession;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/**
 * BookingController — cr-java-0065 + cr-java-0067 FIX:
 *
 * cr-java-0065 FIX:
 *   All HTTP session state (lastBooking, guestName) has been migrated to
 *   Amazon ElastiCache for Redis via Spring Session.  Spring Session
 *   transparently replaces the standard javax.servlet.http.HttpSession
 *   implementation with a Redis-backed one, so the existing
 *   session.setAttribute / session.getAttribute call-sites are preserved
 *   but now write to / read from a centralised Redis store rather than
 *   in-process JVM memory.
 *
 *   This makes every application instance stateless: AWS ALB can route
 *   any request to any instance, auto-scaling and failover work correctly,
 *   and session data survives instance termination.
 *
 * cr-java-0067 FIX:
 *   The unbounded static in-memory HashMap (bookingCache) has been replaced
 *   with Amazon ElastiCache for Redis via Spring Data Redis (RedisTemplate).
 *   Each cache entry is stored with a 30-minute TTL so that:
 *     - Memory growth is bounded and controlled.
 *     - Stale data is automatically evicted after the TTL expires.
 *     - All application instances share a single, consistent cache view.
 *     - Cache entries survive individual instance restarts/replacements.
 *
 * Required additions (see pom.xml and application.properties):
 *   - spring-session-data-redis dependency
 *   - spring-boot-starter-data-redis dependency
 *   - @EnableRedisHttpSession on a @Configuration class (see RedisSessionConfig)
 *   - spring.redis.host / spring.redis.port pointing at the ElastiCache endpoint
 */
@RestController
@RequestMapping("/api/bookings")
public class BookingController {

    @Autowired
    private BookingService bookingService;

    /**
     * cr-java-0067 FIX: Replaced unbounded static in-memory HashMap with
     * Amazon ElastiCache for Redis via Spring Data RedisTemplate.
     *
     * The old pattern:
     *   private static final Map<String, Object> bookingCache = new HashMap<>();
     *
     * caused:
     *   - Unbounded memory growth (no TTL / eviction policy).
     *   - Instance-local cache — invisible to other EC2/ECS instances.
     *   - Stale data inconsistencies across a horizontally-scaled cluster.
     *
     * The new pattern writes each booking to Redis with a 30-minute TTL
     * (BOOKING_CACHE_TTL_MINUTES) under the key prefix "booking:cache:<bookingId>".
     * Redis handles expiration automatically, and all instances share the same
     * ElastiCache cluster, ensuring consistent cache state.
     */
    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    /** TTL for booking cache entries in Amazon ElastiCache for Redis (30 minutes). */
    private static final long BOOKING_CACHE_TTL_MINUTES = 30L;

    /** Key prefix for booking cache entries stored in ElastiCache for Redis. */
    private static final String BOOKING_CACHE_KEY_PREFIX = "booking:cache:";

    /**
     * cr-java-0065 FIX: HttpSession is now backed by Amazon ElastiCache for Redis
     * via Spring Session (spring-session-data-redis).  The session.setAttribute calls
     * below write to Redis instead of in-process JVM memory, enabling stateless
     * horizontal scaling across multiple EC2 / ECS instances behind an AWS ALB.
     *
     * cr-java-0067 FIX: bookingCache.put() replaced with redisTemplate.opsForValue().set()
     * with a 30-minute TTL, storing the booking in Amazon ElastiCache for Redis.
     */
    @PostMapping("/create")
    public Map<String, Object> createBooking(
            @RequestParam String guestName,
            @RequestParam String roomType,
            @RequestParam String checkIn,
            @RequestParam String checkOut,
            HttpServletRequest request) {

        Map<String, Object> booking = bookingService.createBooking(guestName, roomType, checkIn, checkOut);

        // cr-java-0065 FIX: Session is now Redis-backed via Spring Session.
        // session.setAttribute writes to Amazon ElastiCache for Redis — data is
        // shared across all application instances, eliminating server affinity.
        HttpSession session = request.getSession(true);
        session.setAttribute("lastBooking", booking);
        session.setAttribute("guestName", guestName);

        // cr-java-0067 FIX: Store booking in Amazon ElastiCache for Redis with a
        // 30-minute TTL.  This replaces the unbounded static in-memory HashMap that
        // caused memory growth and cache inconsistency across instances.
        String cacheKey = BOOKING_CACHE_KEY_PREFIX + booking.get("bookingId");
        redisTemplate.opsForValue().set(cacheKey, booking, BOOKING_CACHE_TTL_MINUTES, TimeUnit.MINUTES);

        Map<String, Object> response = new HashMap<>();
        response.put("status", "confirmed");
        response.put("booking", booking);
        return response;
    }

    /**
     * cr-java-0065 FIX: session.getAttribute now reads from Amazon ElastiCache for
     * Redis via Spring Session, so the correct guestName is returned regardless of
     * which application instance handles this request.
     *
     * cr-java-0067 FIX: Booking lookup now reads from Amazon ElastiCache for Redis
     * via redisTemplate.opsForValue().get(), providing a consistent cache view
     * across all application instances.
     */
    @GetMapping("/status/{bookingId}")
    public Map<String, Object> getBookingStatus(
            @PathVariable String bookingId,
            HttpServletRequest request) {

        // cr-java-0065 FIX: Reading from Redis-backed Spring Session — returns the
        // correct value on any instance in the cluster, not just the originating one.
        HttpSession session = request.getSession(false);
        String lastGuest = (session != null) ? (String) session.getAttribute("guestName") : null;

        // cr-java-0067 FIX: Read booking from Amazon ElastiCache for Redis cache.
        // Returns null (cache miss) if the TTL has expired or the entry was never cached.
        String cacheKey = BOOKING_CACHE_KEY_PREFIX + bookingId;
        Object cachedBooking = redisTemplate.opsForValue().get(cacheKey);

        Map<String, Object> result = new HashMap<>();
        result.put("bookingId", bookingId);
        result.put("sessionGuest", lastGuest);
        result.put("cachedBooking", cachedBooking);
        result.put("details", bookingService.getBookingById(bookingId));
        return result;
    }

    @GetMapping("/availability")
    public Map<String, Object> checkAvailability(@RequestParam String roomType) {
        // VIOLATION cr-java-0088 [Cloud Compatibility / Mandatory]: Plain HTTP call to
        // internal inventory service. AWS ALB, WAF, and Well-Architected security review
        // enforce HTTPS. This call will be blocked or flagged in a cloud-native setup.
        String inventoryUrl = "http://inventory-service.internal:8081/rooms/available"; // cr-java-0088

        Map<String, Object> response = new HashMap<>();
        response.put("roomType", roomType);
        response.put("inventoryEndpoint", inventoryUrl);
        response.put("available", bookingService.isRoomAvailable(roomType));
        return response;
    }

    @GetMapping("/report/download")
    public Map<String, Object> downloadReport(@RequestParam String month) {
        // VIOLATION czr-java-001 [Software Portability / Mandatory]: Hardcoded absolute
        // file path. This path does not exist inside a container image. Container images
        // have their own isolated file systems — /var/legacy/reports won't be present.
        String reportPath = "/var/legacy/reports/" + month + "_bookings.pdf"; // czr-java-001

        Map<String, Object> response = new HashMap<>();
        response.put("reportPath", reportPath);
        response.put("message", bookingService.generateReport(month));
        return response;
    }
}
