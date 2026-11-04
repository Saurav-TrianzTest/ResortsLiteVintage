package com.demo.resortslite;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import io.lettuce.core.RedisClient;
import io.lettuce.core.RedisURI;
import io.lettuce.core.api.sync.RedisCommands;

import javax.servlet.http.HttpSession;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/bookings")
public class BookingController {

    @Autowired
    private BookingService bookingService;

    private RedisClient redisClient;
    private static final String CACHE_PREFIX = "booking:cache:";
    private static final int CACHE_TTL_SECONDS = 3600;

    private RedisCommands<String, String> getRedisCommands() {
        if (redisClient == null) {
            String redisHost = System.getenv().getOrDefault("REDIS_HOST", "localhost");
            int redisPort = Integer.parseInt(System.getenv().getOrDefault("REDIS_PORT", "6379"));
            RedisURI redisUri = RedisURI.create(redisHost, redisPort);
            redisClient = RedisClient.create(redisUri);
        }
        return redisClient.connect().sync();
    }

    @PostMapping("/create")
    public Map<String, Object> createBooking(
            @RequestParam String guestName,
            @RequestParam String roomType,
            @RequestParam String checkIn,
            @RequestParam String checkOut,
            HttpSession session) {

        Map<String, Object> booking = bookingService.createBooking(guestName, roomType, checkIn, checkOut);

        session.setAttribute("lastBooking", booking);
        session.setAttribute("guestName", guestName);

        try {
            String cacheKey = CACHE_PREFIX + booking.get("bookingId");
            String json = "{\"bookingId\":\"" + booking.get("bookingId") + "\"}";
            RedisCommands<String, String> sync = getRedisCommands();
            sync.set(cacheKey, json);
            sync.expire(cacheKey, CACHE_TTL_SECONDS);
        } catch (Exception e) {
            // Cache failure is non-critical; keep old behavior
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
