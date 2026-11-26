package com.demo.resortslite;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;

/**
 * Amazon S3 client configuration. Credentials are resolved through the AWS default
 * credentials provider chain (IAM role / environment / profile) - nothing is hardcoded.
 */
@Configuration
public class S3Config {

    @Bean(destroyMethod = "close")
    public S3Client s3Client(@Value("${app.reports.s3.region:${AWS_REGION:us-east-1}}") String region) {
        return S3Client.builder()
                .region(Region.of(region))
                .build();
    }
}
