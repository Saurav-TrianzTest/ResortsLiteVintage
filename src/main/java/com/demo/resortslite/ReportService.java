package com.demo.resortslite;

import org.springframework.stereotype.Service;

import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.Map;

@Service
public class ReportService {

    // cr-java-0061 FIX: Replaced hardcoded absolute file path "/var/legacy/reports/" with
    // an environment variable backed S3 bucket name. The S3 bucket is read from the
    // environment variable REPORT_S3_BUCKET, defaulting to "resort-reports-bucket" if not set.
    private static final String REPORT_S3_BUCKET = System.getenv("REPORT_S3_BUCKET") != null
            ? System.getenv("REPORT_S3_BUCKET")
            : "resort-reports-bucket";

    // cr-java-0061 FIX: Replaced hardcoded Windows-style backup path "C:\\ResortBackups\\nightly\\"
    // with an environment variable backed S3 bucket name for backups.
    private static final String BACKUP_S3_BUCKET = System.getenv("BACKUP_S3_BUCKET") != null
            ? System.getenv("BACKUP_S3_BUCKET")
            : "resort-backups-bucket";

    // cr-java-0077 FIX: Replaced hard-coded port 8080 with a value read from the SERVER_PORT
    // environment variable (injected by ECS task definition, EKS pod spec, or Elastic Beanstalk
    // environment configuration). Falls back to 8080 only for local development.
    // In production the value should be supplied via AWS Systems Manager Parameter Store and
    // injected as an environment variable at container/instance startup.
    private static final int SERVER_PORT = System.getenv("SERVER_PORT") != null
            ? Integer.parseInt(System.getenv("SERVER_PORT"))
            : 8080;

    // cr-java-0111 FIX: Standardized timestamp formatter using java.time API with explicit
    // UTC zone offset. Used in place of SimpleDateFormat to ensure consistent, thread-safe
    // timestamp generation across all cloud regions and container instances.
    private static final DateTimeFormatter UTC_FORMATTER =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneOffset.UTC);

    public Map<String, Object> generateMonthlyReport(String month, String year) {
        // cr-java-0063 FIX (Lines 37-42): Replaced all java.io.File-based persistent storage
        // operations with Amazon S3 client calls using AWS SDK for Java v2.
        //
        // ORIGINAL CODE (lines 37-46 in source):
        //   File reportDir = new File(REPORT_BASE_PATH);   // line 37 - java.io.File usage
        //   if (!reportDir.exists()) {                      // line 38
        //       reportDir.mkdirs();                         // line 39 - java.io.File method
        //   }
        //   FileWriter writer = new FileWriter(fullPath);   // line 42 - local FS write
        //   writer.write("BookingID,...\n");
        //   writer.close();
        //
        // REASON: java.io.File assumes local file system availability and persistence.
        // In cloud/containerized environments the local file system is ephemeral; data
        // written locally is lost on container restart or scale-out. The fix streams the
        // CSV content directly to Amazon S3 via S3Client.putObject(), ensuring durable,
        // highly available storage that survives container lifecycle events.
        String s3Key = "reports/resort_report_" + month + "_" + year + ".csv";

        Map<String, Object> result = new HashMap<>();

        try {
            S3Client s3Client = S3Client.create();

            String csvContent = "BookingID,GuestName,RoomType,CheckIn,CheckOut,Amount\n"
                    + "BK-001,John Smith,SUITE,2024-03-01,2024-03-05,1750.00\n"
                    + "BK-002,Jane Doe,DELUXE,2024-03-03,2024-03-07,960.00\n";

            PutObjectRequest putRequest = PutObjectRequest.builder()
                    .bucket(REPORT_S3_BUCKET)
                    .key(s3Key)
                    .contentType("text/csv")
                    .build();

            s3Client.putObject(putRequest, RequestBody.fromString(csvContent));

            result.put("status", "generated");
            result.put("s3Bucket", REPORT_S3_BUCKET);
            result.put("s3Key", s3Key);
            result.put("serverPort", SERVER_PORT); // czr-port-001

        } catch (S3Exception e) {
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
        // cr-java-0111 FIX: Replaced java.util.Date + SimpleDateFormat (line 70 in source)
        // with java.time.Instant captured at UTC via ZonedDateTime and formatted using a
        // thread-safe DateTimeFormatter. This eliminates server-local timezone dependency
        // and ensures consistent timestamps across all cloud regions and container replicas.
        //
        // ORIGINAL CODE (line 70 in source):
        //   String timestamp = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date());
        //
        // REASON: java.util.Date captures the JVM's default timezone which varies between
        // cloud regions and container images. SimpleDateFormat is also not thread-safe.
        // Replacing with Instant.now() pinned to UTC guarantees identical timestamps
        // regardless of where the container is scheduled in a multi-region AWS deployment.
        String timestamp = UTC_FORMATTER.format(ZonedDateTime.now(ZoneOffset.UTC));

        Map<String, Object> info = new HashMap<>();
        // cr-java-0061 FIX: Replaced hardcoded REPORT_BASE_PATH and BACKUP_PATH references
        // with S3 bucket names sourced from environment variables.
        info.put("reportS3Bucket", REPORT_S3_BUCKET);
        info.put("backupS3Bucket", BACKUP_S3_BUCKET);
        info.put("serverPort", SERVER_PORT);        // czr-port-001
        info.put("generatedAt", timestamp);
        return info;
    }
}
