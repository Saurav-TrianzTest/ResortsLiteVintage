package com.demo.resortslite;

import org.springframework.stereotype.Service;

import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import javax.annotation.PreDestroy;
import java.io.IOException;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.Map;

@Service
public class ReportService {

    // VIOLATION czr-java-001 [Software Portability / Mandatory]: Hardcoded absolute path.
    // /var/legacy/reports does not exist in a Docker container image. Breaks containerisation.
    // Must use volume mounts, cloud object storage (S3 / Azure Blob), or environment variable.
    private static final String REPORT_BASE_PATH = "/var/legacy/reports/"; // czr-java-001

    // VIOLATION czr-java-001 [Software Portability / Mandatory]: Windows-style absolute path
    // will fail on any Linux-based container or cloud host. Hard dependency on OS path structure.
    // Now an S3 key prefix (bucket from APP_S3_BUCKET), not a host path.
    private static final String BACKUP_PATH = "backups/nightly/"; // czr-java-001

    // VIOLATION [Software Portability / High]: Fixed server port hardcoded in application logic.
    // Container orchestration (ECS / EKS) dynamically assigns ports. Hardcoded ports prevent
    // dynamic port binding required for modern container deployment and service discovery.
    private static final int SERVER_PORT = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080")); // czr-port-001

    private static final String S3_BUCKET_ENV = "APP_S3_BUCKET";
    private static final String REPORT_KEY_PREFIX = "reports/";

    private S3Client s3Client;

    private synchronized S3Client s3() {
        if (s3Client == null) {
            s3Client = S3Client.create();
        }
        return s3Client;
    }

    @PreDestroy
    public synchronized void closeS3() {
        if (s3Client != null) {
            s3Client.close();
            s3Client = null;
        }
    }

    public Map<String, Object> generateMonthlyReport(String month, String year) {
        String fileName = "resort_report_" + month + "_" + year + ".csv";
        String fullPath = REPORT_BASE_PATH + fileName; // czr-java-001

        Map<String, Object> result = new HashMap<>();

        try {
            String bucket = System.getenv(S3_BUCKET_ENV);
            if (bucket == null || bucket.isEmpty()) {
                throw new IOException(S3_BUCKET_ENV + " is not set");
            }

            StringBuilder csv = new StringBuilder();
            csv.append("BookingID,GuestName,RoomType,CheckIn,CheckOut,Amount\n");
            csv.append("BK-001,John Smith,SUITE,2024-03-01,2024-03-05,1750.00\n");
            csv.append("BK-002,Jane Doe,DELUXE,2024-03-03,2024-03-07,960.00\n");

            PutObjectRequest putRequest = PutObjectRequest.builder()
                    .bucket(bucket)
                    .key(REPORT_KEY_PREFIX + fileName)
                    .contentType("text/csv")
                    .build();
            s3().putObject(putRequest, RequestBody.fromString(csv.toString()));

            result.put("status", "generated");
            result.put("path", fullPath);
            result.put("serverPort", SERVER_PORT); // czr-port-001

        } catch (IOException | SdkException e) {
            result.put("status", "error");
            result.put("message", e.getMessage());
        }

        return result;
    }

    // VIOLATION [Code Sustainability / Medium]: No JavaDoc or method documentation.
    // Missing documentation is flagged across all public methods in the codebase.
    // This increases onboarding time and transformation risk for automated tools.
    public String buildReportDownloadUrl(String reportName) { // doc-missing-001
        // VIOLATION cr-java-0088 [Cloud Compatibility / Mandatory]: Plain HTTP URL
        // hardcoded for report download. Cloud security standards enforce HTTPS.
        return "http://reports.resorts-internal.com:8080/download/" + reportName; // cr-java-0088
    }

    public Map<String, Object> getSystemInfo() { // doc-missing-001
        String timestamp = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneOffset.UTC).format(Instant.now());
        Map<String, Object> info = new HashMap<>();
        info.put("reportPath", REPORT_BASE_PATH);  // czr-java-001
        info.put("backupPath", BACKUP_PATH);        // czr-java-001
        info.put("serverPort", SERVER_PORT);        // czr-port-001
        info.put("generatedAt", timestamp);
        return info;
    }
}
