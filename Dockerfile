# Build stage
FROM maven:3.8.6-openjdk-8-slim AS builder
WORKDIR /workspace

# Copy pom.xml and resolve dependencies first for better caching
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source and build
COPY src ./src
RUN mvn clean package -DskipTests -B

# Runtime stage
FROM eclipse-temurin:8-jdk
WORKDIR /app

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copy the built JAR
COPY --from=builder /workspace/target/*.jar app.jar

# Environment configuration
ENV TZ=UTC
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
ENV SPRING_PROFILES_ACTIVE=prod

# Expose the application port
EXPOSE 8080

# Run as non-root user
USER appuser

# Start the application with signal handling for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
