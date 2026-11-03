package com.demo.resortslite;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueResponse;

import javax.annotation.PostConstruct;
import java.util.logging.Logger;

/**
 * cr-java-0069 FIX: Centralised AWS Secrets Manager accessor.
 *
 * Retrieves the database secret (username + password) from AWS Secrets Manager
 * at application start-up, eliminating hard-coded credentials from source code.
 *
 * The secret is expected to be stored as a JSON string in the form:
 *   { "username": "...", "password": "..." }
 *
 * Required environment variables / application properties:
 *   AWS_REGION                  – AWS region where the secret lives (default: us-east-1)
 *   app.db.secret.name          – Name / ARN of the Secrets Manager secret
 */
@Component
public class AwsSecretsManagerConfig {

    private static final Logger logger = Logger.getLogger(AwsSecretsManagerConfig.class.getName());

    /** Name or ARN of the Secrets Manager secret that holds DB credentials. */
    @Value("${app.db.secret.name:resortslite/db/credentials}")
    private String dbSecretName;

    /** AWS region – defaults to us-east-1 but can be overridden via the property. */
    @Value("${cloud.aws.region.static:us-east-1}")
    private String awsRegion;

    private String dbUsername;
    private String dbPassword;

    /**
     * Fetches the secret from AWS Secrets Manager once the bean is initialised.
     * Falls back to empty strings if the secret cannot be retrieved, so the
     * application can still start in local / test environments where Secrets
     * Manager is not available (the datasource will simply fail to authenticate,
     * which is the expected behaviour without valid credentials).
     */
    @PostConstruct
    public void loadSecrets() {
        try {
            SecretsManagerClient client = SecretsManagerClient.builder()
                    .region(Region.of(awsRegion))
                    .build();

            GetSecretValueRequest request = GetSecretValueRequest.builder()
                    .secretId(dbSecretName)
                    .build();

            GetSecretValueResponse response = client.getSecretValue(request);
            String secretJson = response.secretString();

            ObjectMapper mapper = new ObjectMapper();
            JsonNode secretNode = mapper.readTree(secretJson);

            this.dbUsername = secretNode.path("username").asText("");
            this.dbPassword = secretNode.path("password").asText("");

            logger.info("Database credentials successfully loaded from AWS Secrets Manager secret: "
                    + dbSecretName);

        } catch (Exception e) {
            logger.warning("Could not load DB credentials from AWS Secrets Manager ("
                    + dbSecretName + "): " + e.getMessage()
                    + ". Falling back to empty credentials.");
            this.dbUsername = "";
            this.dbPassword = "";
        }
    }

    /** Returns the database username retrieved from AWS Secrets Manager. */
    public String getDbUsername() {
        return dbUsername;
    }

    /** Returns the database password retrieved from AWS Secrets Manager. */
    public String getDbPassword() {
        return dbPassword;
    }
}
