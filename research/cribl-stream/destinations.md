# Cribl Stream Destinations -- Requirements Specification

## Destinations Overview

### General Architecture Requirements

- The system SHALL categorize destinations into three types: **Streaming** (real-time event delivery), **Non-Streaming/Batch** (local staging followed by upload), and **Internal** (intra-cluster routing).
- The system SHALL provide health status indicators for each destination: healthy, warning, critical, disabled, or unconfigured.
- The system SHALL support live data capture on destinations for real-time event inspection.
- The system SHALL provide a Test function to validate destination configuration and downstream connectivity.
- The system SHALL support post-processing pipelines on destinations, applied before data transmission.
- The system SHALL automatically inject system fields into events: `cribl_pipe`, `cribl_host`, `cribl_input`, `cribl_output`, `cribl_route`, `cribl_wp`.
- The system SHALL support tagging destinations with metadata for filtering and grouping (tags are not added to events).
- The system SHALL support GitOps environment specification for branch-specific destination enablement.

### Backpressure and Buffering (General)

- The system SHALL support three backpressure behaviors on streaming destinations: **Block** (refuse new data), **Drop** (discard events), or **Persistent Queue** (buffer to disk).
- The system SHALL support persistent queue (PQ/dPQ) modes: **Error** (queue on destination unavailability), **Backpressure** (queue during congestion), and **Always On** (immediate queuing).
- The system SHALL support persistent queue configuration: file size limit (default 1 MB), queue size limit (default 5 GB, max 1 TB), compression (None or Gzip), queue-full behavior (Block or Drop), and strict FIFO ordering with optional drain rate throttling.
- The system SHALL limit persistent queue to 1 GB per destination per worker process on Cribl-managed Cloud Workers (Enterprise plan).

### Non-Streaming Destination General Behavior

- The system SHALL use a local staging directory to buffer, format, and compress files before uploading to the final destination.
- The system SHALL close staged files when any of these conditions are met: file size limit (default 32 MB), file open time limit (default 300s), idle time limit (default 30s), or open file limit (default 100 concurrent files).
- The system SHALL support dead-lettering for failed uploads, moving undeliverable files after exceeding retry limits (default 20 retries).
- The system SHALL support automatic removal of empty staging directories (default every 300 seconds).
- The system SHALL support force-close of all staged files on orderly shutdown.
- The system SHALL support data formats: JSON (default), Raw, and Parquet (Linux only).
- The system SHALL support compression: gzip (default, recommended) or none for JSON/Raw; compression not available for Parquet.

### Retry Behavior (General for HTTP-based Streaming Destinations)

- The system SHALL implement exponential backoff retry for configurable HTTP status codes.
- The system SHALL by default retry on 401, 403, 408, 429, and 5xx responses, and drop on 1xx, 3xx, and other 4xx responses.
- The system SHALL support configurable pre-backoff interval (default 1000 ms), backoff multiplier (default 2), and backoff limit (default 10s, max 180s).
- The system SHALL honor Retry-After headers up to a maximum of 180 seconds.
- The system SHALL support optional timeout retries with independent backoff configuration.

### HTTP Connection Management (General)

- The system SHALL reuse HTTP connections via keepalives and discard connections after 2 minutes of first use to prevent destination stickiness.
- The system SHALL support round-robin DNS for distributing requests across multiple resolved IPs.
- The system SHALL support HTTP/S proxy configuration via system proxy settings.
- The system SHALL support configurable request concurrency (default 5, max 32 per worker process).
- The system SHALL support configurable request timeout (default 30 seconds).
- The system SHALL support payload compression (enabled by default on most HTTP destinations).
- The system SHALL support extra HTTP headers with encrypted value transmission.
- The system SHALL support failed request logging modes: None, Payload, or Payload + Headers (with sensitive header redaction).

---

## Streaming Destinations -- HTTP/S Protocol

### Destination: Amazon CloudWatch Logs

- **Description**: Streams log data to AWS CloudWatch Logs. Does not require Cribl Stream to run on AWS.
- **Requirements**:
  - The system SHALL send events to CloudWatch Logs log groups and log streams.
  - The system SHALL support configurable log group name and log stream prefix (generates unique stream names per instance).
  - The system SHALL drop events more than 24 hours older than the newest event in a batch (CloudWatch constraint).
  - The system SHALL monitor out-of-range dropped events via Status tab and debug logs.
- **Auth model**: AWS IAM -- Auto (SDK credential chain), Manual (access key/secret key), or Secret (stored key pair). Supports AssumeRole for cross-account access (duration 900-43200s). Supports SAML/Okta SSO via environment variables.
- **Protocol**: HTTPS streaming. TLS supported.
- **Required permissions**: `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Amazon Kinesis Data Streams

- **Description**: Outputs events to Amazon Kinesis Data Streams with records up to 1 MB uncompressed. Does not require running on AWS.
- **Requirements**:
  - The system SHALL support two delivery modes: batched (PutRecord API with NDJSON, gzip-compressed) and non-batched (PutRecords API with single JSON per record, uncompressed).
  - The system SHALL include a header line with format type, event count, and payload size when using batched mode.
  - The system SHALL support configurable record size limit (default 1 MB uncompressed).
  - The system SHALL support compression: Gzip (default) or None.
  - The system SHALL support the ListShards API (default) for higher rate limits (1000/sec vs 10/sec with DescribeStream).
- **Auth model**: AWS IAM -- Auto, Manual, or Secret. Supports AssumeRole.
- **Protocol**: HTTPS streaming to Kinesis API.
- **Required permissions**: `kinesis:ListShards` or `kinesis:DescribeStream`, `kinesis:PutRecord` (batched), `kinesis:PutRecords` (non-batched).
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Amazon SQS

- **Description**: Sends events to Amazon SQS queues. Supports Standard and FIFO queue types.
- **Requirements**:
  - The system SHALL accept queue name, URL, or ARN as JavaScript expression.
  - The system SHALL support Standard (default) and FIFO queue types.
  - The system SHALL support auto-creation of queues if they do not exist (enabled by default).
  - The system SHALL enforce a 256 KB maximum record size per SQS specification.
  - The system SHALL support message group ID for FIFO queues (default `'cribl'`, overridable via `__messageGroupId`).
  - The system SHALL support internal fields: `__messageGroupId`, `__sqsMsgAttrs`, `__sqsSysAttrs`.
  - The system SHALL support configurable concurrent requests (max 10).
- **Auth model**: AWS IAM -- Auto, Manual, or Secret. Supports AssumeRole.
- **Protocol**: HTTPS to SQS API.
- **Required permissions**: `sqs:ListQueues`, `sqs:SendMessage`, `sqs:SendMessageBatch`, `sqs:CreateQueue`, `sqs:GetQueueAttributes`, `sqs:SetQueueAttributes`, `sqs:GetQueueUrl`.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Azure Data Explorer (Streaming Mode)

- **Description**: Sends data to Azure Data Explorer (ADX) via HTTP payloads directly to ADX tables. Lower latency for smaller data volumes.
- **Requirements**:
  - The system SHALL support both Batching (default, non-streaming) and Streaming ingestion modes.
  - The system SHALL support data formats: JSON (default), Raw, or Parquet (batching mode only).
  - The system SHALL support named data mappings or JSON mapping objects for field transformations.
  - The system SHALL support database settings validation (requires Database Viewer and Table Viewer roles).
  - The system SHALL support duplicate prevention via `ingestIfNotExists` with `ingest-by` extent tags.
- **Auth model**: Azure service principal -- Client Secret or Certificate. Requires Tenant ID, Client ID, Microsoft Entra ID endpoint, and Scope.
- **Protocol**: HTTPS for streaming; S3-compatible staging for batching.
- **Required permissions**: Database Ingestor or Table Ingestor role minimum; Database Viewer for validation.
- **Backpressure**: Block, Drop, or Persistent Queue (streaming mode only).

### Destination: Azure Event Hubs

- **Description**: Streams data to Azure Event Hubs using Kafka protocol over TCP.
- **Requirements**:
  - The system SHALL send data using the Kafka binary protocol to Event Hub endpoints.
  - The system SHALL support data formats: JSON (entire event) or `_raw` field only.
  - The system SHALL support acknowledgment levels: Leader (default), All, or None.
  - The system SHALL support per-event topic override via `__topicOut` field.
  - The system SHALL support internal fields: `__topicOut`, `__key`, `__headers`, `__kafkaTime`.
  - The system SHALL support configurable record size limit (default 768 KB uncompressed).
- **Auth model**: PLAIN (connection string, manual or secret) or OAUTHBEARER (Microsoft Entra ID with client ID, tenant, scope, and client secret or certificate).
- **Protocol**: Kafka binary TCP protocol (port 9093). TLS enabled by default. No HTTP proxy support.
- **Required permissions**: Azure Event Hubs Data Sender role.
- **Backpressure**: Block, Drop, or Persistent Queue.
- **Retry**: Up to 5 attempts with exponential backoff (initial 300ms, multiplier 2-20, limit 30s).

### Destination: Azure Monitor Logs (Deprecated)

- **Description**: Sends streaming data to Azure Monitor Logs (Log Analytics workspace) via HTTP. Deprecated -- Microsoft recommends using Microsoft Sentinel instead (legacy API retiring September 14, 2026).
- **Requirements**:
  - The system SHALL send data to the Azure Log Analytics HTTP Data Collector API.
  - The system SHALL support configurable log type (overridable per event via `__logType`).
  - The system SHALL support resource ID for resource-centric queries.
  - The system SHALL enforce Azure limits of 500 custom fields per data type.
- **Auth model**: Azure Log Analytics Workspace ID and Primary/Secondary Shared Workspace Key (Manual or Secret).
- **Protocol**: HTTPS streaming.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Microsoft Sentinel

- **Description**: Sends log and metric events to Microsoft Sentinel SIEM via HTTPS. Supports Azure Public Cloud, US Government Cloud, and 21Vianet.
- **Requirements**:
  - The system SHALL support two endpoint methods: URL (direct data collection endpoint) or ID (endpoint + DCR ID + stream name).
  - The system SHALL send individual top-level fields, not a combined `_raw` field.
  - The system SHALL require field names to match Data Collection Rule (DCR) schema exactly.
  - The system SHALL enforce a 1000 KB body size limit (API maximum).
  - The system SHALL support per-event endpoint override via `__url` field.
  - The system SHALL support per-event custom headers via `__headers` field.
  - The system SHALL identify metric events via `__criblMetrics` internal field.
- **Auth model**: OAuth 2.0 flow with Login URL, Client ID, OAuth Secret, and Scope (environment-specific).
- **Protocol**: HTTPS POST with JSON payload. Gzip compression enabled by default.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: ClickHouse

- **Description**: Routes observability data (logs, metrics, traces) to ClickHouse via HTTP for monitoring and analysis.
- **Requirements**:
  - The system SHALL send data to ClickHouse via its HTTP interface.
  - The system SHALL support data formats: JSONCompactEachRowWithNames (default, bandwidth-optimized) and JSONEachRow.
  - The system SHALL support automatic field-to-column mapping with optional field exclusion.
  - The system SHALL support custom column mappings via Column Mapping table with JavaScript expressions.
  - The system SHALL support "Retrieve table columns" feature for auto-populating schema.
  - The system SHALL support async inserts with optional wait-for-disk-persistence confirmation.
  - The system SHALL enforce a maximum body size of 10 MB.
  - The system SHALL support schema mismatch logging with event file output.
- **Auth model**: None, Basic (username/password or credentials secret), or SSL User Certificate.
- **Protocol**: HTTP/HTTPS. Configurable TLS versions, SNI, mutual authentication.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Cortex XSIAM

- **Description**: Streams event data to Palo Alto Networks' Cortex XSIAM for threat detection and response.
- **Requirements**:
  - The system SHALL send data to the XSIAM `/logs/v1/event` endpoint.
  - The system SHALL support automatic format parsing for CEF, LEEF, Syslog, JSON, and raw formats.
  - The system SHALL serialize JSON with native object representation for the `data` field.
  - The system SHALL enforce a 5 MB limit per individual event and 9.5 MB per batch.
  - The system SHALL support configurable request rate limiting (default 400 req/s, max 2000).
  - The system SHALL require the Palo Alto XSIAM Pack for data mapping.
- **Auth model**: Bearer Token (manual or stored secret).
- **Protocol**: HTTPS with JSON Content-Type.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: CrowdStrike Falcon LogScale

- **Description**: Streams data to CrowdStrike Falcon LogScale HTTP Event Collector (HEC) in JSON or Raw format.
- **Requirements**:
  - The system SHALL send events to LogScale HEC endpoints (`/api/v1/ingest/hec` for JSON, `/api/v1/ingest/hec/raw` for raw).
  - The system SHALL support request format selection (JSON or Raw) matching the endpoint path.
  - The system SHALL recommend setting `sourceType` to a LogScale parser name; unmapped values default to `kv` parser.
  - The system SHALL drop nested JSON in the `fields` element.
- **Auth model**: HEC API token (Manual or Secret).
- **Protocol**: HTTPS streaming. TLS configurable.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: CrowdStrike Falcon Next-Gen SIEM

- **Description**: Sends data to CrowdStrike Falcon Next-Gen SIEM for streaming delivery.
- **Requirements**:
  - The system SHALL send payloads containing only the `_raw` field (NG SIEM licensing based on payload size; parsers designed for `_raw` only).
  - The system SHALL require post-processing pipeline to strip all fields except `_raw`.
  - The system SHALL support request format: JSON (default) or Raw.
  - The system SHALL require creation of a "Cribl Data Connector" in CrowdStrike NG SIEM.
- **Auth model**: Authentication token (Manual or Secret).
- **Protocol**: HTTPS streaming.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Datadog

- **Description**: Forwards log, metric, and trace events to Datadog via REST API endpoints specific to each data type and geographic region.
- **Requirements**:
  - The system SHALL route events to separate endpoints: Logs (`http-intake.logs.{domain}`), Metrics (`api.{domain}`), APM Traces (`trace.agent.{domain}`).
  - The system SHALL support regions: US (default), US3, US5, Europe, US1-FED, AP1, and Custom.
  - The system SHALL identify metric events by the `__criblMetrics` internal field and support Datadog metric types: gauge, counter, rate, distribution.
  - The system SHALL support "Send counter metrics as count" to prevent Datadog from transforming counter to gauge.
  - The system SHALL support log format options: `application/json` (default) or `text/plain`.
  - The system SHALL support per-event tags via `ddtags` field (comma-separated string format, not array).
  - The system SHALL merge UI-configured tags with event `ddtags` values; event tags do not override UI tags.
  - The system SHALL batch requests separately per unique API key and tags by default.
  - The system SHALL support per-event API key override via `__agent_api_key` field.
- **Auth model**: API key (Manual or Secret). Optional per-event key via `__agent_api_key`.
- **Protocol**: HTTPS REST API.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Dynatrace HTTP

- **Description**: Sends logs to Dynatrace's SaaS or ActiveGate endpoints via HTTP.
- **Requirements**:
  - The system SHALL support three endpoint types: Cloud (SaaS), ActiveGate, and Manual (custom URL).
  - The system SHALL support per-event endpoint override via `__url` field.
  - The system SHALL support per-event custom headers via `__headers` field.
  - The system SHALL enforce a maximum body size of 5 MB (default 4 KB).
- **Auth model**: Dynatrace API access token (Auth Token or Text Secret).
- **Protocol**: HTTPS streaming.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Dynatrace OTLP

- **Description**: Sends traces, logs, and metrics to Dynatrace using OTLP v1.3.1 via HTTP with Binary Protobuf encoding.
- **Requirements**:
  - The system SHALL send data using OTLP v1.3.1 (fixed version).
  - The system SHALL use HTTP protocol with Binary Protobuf encoding only (no JSON support).
  - The system SHALL support SaaS and ActiveGate endpoint types.
  - The system SHALL support custom path overrides for traces, metrics, and logs endpoints.
  - The system SHALL drop non-conforming events with error logging.
  - The system SHALL enforce a default body size limit of 2048 KB.
- **Auth model**: Dynatrace API access token stored as text secret.
- **Protocol**: HTTP with Binary Protobuf.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Elastic Cloud

- **Description**: Forwards events to Elastic Cloud deployments via the Bulk API, optimized for Elastic Cloud.
- **Requirements**:
  - The system SHALL accept Elastic Cloud IDs for connection.
  - The system SHALL support configurable data stream or index via JavaScript expression (overridable per event via `__index`).
  - The system SHALL support Elastic ingest pipeline integration.
  - The system SHALL normalize fields: `_time` to `@timestamp` (millisecond resolution), `host` to `host.name`.
  - The system SHALL support document ID inclusion for Time Series Data Streams (TSDS).
- **Auth model**: Manual username/password, Secret, Manual API Key, or Secret API Key.
- **Protocol**: HTTPS Bulk API.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Elasticsearch

- **Description**: Sends events to self-hosted Elasticsearch clusters via the Bulk API, supporting data streams.
- **Requirements**:
  - The system SHALL support Elasticsearch Bulk API URLs with load balancing and configurable weights.
  - The system SHALL support write actions: Index (for updates) or Create (for data streams, append-only).
  - The system SHALL support per-event index override via `__index` field.
  - The system SHALL support Elastic ingest pipeline references via JavaScript expression.
  - The system SHALL normalize fields: `_time` to `@timestamp`, `host` to `host.name`.
  - The system SHALL support Elastic version auto-detection or explicit 6.x/7.x selection.
- **Auth model**: Manual username/password, Secret, Manual API Key, or Secret API Key.
- **Protocol**: HTTPS Bulk API. Gzip compression enabled by default.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Google Cloud Chronicle API

- **Description**: Sends data to Google Cloud Chronicle using the v1alpha ImportLogs ingestion method. Chronicle's parsers transform raw data into Unified Data Model (UDM).
- **Requirements**:
  - The system SHALL send raw, unstructured data for Chronicle's built-in parser transformation.
  - The system SHALL support configurable default log type from Google's dynamic list.
  - The system SHALL support log type hierarchy: event `__logType` field > Default log type setting.
  - The system SHALL support namespace for data domain classification (overridable via `__namespace`).
  - The system SHALL support custom labels with RBAC flag for data access control.
  - The system SHALL enforce a default body size limit of 5120 KB and flush period of 5 seconds.
- **Auth model**: Google service account credentials (direct or stored secret). Requires GCP project ID and instance UUID.
- **Protocol**: HTTPS to Chronicle API.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Google Cloud Logging

- **Description**: Streams log data to Google Cloud Logging for real-time storage, management, search, and analysis.
- **Requirements**:
  - The system SHALL compress all payloads using gzip.
  - The system SHALL support log location types: Project, Organization, Billing Account, or Folder.
  - The system SHALL support log name validation and sanitization (replace invalid characters, enforce 512-character max).
  - The system SHALL support payload formats: Text or JSON.
  - The system SHALL support resource type and labels (must correspond to valid Google monitored resource types).
  - The system SHALL support severity expressions mapped to LogSeverity values.
  - The system SHALL automatically map `_time` to LogEntry timestamp.
  - The system SHALL support configurable request rate throttling up to 2000 requests/second.
  - The system SHALL support advanced LogEntry fields: trace, span ID, HTTP request, operation, source location.
- **Auth model**: Auto (GOOGLE_APPLICATION_CREDENTIALS env var), Manual (service account JSON), or Secret. Requires `Logs Writer` role.
- **Protocol**: HTTPS with gzip compression.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Google Cloud Pub/Sub

- **Description**: Sends data to Google Cloud Pub/Sub managed messaging service.
- **Requirements**:
  - The system SHALL support configurable topic ID with dynamic per-event override via `__topicOut`.
  - The system SHALL support auto-creation of topics if enabled.
  - The system SHALL support ordered delivery to maintain event sequence.
  - The system SHALL support regional publishing with auto-selection default.
  - The system SHALL support configurable batch size (default 10 items), batch timeout (default 100ms), max queue size (default 100), and max batch size (default 256 KB).
  - The system SHALL require alternate topics specified via `__topicOut` to already exist; missing topics result in dropped events.
- **Auth model**: Auto (GOOGLE_APPLICATION_CREDENTIALS), Manual (service account JSON), or Secret. Requires `roles/pubsub.publisher` minimum; `roles/pubsub.editor` for topic creation.
- **Protocol**: HTTPS to Pub/Sub API.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Google Security Operations (SecOps)

- **Description**: Streams data to Google Security Operations (formerly Chronicle) for security telemetry. Supports structured UDM and unstructured log formats.
- **Requirements**:
  - The system SHALL support sending data as Unstructured (raw logs for SecOps parsing) or pre-structured UDM.
  - The system SHALL support UDM Entities for log enrichment via `v2/entities:batchCreate` endpoint.
  - The system SHALL support API versions V2 (recommended) and V1 (legacy).
  - The system SHALL support log type management with custom log types and event-level `__logType` override.
  - The system SHALL require UDM fields (`metadata`, `principal`, `network`) as top-level event fields.
  - The system SHALL enforce a default request timeout of 90 seconds.
- **Auth model**: Service Account Credentials (direct or secret) for V2; API Key for V1.
- **Protocol**: HTTPS streaming.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Grafana Cloud

- **Description**: Sends data to Grafana Cloud's Loki (logs) and Prometheus (metrics) services, routing events based on internal fields.
- **Requirements**:
  - The system SHALL route events containing `__criblMetrics` to Prometheus; all others to Loki.
  - The system SHALL add a `source` label automatically if no labels exist (prevents Loki rejection).
  - The system SHALL support separate Loki and Prometheus endpoint URLs with independent authentication.
  - The system SHALL support message formats: Protobuf (default) or JSON.
  - The system SHALL apply Snappy compression for Prometheus payloads and configurable Gzip for Loki JSON.
  - The system SHALL support custom log labels with event-level override via `__labels` field.
  - The system SHALL support structured metadata via `__structuredMetadata` field.
  - The system SHALL support metric renaming expression (default: replace `.` with `_`).
- **Auth model**: Auth token (bearer or text secret) or Basic (username/password or credentials secret) -- configured independently for Loki and Prometheus.
- **Protocol**: HTTPS with Protobuf/JSON.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Honeycomb

- **Description**: Streams events to Honeycomb datasets for observability.
- **Requirements**:
  - The system SHALL send events to a configurable Honeycomb dataset.
- **Auth model**: API key (Manual or Secret).
- **Protocol**: HTTPS streaming.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: InfluxDB

- **Description**: Streams data to InfluxDB (v1.x, v2.0.x) and InfluxDB Cloud.
- **Requirements**:
  - The system SHALL support v1 API (`/write`) and v2 API (`/api/v2/write`, requires InfluxDB 1.8+).
  - The system SHALL support configurable timestamp precision (default milliseconds).
  - The system SHALL support dynamic value fields: parse measurement names to extract value fields (enabled by default).
  - The system SHALL support v1 API database name field; v2 API bucket and organization ID fields.
- **Auth model**: None (default), Auth Token (bearer or text secret), or Basic (username/password or credentials secret).
- **Protocol**: HTTPS to InfluxDB Write API.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Loki

- **Description**: Streams log events to Grafana Loki log aggregation system.
- **Requirements**:
  - The system SHALL support message formats: Protobuf (default) or JSON with Gzip compression.
  - The system SHALL support custom labels as name/value pairs with dynamic expressions.
  - The system SHALL support event-level label override via `__labels` field.
  - The system SHALL support structured metadata via `__structuredMetadata` field.
  - The system SHALL support per-event custom headers via `__headers` field (when dynamic headers enabled).
  - The system SHALL default to 15-second flush period and 1 concurrent request per worker process.
- **Auth model**: None, Auth Token (bearer or text secret), or Basic (username/password or credentials secret).
- **Protocol**: HTTPS with Protobuf or JSON.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: New Relic Events

- **Description**: Sends events to New Relic via the Event API as custom events.
- **Requirements**:
  - The system SHALL support configurable region with custom endpoint option.
  - The system SHALL require a New Relic Account ID.
  - The system SHALL support default `eventType` with per-event override.
  - The system SHALL support per-event API key override via `__newRelic_apiKey` field.
- **Auth model**: New Relic Ingest License API key (Manual or Secret). Per-event override via `__newRelic_apiKey`.
- **Protocol**: HTTPS to Event API.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: New Relic Logs and Metrics

- **Description**: Streams events to New Relic's Log API and Metric API.
- **Requirements**:
  - The system SHALL route logs to the Log API and metrics to the Metric API.
  - The system SHALL support configurable log type with per-event override.
  - The system SHALL support custom name-value field enrichment.
  - The system SHALL support per-event API key override via `__newRelic_apiKey`.
  - The system SHALL enforce a default body size limit of 1024 KB.
- **Auth model**: New Relic Ingest License API key (Manual or Secret).
- **Protocol**: HTTPS to Log/Metric APIs.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: OpenTelemetry (OTel)

- **Description**: Sends events to OTLP-compliant targets supporting native OTel Trace, Metric, and Log events.
- **Requirements**:
  - The system SHALL support protocols: gRPC (default) and HTTP.
  - The system SHALL use Binary Protobuf encoding only (no JSON Protobuf).
  - The system SHALL support OTLP versions: 0.10.0 (default) and 1.3.1.
  - The system SHALL support compression: Gzip (default), Deflate (gRPC only), or None.
  - The system SHALL support separate endpoint overrides for traces, metrics, and logs (HTTP only).
  - The system SHALL drop non-conforming events with error logging.
  - The system SHALL support gRPC-specific settings: connection timeout (10s default), keep-alive ping (30s), custom metadata.
  - The system SHALL support HTTP-specific settings: round-robin DNS, keep-alive headers, custom HTTP headers.
- **Auth model**: None, Bearer token (static or secret), or HTTP Basic (static or secret).
- **Protocol**: gRPC or HTTP with Binary Protobuf. Default port 4137 (443 with TLS).
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Prometheus

- **Description**: Sends metric events to systems supporting Prometheus' remote write specification.
- **Requirements**:
  - The system SHALL send data to a configurable remote write URL.
  - The system SHALL automatically protobuf-encode and snappy-compress payloads per the remote_write specification.
  - The system SHALL only accept events with `__criblMetrics` internal field; others are dropped.
  - The system SHALL support metric renaming expression (default: replace `.` with `_`).
  - The system SHALL support metadata transmission (type/metricFamilyName) with configurable flush period.
- **Auth model**: None, Auth Token (bearer or text secret), or Basic (username/password or credentials secret).
- **Protocol**: HTTPS with Protobuf + Snappy compression.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: SentinelOne AI SIEM

- **Description**: Streams data to SentinelOne Singularity AI SIEM using HTTP Event Collector (HEC) protocol.
- **Requirements**:
  - The system SHALL support regional endpoints: US, Canada, EMEA, India, South India, Australia, or custom tenant URL.
  - The system SHALL support two endpoint paths: `/services/collector/event` (structured JSON) and `/services/collector/raw` (plain text).
  - The system SHALL support configurable event fields: serverHost, logFile, parser, dataSource (category/name/vendor), event.type.
  - The system SHALL enforce a default body size limit of 5120 KB and flush period of 5 seconds.
  - The system SHALL not support mutual TLS (mTLS).
- **Auth model**: API key as Bearer token (Manual or Secret).
- **Protocol**: HTTPS HEC.
- **Backpressure**: Block, Drop, or Persistent Queue (note: PQ support indicated but limited).

### Destination: SentinelOne DataSet

- **Description**: Sends log events to SentinelOne/Scalyr DataSet platform via the DataSet API's `addEvents` endpoint. (Being superseded by SentinelOne AI SIEM.)
- **Requirements**:
  - The system SHALL send batches of events as JSON to the `addEvents` endpoint.
  - The system SHALL support DataSet sites: US (default), Europe, or Custom endpoint.
  - The system SHALL enforce a rate limit of 10 MB/sec per session (2.5 MB/sec recommended).
  - The system SHALL create sessions per unique `serverHost` value.
  - The system SHALL support severity mapping: integer range 0-6 and string enums (finest, finer, fine, info, warning, error, fatal).
  - The system SHALL support timestamp auto-conversion to nanosecond precision.
  - The system SHALL support message field logic: missing sends entire event, non-object sends `{message: <value>}`, object sends flattened fields.
- **Auth model**: DataSet API key with "Log Write Access" permission (Manual or Secret).
- **Protocol**: HTTPS to DataSet API.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: ServiceNow Cloud Observability

- **Description**: Routes observability data (logs, metrics, traces) to ServiceNow Cloud Observability via OTLP v1.3.1.
- **Requirements**:
  - The system SHALL support protocols: gRPC (default) and HTTP.
  - The system SHALL use Binary Protobuf encoding for HTTP; Protocol Buffers for gRPC.
  - The system SHALL support US and Europe regional endpoints (ingest.lightstep.com:443 / ingest.eu.lightstep.com:443).
  - The system SHALL support custom endpoint configuration for IPv4, IPv6, URLs, or IP addresses.
  - The system SHALL support compression: Gzip (default), None, or Deflate (gRPC).
  - The system SHALL enforce OTLP v1.3.1 Protobuf schema compliance; drop non-conforming events.
  - The system SHALL support configurable token header name (default `lightstep-access-token`).
- **Auth model**: ServiceNow Cloud Observability access token stored as text secret.
- **Protocol**: gRPC or HTTP with OTLP v1.3.1.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: SignalFx (Splunk Observability Cloud)

- **Description**: Sends events to Splunk Observability Cloud (SignalFx).
- **Requirements**:
  - The system SHALL require an Observability Cloud realm name.
- **Auth model**: Observability Cloud API access token (Manual or Secret).
- **Protocol**: HTTPS streaming.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Splunk HEC

- **Description**: Streams data to Splunk's HTTP Event Collector, sending events to the cooked/parsed pipeline segment. Recommended for Splunk Cloud.
- **Requirements**:
  - The system SHALL support three HEC endpoint types: `/services/collector/event`, `/services/collector/raw`, and `/services/collector/s2s`.
  - The system SHALL support load balancing across multiple endpoints with configurable traffic weights.
  - The system SHALL identify metric events by `__criblMetrics` internal field.
  - The system SHALL support multi-metric output (Splunk 8.0+) bundling multiple metrics per event.
  - The system SHALL use `_raw` field for log events if present; otherwise serialize entire event as JSON.
  - The system SHALL NOT use Indexer Acknowledgement (causes channel GUID validation failures).
  - The system SHALL enforce a Splunk Cloud body size limit of 1 MB.
  - The system SHALL default: body size 4096 KB, flush period 1s, request concurrency 5 (max 32).
- **Auth model**: HEC Auth token (Manual or Secret).
- **Protocol**: HTTPS HEC. TLS supported. Compression enabled by default.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Sumo Logic

- **Description**: Sends logs and metrics to Sumo Logic via HTTP Hosted Collector with HTTP Sources.
- **Requirements**:
  - The system SHALL identify metric events via `__criblMetrics` internal field.
  - The system SHALL support data formats: JSON (default) or Raw.
  - The system SHALL batch requests separately per unique Source Name/Source Category combination (high cardinality increases memory).
  - The system SHALL support custom source name/category override via `__sourceName` and `__sourceCategory` fields.
  - The system SHALL require UTF-8 encoded data.
  - The system SHALL enforce a default body size of 1024 KB (Sumo Logic recommends 100 KB to 1 MB before compression).
- **Auth model**: Endpoint URL from Sumo Logic HTTP Logs and Metrics Source (no separate API key).
- **Protocol**: HTTPS POST.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Wavefront

- **Description**: Streams metrics events to Wavefront (VMware Aria Operations for Applications).
- **Requirements**:
  - The system SHALL require a Wavefront domain name.
- **Auth model**: Wavefront API token (Manual or Secret).
- **Protocol**: HTTPS streaming.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Webhook

- **Description**: Sends log and metric events to arbitrary HTTP endpoints. Highly configurable for custom integrations.
- **Requirements**:
  - The system SHALL support HTTP methods: POST (default), PUT, or PATCH.
  - The system SHALL support load balancing with configurable weights across multiple URLs.
  - The system SHALL support data format options: NDJSON (default), JSON Array, Custom (JavaScript expressions), or Advanced (JavaScript code blocks, e.g., for Elasticsearch Bulk API or Splunk HEC formatting).
  - The system SHALL support per-event URL override via `__url` field (without load balancing).
  - The system SHALL support per-event custom headers via `__headers` field.
  - The system SHALL support configurable body size up to 500 MB (default 4096 KB).
  - The system SHALL support five authentication methods: None, Auth token, Auth token (text secret), Basic, Basic (credentials secret), and OAuth (with login URL, token refresh, custom parameters, and nested response token mapping).
- **Auth model**: None, Bearer Token, Basic Auth, or OAuth (with token refresh and custom parameter support).
- **Protocol**: HTTP/HTTPS. Configurable TLS with mutual authentication.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Wiz Defend

- **Description**: Streams data to Wiz Defend cloud security platform via an HEC-compatible endpoint.
- **Requirements**:
  - The system SHALL support configurable Wiz Data Center (e.g., us1, us8, eu1).
  - The system SHALL support Wiz Environment: Production or Government.
  - The system SHALL require a Wiz Connector ID for cross-validation.
  - The system SHALL send the selected Wiz Defend Source type (AWS CloudTrail, Azure Activity Logs, GCP Audit Logs) in the `WizDefend-Source-Type` HTTP header.
- **Auth model**: Authentication token (Manual or Secret).
- **Protocol**: HTTPS HEC-compatible. TLS configurable with mutual authentication.
- **Backpressure**: Block, Drop, or Persistent Queue.

---

## Streaming Destinations -- TCP Protocol

### Destination: Amazon MSK

- **Description**: Sends data to Amazon Managed Streaming for Apache Kafka (MSK) topics using Kafka binary protocol.
- **Requirements**:
  - The system SHALL send data using the Kafka binary TCP protocol.
  - The system SHALL support record formats: JSON (default) or Protobuf (OpenTelemetry signals).
  - The system SHALL support compression codecs: None, Gzip (recommended), Snappy, LZ4, ZSTD.
  - The system SHALL support acknowledgment levels: Leader (default), All, or None.
  - The system SHALL support per-event topic override via `__topicOut`.
  - The system SHALL support internal fields: `__topicOut`, `__key`, `__headers`, `__kafkaTime`, `__keySchemaIdOut`, `__valueSchemaIdOut`.
  - The system SHALL default to `Date.now()` timestamp; `__kafkaTime` field preserves upstream timestamps.
  - The system SHALL support configurable events-per-batch (default 1000), record size limit (default 768 KB).
  - The system SHALL automatically enable TLS for IAM authentication.
- **Auth model**: AWS IAM -- Auto, Manual, or Secret. Supports AssumeRole.
- **Protocol**: Kafka binary TCP. No HTTP proxy support; direct connection required.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Confluent Cloud

- **Description**: Sends data to Kafka topics on Confluent Cloud's managed Kafka platform.
- **Requirements**:
  - The system SHALL support SASL authentication mechanisms: PLAIN, SCRAM-SHA-256, SCRAM-SHA-512, GSSAPI/Kerberos.
  - The system SHALL support Schema Registry integration with URL, default key/value schema IDs, and optional authentication/TLS.
  - The system SHALL NOT support Kerberos for Cribl-managed Cloud Workers.
  - The system SHALL require SNI field to remain blank (managed by Kafka library internally).
  - The system SHALL support Protobuf encoding for OpenTelemetry signals and drop non-conforming events.
  - The system SHALL support compression: None, Gzip (default), Snappy, LZ4, ZSTD.
- **Auth model**: SASL (PLAIN, SCRAM, Kerberos) with manual or stored credentials.
- **Protocol**: Kafka binary TCP. No HTTP proxy support.
- **Backpressure**: Block, Drop, or Persistent Queue.
- **Retry**: Up to 5 attempts, initial 300ms, exponential backoff, max 30-180s.

### Destination: Kafka

- **Description**: Sends data to Apache Kafka topics using binary TCP protocol.
- **Requirements**:
  - The system SHALL support record formats: JSON (default) or Protobuf.
  - The system SHALL support compression: None, Gzip, Snappy, LZ4, ZSTD.
  - The system SHALL support acknowledgment levels: Leader (default), All, or None.
  - The system SHALL support Schema Registry for Avro/JSON encoded data with optional TLS.
  - The system SHALL support SASL mechanisms: PLAIN, SCRAM-256, SCRAM-512, GSSAPI/Kerberos.
  - The system SHALL support internal fields: `__topicOut`, `__key`, `__headers`, `__kafkaTime`, `__keySchemaIdOut`, `__valueSchemaIdOut`.
  - The system SHALL support configurable events-per-batch (default 1000), record size limit (default 768 KB).
  - The system SHALL leave SNI field blank (Kafka library manages it internally).
- **Auth model**: SASL (PLAIN, SCRAM, Kerberos) with manual or stored credentials.
- **Protocol**: Kafka binary TCP. No HTTP proxy support.
- **Backpressure**: Block, Drop, or Persistent Queue.
- **Retry**: Up to 5 attempts, initial 300ms, backoff multiplier 2-20, limit 30s.

### Destination: Microsoft Fabric Real-Time Intelligence

- **Description**: Sends data to Microsoft Fabric Eventstreams via Kafka-based Cribl Data source.
- **Requirements**:
  - The system SHALL send data using the Kafka binary protocol.
  - The system SHALL support data formats: JSON (entire event) or `_raw` field only.
  - The system SHALL support acknowledgment levels: Leader (default), All, or None.
  - The system SHALL support per-event topic override via `__topicOut`.
  - The system SHALL require creation of a Cribl data source in Microsoft Fabric first.
  - The system SHALL NOT require load balancing (Fabric handles it).
- **Auth model**: PLAIN (SASL with connection string as password) or OAUTHBEARER (Microsoft Entra ID with client ID, tenant ID, scope, and secret or certificate).
- **Protocol**: Kafka binary TCP.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Splunk Load Balanced

- **Description**: Distributes data across multiple Splunk receivers using Splunk-to-Splunk (S2S) protocol. Data arrives cooked and parsed.
- **Requirements**:
  - The system SHALL support S2S protocol versions v3 and v4 (default).
  - The system SHALL support load balancing with configurable weights across multiple receivers.
  - The system SHALL support Indexer Discovery for automatic receiver detection in clustering environments.
  - The system SHALL support compression for v4: Disabled (default) or Always.
  - The system SHALL support multi-measurement metric output (Splunk 8.0+).
  - The system SHALL automatically serialize events without `_raw` to JSON.
  - The system SHALL support nested field serialization: None or JSON.
  - The system SHALL limit ACK mechanism to shutdown signals only.
  - The system SHALL support connection limiting per worker process.
  - The system SHALL support endpoint health fluctuation allowance (default 100ms grace period).
  - The system SHALL minimize in-flight data loss by detecting indexer shutdown.
  - The system SHALL support DNS re-resolution for dynamic receiver addition via A records.
  - The system SHALL support Splunk Cloud mutual TLS authentication via Universal Forwarder credentials package.
- **Auth model**: Token-based authentication to cluster manager (Manual or Secret).
- **Protocol**: Splunk S2S (TCP). TLS configurable with mutual authentication.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Splunk Single Instance

- **Description**: Streams data to a single Splunk instance. Data arrives cooked and parsed.
- **Requirements**:
  - The system SHALL support S2S protocol versions v3 and v4 (default).
  - The system SHALL support compression for v4: Disabled (default) or Always.
  - The system SHALL automatically serialize events without `_raw` to JSON.
  - The system SHALL support multi-measurement metric output (Splunk 8.0+).
  - The system SHALL minimize in-flight data loss by detecting indexer shutdown.
- **Auth model**: Shared secret auth token (Manual or Secret).
- **Protocol**: Splunk S2S (TCP). TLS configurable.
- **Backpressure**: Block, Drop, or Persistent Queue.

---

## Streaming Destinations -- Other Protocols (TCP/UDP)

### Destination: Graphite

- **Description**: Sends metrics data to Graphite backend for time-series storage and visualization.
- **Requirements**:
  - The system SHALL support protocols: UDP (default) and TCP.
  - The system SHALL support configurable host and port (default 8125).
  - The system SHALL enforce a UDP record size limit (default 512 bytes).
  - The system SHALL support TCP-specific settings: throttling, connection/write timeouts, flush period.
  - The system SHALL NOT support TLS.
- **Auth model**: None.
- **Protocol**: TCP or UDP. No TLS.
- **Backpressure**: Block, Drop, or Persistent Queue (TCP only).

### Destination: NetFlow

- **Description**: Forwards NetFlow v5 and v9 UDP traffic to downstream NetFlow collectors without modification.
- **Requirements**:
  - The system SHALL exclusively forward NetFlow v5 and v9 UDP traffic.
  - The system SHALL require the `__netflowRaw` field (generated by NetFlow Source with pass-through enabled).
  - The system SHALL discard events not containing `__netflowRaw`.
  - The system SHALL forward the export payload as received without modifying flow records.
  - The system SHALL NOT preserve original transport headers.
  - The system SHALL support source IP spoofing (on-prem only) via `udp-sender` helper binary with `CAP_NET_RAW`.
  - The system SHALL support configurable MTU (default 1500 bytes) when spoofing enabled.
- **Auth model**: None.
- **Protocol**: UDP. No TLS.
- **Backpressure**: Persistent Queue supported.

### Destination: SNMP Trap

- **Description**: Forwards SNMP Trap events to remote destinations.
- **Requirements**:
  - The system SHALL forward SNMP trap packets to configurable destinations (address and port, default 162).
  - The system SHALL support multiple destinations.
  - The system SHALL NOT modify SNMP packets during forwarding.
  - The system SHALL NOT generate native SNMP packets from non-SNMP input data.
  - The system SHALL support the SNMP Trap Serialize Function for pipeline-modified events.
  - The system SHALL NOT support TLS or Persistent Queues.
- **Auth model**: None.
- **Protocol**: UDP (port 162 default). No TLS.
- **Backpressure**: None (no PQ support).

### Destination: StatsD

- **Description**: Streams metrics data to StatsD destinations.
- **Requirements**:
  - The system SHALL support protocols: UDP (default) and TCP.
  - The system SHALL support configurable host and port (default 8125).
  - The system SHALL enforce a UDP record size limit (default 512 bytes).
  - The system SHALL support TCP-specific: throttling, connection/write timeouts, flush period.
  - The system SHALL NOT support TLS.
- **Auth model**: None.
- **Protocol**: TCP or UDP. No TLS.
- **Backpressure**: Block, Drop, or Persistent Queue (TCP only).

### Destination: StatsD Extended

- **Description**: Streams metrics to StatsD Extended (DogStatsD-compatible) destinations with tag support.
- **Requirements**:
  - The system SHALL support protocols: UDP (default) and TCP.
  - The system SHALL support the DogStatsD extended tag format.
  - The system SHALL NOT support TLS.
- **Auth model**: None.
- **Protocol**: TCP or UDP. No TLS.
- **Backpressure**: Block, Drop, or Persistent Queue (TCP only).

### Destination: Syslog

- **Description**: Sends data to syslog receivers via TCP or UDP, supporting RFC 3164 and RFC 5424 formats.
- **Requirements**:
  - The system SHALL support protocols: TCP (default) and UDP.
  - The system SHALL support message formats: RFC 3164 and RFC 5424.
  - The system SHALL support timestamp formats: syslog format or ISO8601.
  - The system SHALL support configurable facility (default user), severity (default notice), and app name (default Cribl).
  - The system SHALL construct RFC-compliant payloads from `facility`, `severity`, `_time`, `host`, `message` fields.
  - The system SHALL support complete message replacement via `__syslogout` field (no validation performed).
  - The system SHALL support internal fields: `__priority`, `__facility`, `__severity`, `__appname`, `__procid`, `__msgid`, `__syslogout`.
  - The system SHALL support octet count framing (RFC 5425/6587) or newline-delimited framing.
  - The system SHALL support UDP source IP spoofing (on-prem only) via `udp-sender` helper binary with `CAP_NET_RAW`.
  - The system SHALL enforce a UDP record size limit (default 1500 bytes, max 2048 bytes).
  - The system SHALL support TCP load balancing with configurable weights and TLS with mutual authentication.
- **Auth model**: None (relies on network-level security). TLS supported for TCP.
- **Protocol**: TCP or UDP. TLS for TCP. No compression.
- **Backpressure**: Block, Drop, or Persistent Queue (TCP).

---

## Non-Streaming (Batch) Destinations

### Destination: Amazon S3 Compatible Stores

- **Description**: Stores data in Amazon S3 or S3-compatible services. Does not require running on AWS.
- **Requirements**:
  - The system SHALL stage files locally, compress, then upload to S3.
  - The system SHALL support data formats: JSON (default), Raw, or Parquet (Linux only).
  - The system SHALL support compression: gzip (default, recommended), none, or other formats. Configurable levels: Best Speed (default), Normal, Best Compression.
  - The system SHALL support partitioning via JavaScript expression (defaults to date-based structure).
  - The system SHALL auto-append 6-character random sequences to filenames to prevent overwrites.
  - The system SHALL support multipart uploads when concurrent file parts >= 2 (default 4).
  - The system SHALL support configurable staging file limit (default 100, min 10, max 4200).
  - The system SHALL support S3 Object ACL, Storage Class selection (Standard, Intelligent Tiering, Glacier variants, etc.).
  - The system SHALL support server-side encryption: None, S3-managed, or KMS-managed.
  - The system SHALL support Parquet-specific options: automatic/manual schema, versions (1.0, 2.4, 2.6), data page version, group row limit, page size, statistics, page indexes, checksums, and metadata.
  - The system SHALL evaluate bucket name expressions at init time only (event-level variables unavailable).
- **Auth model**: Auto (AWS SDK credential chain), Manual (access key/secret key), or Secret. Supports AssumeRole (duration 900-43200s).
- **Protocol**: HTTPS S3 API. Signature version v4.
- **Required permissions**: `s3:PutObject`, `s3:ListBucket`, `s3:GetBucketLocation`, plus `kms:GenerateDataKey` and `kms:Decrypt` for multipart with KMS.
- **Backpressure**: Block or Drop. Dead-lettering available.

### Destination: Azure Blob Storage

- **Description**: Sends data to Azure Blob Storage and Azure Data Lake Storage Gen2. Works from any cloud or on-prem.
- **Requirements**:
  - The system SHALL stage files locally before compression and upload.
  - The system SHALL support data formats: JSON (default), Raw, or Parquet (Linux only).
  - The system SHALL support container auto-creation if missing.
  - The system SHALL support blob access tier selection: Hot, Cool, Cold, Archive, or default.
  - The system SHALL support configurable endpoint suffix for custom Azure endpoints.
  - The system SHALL support Parquet options matching S3 destination capabilities.
- **Auth model**: Manual (connection string), Secret, Client Secret (service principal with tenant/client IDs), or Certificate (certificate-based service principal). Requires Storage Blob Data Contributor RBAC role.
- **Protocol**: HTTPS to Azure Blob API.
- **Backpressure**: Block or Drop. Dead-lettering available. No Persistent Queue.

### Destination: Azure Data Explorer (Batching Mode)

- **Description**: Sends batched data to Azure Data Explorer via staging in storage containers. ADX pulls and ingests batches.
- **Requirements**:
  - The system SHALL stage data in a storage container for ADX batch ingestion.
  - The system SHALL support flush-immediately mode to bypass aggregation.
  - The system SHALL support extent tags for data partition labeling and duplicate prevention.
  - The system SHALL support report level: FailuresOnly (default), DoNotReport, or FailuresAndSuccesses.
  - The system SHALL support retain-blob-on-success option.
- **Auth model**: Azure service principal -- Client Secret or Certificate.
- **Protocol**: HTTPS to ADX ingestion service.
- **Backpressure**: Block or Drop. Dead-lettering available. No PQ in batching mode.

### Destination: Cloudflare R2

- **Description**: Sends data to Cloudflare R2 object storage via S3-compatible API.
- **Requirements**:
  - The system SHALL connect to R2 endpoint (e.g., `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`).
  - The system SHALL support data formats: JSON (default), Raw, or Parquet (Linux only).
  - The system SHALL support multipart uploads with concurrent file parts (default 4, range 1-10).
  - The system SHALL support Parquet options matching S3 destination capabilities.
  - The system SHALL require buckets to pre-exist; non-existent buckets generate errors.
- **Auth model**: Auto (AWS SDK credential chain) or Secret (stored credentials).
- **Protocol**: HTTPS S3-compatible API.
- **Required permissions**: `s3:ListBucket`, `s3:GetBucketLocation`, `s3:PutObject`.
- **Backpressure**: Block or Drop. No Persistent Queue.

### Destination: Cribl Lake

- **Description**: Delivers data to Cribl Lake with automatic partitioning optimized for Cribl Search.
- **Requirements**:
  - The system SHALL be exclusive to Cribl.Cloud deployments.
  - The system SHALL require `_time` as a number (null/string values converted to `Date.now() / 1000`).
  - The system SHALL NOT allow use of built-in `cribl_logs` or `cribl_metrics` datasets.
  - The system SHALL require parsed, named event fields for Lakehouse functionality.
  - The system SHALL support outbound HTTPS on port 443 (non-configurable).
- **Auth model**: Implicit via Cribl.Cloud organization credentials.
- **Protocol**: HTTPS. Non-streaming.
- **Backpressure**: Block or Drop. No Persistent Queue.

### Destination: Databricks

- **Description**: Delivers data to Databricks Unity Catalog volumes using a 3-level namespace (Catalog/Schema/Volume).
- **Requirements**:
  - The system SHALL support Unity Catalog 3-level namespace: Catalog (default `main`), Schema (default `external`), Events Volume Name (default `events`).
  - The system SHALL support data formats: JSON (default), Raw, or Parquet.
  - The system SHALL support dynamic upload paths via JavaScript expressions with global variables.
  - The system SHALL support Parquet options matching S3 destination capabilities.
- **Auth model**: Unity Catalog OAuth with service principal credentials (Workspace ID, Client ID, Client Secret as text secret, OAuth Scope defaults to `all-apis`).
- **Protocol**: HTTPS to Databricks REST API.
- **Backpressure**: Block or Drop. Dead-lettering available. No Persistent Queue.

### Destination: Exabeam

- **Description**: Sends data to Exabeam Security Operations Platform (SIEM) via Google Cloud Storage buckets.
- **Requirements**:
  - The system SHALL deliver data through Google Cloud Storage buckets using Exabeam Cloud Collector credentials.
  - The system SHALL enforce a maximum file size of 10 MB.
  - The system SHALL require events in original, unmodified form for Exabeam parsers to function.
  - The system SHALL support Exabeam-specific metadata: site name, site ID, timezone offset.
  - The system SHALL support autofill from Exabeam connection strings.
- **Auth model**: Service account credentials from Exabeam's Cribl Cloud Collector (access key/secret). Requires Storage Admin or Owner role on GCS buckets.
- **Protocol**: HTTPS to Google Cloud Storage API.
- **Backpressure**: Block or Drop. Dead-lettering available. No Persistent Queue.

### Destination: Filesystem/NFS

- **Description**: Outputs files to local or network-attached file systems (NFS).
- **Requirements**:
  - The system SHALL write files to configurable output location paths.
  - The system SHALL support data formats: JSON (default), Raw, or Parquet.
  - The system SHALL support configurable writing high watermark buffer size (default 64 KB).
  - The system SHALL support disk space protection (block or drop on low disk).
  - The system SHALL NOT support TLS or Persistent Queues.
- **Auth model**: None (uses OS-level file system permissions).
- **Protocol**: Local filesystem I/O.
- **Backpressure**: Block or Drop. Dead-lettering available.

### Destination: Google Cloud Storage

- **Description**: Non-streaming destination that exports data to Google Cloud Storage buckets with local staging and compression.
- **Requirements**:
  - The system SHALL stage files locally, compress, then upload to GCS.
  - The system SHALL support data formats: JSON (default), Raw, or Parquet.
  - The system SHALL support Object ACL assignment (default Private).
  - The system SHALL support Storage Class selection.
  - The system SHALL default endpoint to `https://storage.googleapis.com`.
  - The system SHALL support Parquet options matching S3 destination capabilities.
- **Auth model**: Auto (GCP IAM, on-prem Compute Engine VMs only with uniform/fine-grained ACL), Manual (HMAC key/secret, requires fine-grained ACLs and `storage.objects.create`), or Secret.
- **Protocol**: HTTPS to GCS API.
- **Backpressure**: Block or Drop. Dead-lettering available. No Persistent Queue.

### Destination: MinIO

- **Description**: Sends data to MinIO object storage via S3-compatible API.
- **Requirements**:
  - The system SHALL connect to configurable MinIO endpoints (e.g., `http://minioHost:9000`).
  - The system SHALL support data formats: JSON (default), Raw, or Parquet (Linux only).
  - The system SHALL support multipart uploads with concurrent parts (default 4, up to 10).
  - The system SHALL support S3-compatible settings: Object ACL, Storage Class, server-side encryption, signature version v4.
  - The system SHALL support Parquet options matching S3 destination capabilities.
- **Auth model**: Auto (AWS SDK credential chain), Manual (access key/secret key), or Secret.
- **Protocol**: HTTPS S3-compatible API. TLS configurable.
- **Required permissions**: `s3:ListBucket`, `s3:GetBucketLocation`, `s3:PutObject`.
- **Backpressure**: Block or Drop. Dead-lettering available. No Persistent Queue.

### Destination: Amazon Security Lake

- **Description**: Delivers OCSF-conforming data to AWS Security Lake as Parquet files. Linux only; not available on Windows/macOS.
- **Requirements**:
  - The system SHALL write data exclusively as Parquet files.
  - The system SHALL require events conforming to the Open Cybersecurity Schema Framework (OCSF).
  - The system SHALL require an AWS Account ID and custom source name.
  - The system SHALL NOT support replay.
  - The system SHALL support Parquet options: schema, versions, data page version, row groups, page size, statistics, indexes.
  - The system SHALL require the AssumeRole ARN and External ID from the custom source.
- **Auth model**: Auto only (EC2 instance IAM role or environment variables). Must run on AWS.
- **Protocol**: HTTPS S3 API.
- **Required permissions**: `s3:ListBucket`, `s3:GetBucketLocation`, `s3:PutObject`, plus `kms:GenerateDataKey` and `kms:Decrypt` for multipart.
- **Backpressure**: Block or Drop. No Persistent Queue.

---

## Internal Destinations

### Destination: Default

- **Description**: Internal routing mechanism that specifies a default output from among already-configured destinations.
- **Requirements**:
  - The system SHALL provide a pre-configured Output ID of `default` (not modifiable via UI).
  - The system SHALL allow selection of any configured destination as the default output.
  - The system SHALL prevent circular references (cannot select an Output Router that points back to Default).
  - The system SHALL NOT apply TLS, PQ, or authentication.

### Destination: Output Router

- **Description**: Internal meta-destination that enables dynamic, rule-based routing of events to one or more downstream destinations using JavaScript filter expressions.
- **Requirements**:
  - The system SHALL evaluate routing rules top-to-bottom against event content.
  - The system SHALL support JavaScript filter expressions per rule.
  - The system SHALL support a "Final" toggle per rule (default on): when disabled, events clone to all matching destinations.
  - The system SHALL route unmatched events to the Default Destination.
  - The system SHALL NOT allow routing to another Output Router or a Default pointing back to one.
  - The system SHALL evaluate filters against pre-processing and Route Pipeline fields, but BEFORE post-processing.
  - The system SHALL NOT apply TLS, PQ, or authentication.

### Destination: DevNull

- **Description**: Drops all events. Used for testing pipelines and routes.
- **Requirements**:
  - The system SHALL discard all incoming events without processing or forwarding.
  - The system SHALL require no configuration.
  - The system SHALL be pre-configured upon installation.

### Destination: Cribl HTTP

- **Description**: Relays data to a Cribl HTTP Source for inter-node communication without double-billing.
- **Requirements**:
  - The system SHALL serialize events using HTTP payload format and deliver over HTTP.
  - The system SHALL prevent double-billing when data transfers between Worker Groups sharing infrastructure.
  - The system SHALL require distributed deployments (use Webhook for single-instance testing).
  - The system SHALL forward internal fields (`__criblMetrics`, `__srcIpPort`, `__inputId`, `__outputId`) to receiving HTTP/TCP Sources.
  - The system SHALL support field exclusion with defaults: `__kube_*`, `__metadata`, `__winEvent`.
  - The system SHALL enforce version compatibility: nodes on 3.5.4+ communicate only with 3.5.4+.
  - The system SHALL require TLS parity between destination and source (both enabled or both disabled).
  - The system SHALL support load balancing across multiple Cribl Worker endpoints with traffic weights.
  - The system SHALL support configurable throttling in bytes/second per worker process.
  - The system SHALL support auth token TTL (1-60 minutes) for connected environments.
- **Auth model**: TLS with optional auth token. Cloud-managed TLS is automatic.
- **Protocol**: HTTP/HTTPS. Gzip compression default.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Cribl TCP

- **Description**: Transmits data to a Cribl TCP Source for inter-node communication without double-billing.
- **Requirements**:
  - The system SHALL use streaming binary TCP format.
  - The system SHALL forward all Cribl internal metadata fields by default.
  - The system SHALL support field exclusion blacklists.
  - The system SHALL enforce version compatibility: 3.5.4+ communicates only with 3.5.4+.
  - The system SHALL require TLS parity between destination and source.
  - The system SHALL support load balancing with weight-based distribution and DNS re-resolution.
  - The system SHALL support configurable max connections per worker process.
  - The system SHALL support compression: Gzip (default) or none.
  - The system SHALL support configurable throttling and auth token TTL (1-60 minutes).
- **Auth model**: TLS with optional auth token.
- **Protocol**: Binary TCP. TLS configurable.
- **Backpressure**: Block, Drop, or Persistent Queue.

### Destination: Cribl Search

- **Description**: Sends events directly to Cribl Search over an internal HTTP path.
- **Requirements**:
  - The system SHALL deliver data over HTTP to a Cribl HTTP Source forwarding into Cribl Search's ingestion pipeline.
  - The system SHALL provide free data transfer when meeting eligibility (same organization, shared leader, or identical on-prem licenses).
  - The system SHALL require Cribl Search enabled with Lakehouse Engine.
  - The system SHALL auto-populate Cloud endpoint as `https://search.<workspace>.<organizationId>.cribl.cloud:10200`.
  - The system SHALL support throttling in bytes/second per worker process.
  - The system SHALL forward internal fields including `__criblMetrics` and `__srcIpPort`.
- **Auth model**: Cloud-managed TLS (automatic) or Auth Tokens for cross-environment transfers.
- **Protocol**: HTTPS streaming.
- **Backpressure**: Block, Drop, or Persistent Queue.

---

## Cross-Cutting Capabilities Summary

| Capability | Streaming HTTP | Streaming TCP/Kafka | Streaming UDP | Non-Streaming |
|---|---|---|---|---|
| Persistent Queue | Yes | Yes | No (except NetFlow) | No |
| TLS | Yes | Yes (configurable) | No | Yes (most) |
| Load Balancing | Yes (most) | Yes | N/A | N/A |
| Compression | Yes (payload) | Yes (codec-level) | No | Yes (file-level gzip) |
| Dead-lettering | No | No | No | Yes |
| Parquet support | No | No | No | Yes (Linux only) |
| Post-processing Pipeline | Yes | Yes | Yes | Yes |
| System Fields | Yes | Yes | Yes | Yes |

---

Sources:
- [Destinations Overview](https://docs.cribl.io/stream/destinations/)
- [Managing Destinations](https://docs.cribl.io/stream/managing-destinations/)
- [Amazon S3 Compatible Stores](https://docs.cribl.io/stream/destinations-s3/)
- [Splunk HEC](https://docs.cribl.io/stream/destinations-splunk-hec/)
- [Elasticsearch](https://docs.cribl.io/stream/destinations-elastic/)
- [Kafka](https://docs.cribl.io/stream/destinations-kafka/)
- [Syslog](https://docs.cribl.io/stream/destinations-syslog/)
- [Datadog](https://docs.cribl.io/stream/destinations-datadog/)
- [Webhook](https://docs.cribl.io/stream/destinations-webhook/)
- [Amazon Kinesis](https://docs.cribl.io/stream/destinations-kinesis-streams/)
- [Amazon CloudWatch Logs](https://docs.cribl.io/stream/destinations-cloudwatch-logs/)
- [Azure Blob Storage](https://docs.cribl.io/stream/destinations-azure-blob/)
- [Azure Event Hubs](https://docs.cribl.io/stream/destinations-azure-event-hubs/)
- [Azure Monitor Logs](https://docs.cribl.io/stream/destinations-azure-monitor-logs/)
- [Microsoft Sentinel](https://docs.cribl.io/stream/destinations-sentinel/)
- [Prometheus](https://docs.cribl.io/stream/destinations-prometheus/)
- [InfluxDB](https://docs.cribl.io/stream/destinations-influxdb/)
- [New Relic Events](https://docs.cribl.io/stream/destinations-newrelic-events/)
- [New Relic Logs & Metrics](https://docs.cribl.io/stream/destinations-newrelic/)
- [OpenTelemetry](https://docs.cribl.io/stream/destinations-otel/)
- [Splunk Load Balanced](https://docs.cribl.io/stream/destinations-splunk-lb/)
- [Splunk Single Instance](https://docs.cribl.io/stream/destinations-splunk/)
- [Graphite](https://docs.cribl.io/stream/destinations-graphite/)
- [StatsD](https://docs.cribl.io/stream/destinations-statsd/)
- [Syslog](https://docs.cribl.io/stream/destinations-syslog/)
- [Cribl HTTP](https://docs.cribl.io/stream/destinations-cribl-http/)
- [Cribl TCP](https://docs.cribl.io/stream/destinations-cribl-tcp/)
- [Filesystem/NFS](https://docs.cribl.io/stream/destinations-fs/)
- [Databricks](https://docs.cribl.io/stream/destinations-databricks/)
- [Honeycomb](https://docs.cribl.io/stream/destinations-honeycomb/)
- [Loki](https://docs.cribl.io/stream/destinations-loki/)
- [SignalFx](https://docs.cribl.io/stream/destinations-signalfx/)
- [Wavefront](https://docs.cribl.io/stream/destinations-wavefront/)
- [Sumo Logic](https://docs.cribl.io/stream/destinations-sumo-logic/)
- [Elastic Cloud](https://docs.cribl.io/stream/destinations-elastic-cloud/)
- [Google Cloud Logging](https://docs.cribl.io/stream/destinations-google-logging/)
- [Google Cloud Pub/Sub](https://docs.cribl.io/stream/destinations-google_pubsub/)
- [Google Cloud Storage](https://docs.cribl.io/stream/destinations-google-cloud-storage/)
- [Google Chronicle API](https://docs.cribl.io/stream/destinations-google-chronicle-api/)
- [Google SecOps](https://docs.cribl.io/stream/destinations-google_chronicle/)
- [CrowdStrike Falcon LogScale](https://docs.cribl.io/stream/destinations-humio-hec/)
- [CrowdStrike Next-Gen SIEM](https://docs.cribl.io/stream/destinations-crowdstrike-next-gen-siem/)
- [Cortex XSIAM](https://docs.cribl.io/stream/destinations-xsiam/)
- [ClickHouse](https://docs.cribl.io/stream/destinations-click-house/)
- [Grafana Cloud](https://docs.cribl.io/stream/destinations-grafana_cloud/)
- [Amazon SQS](https://docs.cribl.io/stream/destinations-sqs/)
- [Azure Data Explorer](https://docs.cribl.io/stream/destinations-azure-data-explorer/)
- [Dynatrace HTTP](https://docs.cribl.io/stream/destinations-dynatrace-http/)
- [Dynatrace OTLP](https://docs.cribl.io/stream/destinations-dynatrace-otlp/)
- [ServiceNow Cloud Observability](https://docs.cribl.io/stream/destinations-servicenow/)
- [SentinelOne AI SIEM](https://docs.cribl.io/stream/destinations-sentinel-one-ai-siem/)
- [SentinelOne DataSet](https://docs.cribl.io/stream/destinations-dataset/)
- [Exabeam](https://docs.cribl.io/stream/destinations-exabeam/)
- [Amazon Security Lake](https://docs.cribl.io/stream/destinations-security-lake/)
- [Amazon MSK](https://docs.cribl.io/stream/destinations-msk/)
- [Confluent Cloud](https://docs.cribl.io/stream/destinations-confluent/)
- [NetFlow](https://docs.cribl.io/stream/destinations-netflow/)
- [SNMP Trap](https://docs.cribl.io/stream/destinations-snmp-traps/)
- [Default](https://docs.cribl.io/stream/destinations-default/)
- [DevNull](https://docs.cribl.io/stream/destinations-devnull/)
- [Output Router](https://docs.cribl.io/stream/destinations-output-router/)
- [Cribl Lake](https://docs.cribl.io/stream/destinations-cribl-lake/)
- [Cribl Search](https://docs.cribl.io/stream/destinations-cribl-search/)
- [Cloudflare R2](https://docs.cribl.io/stream/destinations-cloudflare-r2/)
- [MinIO](https://docs.cribl.io/stream/destinations-minio/)
- [Wiz Defend](https://docs.cribl.io/stream/destinations-wiz-defend/)
- [Microsoft Fabric Real-Time Intelligence](https://docs.cribl.io/stream/destinations-fabric-real-time-intelligence/)
