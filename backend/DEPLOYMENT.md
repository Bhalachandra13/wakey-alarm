# Wakey - Deployment Guide

## Production Deployment

### Prerequisites

- Docker & Docker Compose
- Kubernetes cluster (optional, for high availability)
- PostgreSQL 15+ instance or container
- Redis 7+ instance
- RabbitMQ 3.12+ instance
- Firebase project configured
- SSL certificate

### Environment Configuration

Create `.env.production`:

```bash
# Application
SPRING_PROFILES_ACTIVE=prod
SERVER_PORT=8080

# Database
POSTGRES_URL=jdbc:postgresql://postgres-prod.example.com:5432/wakey_prod
POSTGRES_USER=wakey_prod_user
POSTGRES_PASSWORD=<strong_random_password>

# Redis
REDIS_HOST=redis-prod.example.com
REDIS_PORT=6379
REDIS_PASSWORD=<strong_random_password>

# RabbitMQ
RABBITMQ_HOST=rabbitmq-prod.example.com
RABBITMQ_PORT=5672
RABBITMQ_USER=wakey_prod_user
RABBITMQ_PASSWORD=<strong_random_password>

# JWT
JWT_SECRET=<very_long_cryptographically_secure_key>

# Firebase
FIREBASE_CONFIG_JSON=<base64_encoded_service_account_key>

# Server
JAVA_OPTS=-Xmx2g -Xms1g
```

### Docker Deployment

#### Build Image

```bash
cd backend
docker build -t wakey-backend:prod .
docker tag wakey-backend:prod your-registry/wakey-backend:prod
docker push your-registry/wakey-backend:prod
```

#### Docker Compose (Single Node)

Create `docker-compose.prod.yml`:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: wakey_prod
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_prod_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: always

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_prod_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: always

  rabbitmq:
    image: rabbitmq:3.12-management-alpine
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASSWORD}
    volumes:
      - rabbitmq_prod_data:/var/lib/rabbitmq
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: always

  wakey-backend:
    image: your-registry/wakey-backend:prod
    environment:
      SPRING_PROFILES_ACTIVE: prod
      POSTGRES_URL: jdbc:postgresql://postgres:5432/wakey_prod
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      REDIS_HOST: redis
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      RABBITMQ_HOST: rabbitmq
      RABBITMQ_USER: ${RABBITMQ_USER}
      RABBITMQ_PASSWORD: ${RABBITMQ_PASSWORD}
      JWT_SECRET: ${JWT_SECRET}
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    restart: always
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  postgres_prod_data:
    driver: local
  redis_prod_data:
    driver: local
  rabbitmq_prod_data:
    driver: local
```

Deploy:
```bash
docker-compose -f docker-compose.prod.yml up -d
```

### Kubernetes Deployment

Create `kubernetes/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wakey-backend
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: wakey-backend
  template:
    metadata:
      labels:
        app: wakey-backend
    spec:
      containers:
      - name: wakey-backend
        image: your-registry/wakey-backend:prod
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "prod"
        - name: POSTGRES_URL
          valueFrom:
            secretKeyRef:
              name: wakey-secrets
              key: postgres-url
        - name: REDIS_HOST
          value: redis-service
        - name: RABBITMQ_HOST
          value: rabbitmq-service
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  name: wakey-backend-service
spec:
  selector:
    app: wakey-backend
  ports:
  - port: 80
    targetPort: 8080
  type: LoadBalancer
```

Deploy:
```bash
kubectl apply -f kubernetes/deployment.yaml
```

### Health Checks

```bash
# Check application health
curl http://localhost:8080/health

# Check metrics
curl http://localhost:8080/metrics
```

### Backup Strategy

#### PostgreSQL Backup

```bash
# Full backup
docker exec wakey_postgres pg_dump -U wakey_user wakey > wakey_backup.sql

# Restore
docker exec -i wakey_postgres psql -U wakey_user wakey < wakey_backup.sql

# Automated daily backup with cron
0 2 * * * docker exec wakey_postgres pg_dump -U wakey_user wakey > /backups/wakey_$(date +\%Y\%m\%d).sql
```

#### Redis Backup

```bash
# RDB snapshot
docker exec wakey_redis redis-cli BGSAVE

# Copy RDB file
docker cp wakey_redis:/data/dump.rdb ./redis_backup.rdb
```

### Monitoring

#### Prometheus Integration

Add to Spring Boot config:

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,metrics,prometheus
  metrics:
    export:
      prometheus:
        enabled: true
```

#### Log Aggregation (ELK Stack)

```yaml
# In docker-compose
filebeat:
  image: docker.elastic.co/beats/filebeat:8.0.0
  volumes:
    - /var/lib/docker/containers:/var/lib/docker/containers:ro
    - /var/run/docker.sock:/var/run/docker.sock:ro
  environment:
    - ELASTICSEARCH_HOSTS=elasticsearch:9200
  depends_on:
    - elasticsearch
```

### Database Migrations

Flyway runs automatically on startup:

```bash
# Check migration status
docker logs wakey-backend | grep -i flyway

# Manual migration if needed
./gradlew flywayMigrate
```

### Scaling

#### Horizontal Scaling

```bash
# Scale backend service
kubectl scale deployment wakey-backend --replicas=5

# Auto-scaling based on CPU
kubectl autoscale deployment wakey-backend --min=2 --max=10 --cpu-percent=70
```

#### Database Connection Pooling

Configure in `application-prod.yml`:

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 20
      minimum-idle: 5
      connection-timeout: 30000
      idle-timeout: 600000
      max-lifetime: 1800000
```

### Security Hardening

1. **Firewall Rules**
   - Only allow HTTPS (443)
   - Restrict database access to application servers

2. **SSL/TLS**
   ```bash
   # Generate self-signed certificate
   openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365
   ```

3. **API Rate Limiting**
   ```kotlin
   @Configuration
   class RateLimitConfig {
       // Implement rate limiting middleware
   }
   ```

4. **CORS Configuration**
   ```yaml
   cors:
     allowed-origins: https://app.wakey.com
     allowed-methods: GET,POST,PUT,DELETE,PATCH
     allowed-headers: "*"
     max-age: 3600
   ```

### Performance Tuning

1. **Database Indexing**
   - Indices created in Flyway migrations
   - Monitor slow queries

2. **Redis Caching**
   - TTL configured for geofence states
   - Monitor cache hit rates

3. **Connection Pooling**
   - HikariCP configured with optimal settings
   - Monitor active connections

4. **JVM Tuning**
   ```bash
   JAVA_OPTS="-Xmx2g -Xms1g -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
   ```

### Disaster Recovery

1. **Database Replication**
   ```sql
   -- Setup streaming replication in PostgreSQL
   pg_basebackup -h primary -D replica_data -U replication_user -v -P
   ```

2. **RabbitMQ Clustering**
   ```bash
   # Enable cluster mode
   docker exec wakey_rabbitmq rabbitmqctl join_cluster rabbit@rabbitmq1
   ```

3. **Automated Failover**
   - Use Keepalived for virtual IP
   - Health checks trigger automatic failover

### Maintenance Windows

```bash
# Graceful shutdown
curl -X POST http://localhost:8080/actuator/shutdown

# Database maintenance
docker exec wakey_postgres vacuumdb -U wakey_user wakey

# Cache cleanup
docker exec wakey_redis redis-cli FLUSHDB
```

### Monitoring Checklist

- [ ] Application health endpoint responding
- [ ] Database connectivity verified
- [ ] Redis connectivity verified
- [ ] RabbitMQ connectivity verified
- [ ] Logs being collected
- [ ] Metrics being exported
- [ ] Backups running successfully
- [ ] SSL certificate valid
- [ ] Firewall rules in place
- [ ] Database replication working
- [ ] API responding to requests
- [ ] WebSocket connections stable

---

**Last Updated**: January 2024
