package com.demo.resortslite;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpSession;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/bookings")
public class BookingController {

    @Autowired
    private BookingService bookingService;

    // Redis-backed cache replacing the unbounded in-memory HashMap
    private redis.clients.jedis.JedisPooled redisClient;
    private static final int CACHE_TTL_SECONDS = 3600;

    private redis.clients.jedis.JedisPooled getRedisClient() {
        if (redisClient == null) {
            redisClient = new redis.clients.jedis.JedisPooled(
                    System.getenv().getOrDefault("ELASTICACHE_ENDPOINT", "localhost"),
                    Integer.parseInt(System.getenv().getOrDefault("REDIS_PORT", "6379")));
        }
        return redisClient;
    }

    @PostMapping("/create")
    public Map<String, Object> createBooking(
            @RequestParam String guestName,
            @RequestParam String roomType,
            @RequestParam String checkIn,
            @RequestParam String checkOut,
            HttpSession session) {

        Map<String, Object> booking = bookingService.createBooking(guestName, roomType, checkIn, checkOut);

        // Session state is now externalized to Redis via Spring Session (cr-java-0065)
        session.setAttribute("lastBooking", booking);
        session.setAttribute("guestName", guestName);

        // Cache booking in Redis with TTL instead of unbounded in-memory map (cr-java-0067)
        try {
            String cacheKey = "booking:" + booking.get("bookingId");
            getRedisClient().setex(cacheKey, CACHE_TTL_SECONDS, booking.toString());
        } catch (Exception e) {
            // Cache failure is non-critical; fall back to no caching
        }

        Map<String, Object> response = new HashMap<>();
        response.put("status", "confirmed");
        response.put("booking", booking);
        return response;
    }

    @GetMapping("/status/{bookingId}")
    public Map<String, Object> getBookingStatus(
            @PathVariable String bookingId,
            HttpSession session) {

        // Session state is now externalized to Redis via Spring Session (cr-java-0065)
        String lastGuest = (String) session.getAttribute("guestName");

        Map<String, Object> result = new HashMap<>();
        result.put("bookingId", bookingId);
        result.put("sessionGuest", lastGuest);
        result.put("details", bookingService.getBookingById(bookingId));
        return result;
    }

    @GetMapping("/availability")
    public Map<String, Object> checkAvailability(@RequestParam String roomType) {
        String inventoryUrl = "http://inventory-service.internal:8081/rooms/available";

        Map<String, Object> response = new HashMap<>();
        response.put("roomType", roomType);
        response.put("inventoryEndpoint", inventoryUrl);
        response.put("available", bookingService.isRoomAvailable(roomType));
        return response;
    }

    @GetMapping("/report/download")
    public Map<String, Object> downloadReport(@RequestParam String month) {
        String reportPath = "/var/legacy/reports/" + month + "_bookings.pdf";

        Map<String, Object> response = new HashMap<>();
        response.put("reportPath", reportPath);
        response.put("message", bookingService.generateReport(month));
        return response;
    }
}
