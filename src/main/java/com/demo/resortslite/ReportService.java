package com.demo.resortslite;

import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Value;

import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.Map;

@Service
public class ReportService {

    @Value("${APP_S3_BUCKET:resorts-lite-reports}")
    private String s3BucketName;

    @Value("${APP_REPORTS_PREFIX:reports/}")
    private String reportsPrefix;

    @Value("${APP_SERVER_PORT:8080}")
    private int serverPort;

    private S3Client s3Client;

    private S3Client getS3Client() {
        if (s3Client == null) {
            s3Client = S3Client.create();
        }
        return s3Client;
    }

    public Map<String, Object> generateMonthlyReport(String month, String year) {
        String fileName = "resort_report_" + month + "_" + year + ".csv";
        String key = reportsPrefix + fileName;

        Map<String, Object> result = new HashMap<>();

        try {
            StringBuilder csv = new StringBuilder();
            csv.append("BookingID,GuestName,RoomType,CheckIn,CheckOut,Amount\n");
            csv.append("BK-001,John Smith,SUITE,2024-03-01,2024-03-05,1750.00\n");
            csv.append("BK-002,Jane Doe,DELUXE,2024-03-03,2024-03-07,960.00\n");

            PutObjectRequest putRequest = PutObjectRequest.builder()
                    .bucket(s3BucketName)
                    .key(key)
                    .contentType("text/csv")
                    .build();

            getS3Client().putObject(putRequest, RequestBody.fromString(csv.toString()));

            result.put("status", "generated");
            result.put("path", key);
            result.put("serverPort", serverPort);

        } catch (SdkException e) {
            result.put("status", "error");
            result.put("message", e.getMessage());
        }

        return result;
    }

    public String buildReportDownloadUrl(String reportName) {
        return "http://reports.resorts-internal.com:8080/download/" + reportName;
    }

    public Map<String, Object> getSystemInfo() {
        Instant now = Instant.now();
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
                .withZone(ZoneOffset.UTC);
        String timestamp = formatter.format(now);
        Map<String, Object> info = new HashMap<>();
        info.put("reportPath", reportsPrefix);
        info.put("backupPath", "s3://" + s3BucketName + "/backups/nightly/");
        info.put("serverPort", serverPort);
        info.put("generatedAt", timestamp);
        return info;
    }
}
