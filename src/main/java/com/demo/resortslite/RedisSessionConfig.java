package com.demo.resortslite;

import org.springframework.context.annotation.Configuration;
import org.springframework.session.data.redis.config.annotation.web.http.EnableRedisHttpSession;

/**
 * RedisSessionConfig — cr-java-0065 FIX
 *
 * Enables Spring Session backed by Amazon ElastiCache for Redis.
 *
 * @EnableRedisHttpSession replaces the default in-process HttpSession
 * implementation with a Redis-backed one.  Every call to
 * HttpSession.setAttribute / getAttribute transparently reads from and
 * writes to the configured Redis (ElastiCache) cluster, making all
 * application instances fully stateless.
 *
 * Configuration properties (application.properties / environment variables):
 *   spring.redis.host  — ElastiCache primary endpoint  (default: localhost)
 *   spring.redis.port  — ElastiCache port               (default: 6379)
 *   spring.session.timeout — session TTL                (default: 30m)
 *
 * maxInactiveIntervalInSeconds = 1800 (30 minutes) matches the default
 * Spring Session timeout; override via spring.session.timeout property.
 */
@Configuration
@EnableRedisHttpSession(maxInactiveIntervalInSeconds = 1800)
public class RedisSessionConfig {
    // Spring Boot auto-configuration wires the LettuceConnectionFactory
    // (or JedisConnectionFactory) from spring.redis.* properties.
    // No additional beans are required here.
}
