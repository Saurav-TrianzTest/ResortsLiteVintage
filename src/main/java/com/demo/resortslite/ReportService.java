package com.demo.resortslite;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetUrlRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;

import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HashMap;
import java.util.Map;

/**
 * Service responsible for generating and storing resort reports.
 *
 * <p>cr-java-0061 FIX: All hard-coded absolute file-system paths ("/var/legacy/reports/"
 * and "C:\\ResortBackups\\nightly\\") have been removed. Storage configuration is now
 * sourced from environment variables / application properties via @Value injection.</p>
 *
 * <p>cr-java-0062 FIX: All local file write operations (File, FileWriter) have been
 * replaced with Amazon S3 PutObject calls, ensuring data durability and availability
 * in containerised and serverless environments where the local file system is ephemeral.</p>
 *
 * <p>cr-java-0077 FIX: Hard-coded port constant {@code SERVER_PORT = 8080} has been removed.
 * The server port is now injected via the {@code SERVER_PORT} environment variable (with a
 * safe default of 8080), enabling dynamic port assignment by ECS, EKS, or Elastic Beanstalk.
 * The {@code server.port} property in application.properties is also bound to
 * {@code ${SERVER_PORT:8080}} so the container orchestration platform can override it at
 * runtime without any code changes.</p>
 */
@Service
public class ReportService {

    // cr-java-0061 FIX: Replaced hard-coded absolute path "/var/legacy/reports/" with
    // an S3 bucket name sourced from environment variable AWS_S3_BUCKET_NAME.
    @Value("${aws.s3.bucket-name}")
    private String s3BucketName;

    @Value("${aws.s3.region}")
    private String s3Region;

    // cr-java-0061 FIX: Replaced hard-coded Windows backup path "C:\\ResortBackups\\nightly\\"
    // with an S3 key prefix sourced from environment variable AWS_S3_REPORTS_PREFIX.
    @Value("${aws.s3.reports-prefix}")
    private String reportsPrefix;

    // cr-java-0077 FIX: Replaced hard-coded constant SERVER_PORT = 8080 with an
    // @Value-injected field sourced from the server.port property, which is itself
    // bound to the SERVER_PORT environment variable in application.properties.
    // ECS task definitions, EKS pod specs, and Elastic Beanstalk environment
    // configuration can override SERVER_PORT at runtime without code changes,
    // enabling dynamic port assignment required by container orchestration platforms
    // and AWS service discovery mechanisms.
    @Value("${server.port:8080}")
    private int serverPort;

    /**
     * Builds a lazily-initialised S3Client using the default AWS credentials chain
     * (environment variables → ~/.aws/credentials → IAM instance role).
     *
     * @return a configured {@link S3Client} instance
     */
    private S3Client buildS3Client() {
        return S3Client.builder()
                .region(Region.of(s3Region))
                .credentialsProvider(DefaultCredentialsProvider.create())
                .build();
    }

    /**
     * Generates a monthly booking report and uploads it to Amazon S3.
     *
     * <p>cr-java-0062 FIX (lines 37-50 original): The original code used
     * {@code new File(REPORT_BASE_PATH)}, {@code reportDir.mkdirs()}, and
     * {@code new FileWriter(fullPath)} to persist data on the local file system.
     * In cloud/container environments the local file system is ephemeral; data
     * written there is lost on container restart or scale-out events.
     * All local file write operations have been replaced with a single
     * {@link S3Client#putObject} call so that report data is stored durably in
     * Amazon S3 and is accessible regardless of which container instance handles
     * subsequent requests.</p>
     *
     * @param month two-digit month string (e.g. "03")
     * @param year  four-digit year string  (e.g. "2024")
     * @return result map containing status and the S3 object key (or error message)
     */
    public Map<String, Object> generateMonthlyReport(String month, String year) {
        String fileName = "resort_report_" + month + "_" + year + ".csv";
        // cr-java-0061 FIX: S3 key replaces the local fullPath built from REPORT_BASE_PATH.
        String s3Key    = reportsPrefix + fileName; // e.g. "reports/resort_report_03_2024.csv"

        Map<String, Object> result = new HashMap<>();

        // cr-java-0062 FIX (line 42 original): Replaced local FileWriter.write() calls
        // with an in-memory CSV string uploaded via S3Client.putObject().
        // Original violations removed:
        //   - new File(REPORT_BASE_PATH)          → ephemeral local directory creation
        //   - reportDir.mkdirs()                  → ephemeral local directory creation
        //   - new FileWriter(fullPath)             → local file write (cr-java-0062)
        //   - writer.write("BookingID,...")        → local file write (cr-java-0062) [line 42]
        //   - writer.write("BK-001,...")           → local file write (cr-java-0062)
        //   - writer.write("BK-002,...")           → local file write (cr-java-0062)
        //   - writer.close()                       → local file write (cr-java-0062)
        String csvContent = "BookingID,GuestName,RoomType,CheckIn,CheckOut,Amount\n"
                + "BK-001,John Smith,SUITE,2024-03-01,2024-03-05,1750.00\n"
                + "BK-002,Jane Doe,DELUXE,2024-03-03,2024-03-07,960.00\n";

        try (S3Client s3 = buildS3Client()) {
            // cr-java-0062 FIX: PutObjectRequest replaces all FileWriter write operations.
            // Data is stored durably in S3; no local file system dependency remains.
            PutObjectRequest putRequest = PutObjectRequest.builder()
                    .bucket(s3BucketName)
                    .key(s3Key)
                    .contentType("text/csv")
                    .build();

            s3.putObject(putRequest, RequestBody.fromString(csvContent));

            result.put("status", "generated");
            result.put("s3Bucket", s3BucketName);
            result.put("s3Key", s3Key);
            // cr-java-0077 FIX: serverPort is now injected from SERVER_PORT env var
            result.put("serverPort", serverPort);

        } catch (S3Exception e) {
            result.put("status", "error");
            result.put("message", e.awsErrorDetails().errorMessage());
        }

        return result;
    }

    /**
     * Builds a pre-signed or public HTTPS download URL for a report stored in S3.
     *
     * <p>cr-java-0088 FIX: Replaced plain HTTP hardcoded URL with an HTTPS S3 URL
     * derived from the configured bucket and region.</p>
     *
     * @param reportName the S3 object key (or report file name) to build the URL for
     * @return HTTPS URL pointing to the report object in S3
     */
    public String buildReportDownloadUrl(String reportName) { // doc-missing-001
        try (S3Client s3 = buildS3Client()) {
            String s3Key = reportsPrefix + reportName;
            return s3.utilities()
                    .getUrl(GetUrlRequest.builder()
                            .bucket(s3BucketName)
                            .key(s3Key)
                            .build())
                    .toExternalForm();
        }
    }

    /**
     * Returns system information including S3 storage configuration.
     *
     * <p>cr-java-0061 FIX: Replaced REPORT_BASE_PATH and BACKUP_PATH (hard-coded
     * local file-system paths) with S3 bucket/prefix values from configuration.</p>
     *
     * @return map of system metadata
     */
    public Map<String, Object> getSystemInfo() { // doc-missing-001
        // cr-java-0111 FIX: Replaced java.util.Date + SimpleDateFormat (server-local timezone)
        // with java.time.ZonedDateTime pinned to UTC via ZoneOffset.UTC.
        // Using UTC ensures consistent timestamps across all AWS regions, container instances,
        // and distributed services regardless of the host's local timezone setting.
        String timestamp = ZonedDateTime.now(ZoneOffset.UTC)
                .format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        Map<String, Object> info = new HashMap<>();
        info.put("s3BucketName",  s3BucketName);
        info.put("reportsPrefix", reportsPrefix);
        info.put("s3Region",      s3Region);
        // cr-java-0077 FIX: serverPort is now injected from SERVER_PORT env var
        info.put("serverPort",    serverPort);
        info.put("generatedAt",   timestamp);
        return info;
    }
}
