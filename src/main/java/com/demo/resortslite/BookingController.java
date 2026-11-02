package com.demo.resortslite;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.session.Session;
import org.springframework.session.SessionRepository;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;

// cr-java-0065 FIX: Replaced javax.servlet.http.HttpSession with Spring Session's
// SessionRepository backed by Amazon ElastiCache for Redis. Session state is now
// stored in a centralized Redis cluster, enabling stateless application instances
// that can be freely load-balanced, auto-scaled, and replaced without data loss.
// Spring Session transparently intercepts HttpSession calls and delegates to Redis,
// so all session reads/writes are distributed across the entire cluster.

// cr-java-0067 FIX: Replaced unbounded static in-memory HashMap cache with
// Amazon ElastiCache for Redis via Spring Data RedisTemplate. The cache now has
// a configurable TTL (default 30 minutes), preventing indefinite memory growth,
// stale data inconsistencies, and instance-local cache isolation. All application
// instances share the same centralized Redis cache, ensuring consistency across
// horizontally scaled deployments on AWS.

@RestController
@RequestMapping("/api/bookings")
public class BookingController {

    @Autowired
    private BookingService bookingService;

    // cr-java-0065 FIX: SessionRepository<S> is the Spring Session abstraction that
    // delegates to the configured Redis store (ElastiCache). Injected by Spring Boot
    // auto-configuration when spring-session-data-redis is on the classpath.
    @Autowired
    @SuppressWarnings("rawtypes")
    private SessionRepository sessionRepository;

    // cr-java-0067 FIX: RedisTemplate replaces the unbounded static HashMap.
    // Booking entries are stored in Amazon ElastiCache for Redis with a TTL,
    // ensuring controlled expiration and consistent data across all instances.
    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    // cr-java-0067 FIX: TTL for booking cache entries, externalised to an environment
    // variable / application property so it can be tuned per environment without
    // redeployment. Defaults to 30 minutes if not explicitly configured.
    @Value("${app.cache.booking.ttl-minutes:30}")
    private long bookingCacheTtlMinutes;

    private static final String BOOKING_CACHE_PREFIX = "bookingCache:";

    @PostMapping("/create")
    @SuppressWarnings("unchecked")
    public Map<String, Object> createBooking(
            @RequestParam String guestName,
            @RequestParam String roomType,
            @RequestParam String checkIn,
            @RequestParam String checkOut,
            HttpServletRequest request) {

        Map<String, Object> booking = bookingService.createBooking(guestName, roomType, checkIn, checkOut);

        // cr-java-0065 FIX: Session state is now stored in Amazon ElastiCache for Redis
        // via Spring Session's SessionRepository. The session is retrieved (or created)
        // using the session ID carried in the request cookie/header, then attributes are
        // written to Redis — visible to every application instance behind the AWS ALB.
        String sessionId = request.getRequestedSessionId();
        Session session = (sessionId != null) ? sessionRepository.findById(sessionId) : null;
        if (session == null) {
            session = sessionRepository.createSession();
        }
        session.setAttribute("lastBooking", booking);   // cr-java-0065 FIXED
        session.setAttribute("guestName", guestName);   // cr-java-0065 FIXED
        sessionRepository.save(session);

        // cr-java-0067 FIX: Store booking in Amazon ElastiCache for Redis with TTL.
        // The key is namespaced with BOOKING_CACHE_PREFIX to avoid collisions with
        // other Redis keys. The TTL ensures entries expire automatically, preventing
        // unbounded memory growth and stale data across distributed instances.
        String cacheKey = BOOKING_CACHE_PREFIX + booking.get("bookingId");
        redisTemplate.opsForValue().set(cacheKey, booking, bookingCacheTtlMinutes, TimeUnit.MINUTES);

        Map<String, Object> response = new HashMap<>();
        response.put("status", "confirmed");
        response.put("booking", booking);
        response.put("sessionId", session.getId());
        return response;
    }

    @GetMapping("/status/{bookingId}")
    @SuppressWarnings("unchecked")
    public Map<String, Object> getBookingStatus(
            @PathVariable String bookingId,
            HttpServletRequest request) {

        // cr-java-0065 FIX: Guest name is now read from the Redis-backed Spring Session
        // rather than from a local HttpSession. Any application instance in the cluster
        // can serve this request and retrieve the correct session data from ElastiCache.
        String sessionId = request.getRequestedSessionId();
        String lastGuest = null;
        if (sessionId != null) {
            Session session = sessionRepository.findById(sessionId);
            if (session != null) {
                lastGuest = session.getAttribute("guestName");  // cr-java-0065 FIXED
            }
        }

        // cr-java-0067 FIX: Booking lookup now reads from the Redis-backed cache.
        // If the entry has expired (TTL elapsed) or is absent, fall back to the
        // BookingService (database) to retrieve the booking details.
        String cacheKey = BOOKING_CACHE_PREFIX + bookingId;
        Map<String, Object> cachedBooking = (Map<String, Object>) redisTemplate.opsForValue().get(cacheKey);

        Map<String, Object> result = new HashMap<>();
        result.put("bookingId", bookingId);
        result.put("sessionGuest", lastGuest);
        result.put("details", cachedBooking != null ? cachedBooking : bookingService.getBookingById(bookingId));
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
