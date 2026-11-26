package com.demo.resortslite;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.core.exception.SdkClientException;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.Map;

@Service
public class ReportService {

    // VIOLATION czr-java-001 [Software Portability / Mandatory]: Hardcoded absolute path.
    // /var/legacy/reports does not exist in a Docker container image. Breaks containerisation.
    // Must use volume mounts, cloud object storage (S3 / Azure Blob), or environment variable.
    // Now an S3 key prefix (not a filesystem path); configurable via environment.
    private final String reportBasePath;

    // VIOLATION czr-java-001 [Software Portability / Mandatory]: Windows-style absolute path
    // will fail on any Linux-based container or cloud host. Hard dependency on OS path structure.
    // Now an S3 key prefix (not a filesystem path); configurable via environment.
    private final String backupPath;

    // Target S3 bucket, supplied via environment variable REPORTS_S3_BUCKET.
    private final String bucketName;

    private final S3Client s3Client;

    // Server port is externalized: injected from the SERVER_PORT environment variable
    // (sourced from AWS Systems Manager Parameter Store by ECS/EKS/Elastic Beanstalk).
    private final int serverPort;

    @Autowired
    public ReportService(S3Client s3Client,
                         @Value("${app.reports.s3.bucket:${REPORTS_S3_BUCKET:resorts-reports}}") String bucketName,
                         @Value("${app.reports.s3.prefix:${REPORTS_S3_PREFIX:reports/}}") String reportBasePath,
                         @Value("${app.reports.s3.backup-prefix:${REPORTS_S3_BACKUP_PREFIX:backups/nightly/}}") String backupPath,
                         @Value("${server.port:${SERVER_PORT:8080}}") int serverPort) {
        this.serverPort = serverPort;
        this.s3Client = s3Client;
        this.bucketName = bucketName;
        this.reportBasePath = reportBasePath;
        this.backupPath = backupPath;
    }

    public Map<String, Object> generateMonthlyReport(String month, String year) {
        String fileName = "resort_report_" + month + "_" + year + ".csv";
        String fullPath = reportBasePath + fileName; // S3 object key

        Map<String, Object> result = new HashMap<>();

        try {
            StringBuilder csv = new StringBuilder();
            csv.append("BookingID,GuestName,RoomType,CheckIn,CheckOut,Amount\n");
            csv.append("BK-001,John Smith,SUITE,2024-03-01,2024-03-05,1750.00\n");
            csv.append("BK-002,Jane Doe,DELUXE,2024-03-03,2024-03-07,960.00\n");

            s3Client.putObject(PutObjectRequest.builder()
                            .bucket(bucketName)
                            .key(fullPath)
                            .contentType("text/csv")
                            .build(),
                    RequestBody.fromString(csv.toString(), StandardCharsets.UTF_8));

            result.put("status", "generated");
            result.put("path", "s3://" + bucketName + "/" + fullPath);
            result.put("serverPort", serverPort);

        } catch (S3Exception | SdkClientException e) {
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
        String timestamp = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
                .format(ZonedDateTime.now(Clock.systemUTC()).withZoneSameInstant(ZoneOffset.UTC));
        Map<String, Object> info = new HashMap<>();
        info.put("reportPath", "s3://" + bucketName + "/" + reportBasePath);
        info.put("backupPath", "s3://" + bucketName + "/" + backupPath);
        info.put("serverPort", serverPort);
        info.put("generatedAt", timestamp);
        return info;
    }
}
