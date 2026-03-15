# Cribl Stream Sources - Requirements Specification

## Sources Overview

Cribl Stream organizes data ingestion into five source categories, each designed for a distinct ingestion pattern.

### General Source System Requirements

- The system SHALL organize sources into five categories: Collector, Pull, Push, System, and Internal.
- The system SHALL support routing ingested data through configurable Pipelines and Routes.
- The system SHALL support QuickConnect as an alternative to Routes for direct destination connections.
- The system SHALL support adding custom fields to events via JavaScript expressions on all source types.
- The system SHALL support optional pre-processing pipelines on all source types.
- The system SHALL support tagging sources with user-defined labels for filtering and grouping.
- The system SHALL expose internal metadata fields (e.g., `__inputId`, `__srcIpPort`) for use in processing functions.
- The system SHALL support GitOps environment targeting on all source types.
- The system SHALL make all HTTP-based sources proxyable.

---

## Collector Sources

Collector sources perform intermittent, batch-oriented data retrieval. They run as jobs triggered manually or on a schedule.

### General Collector Requirements

- The system SHALL support ad hoc and scheduled collection jobs for all collectors.
- The system SHALL distribute files across Workers based on file size during Full Run mode.
- The system SHALL use a single Worker to return available files during Discovery mode.
- The system SHALL support configurable event breaker rulesets with adjustable buffer timeouts (10ms to 12 hours).
- The system SHALL support result routing via normal Routes or direct Pipeline/Destination combinations.
- The system SHALL support output throttling (bytes/second) on collector results.
- The system SHALL support configurable job artifact retention (time-to-live, default 4 hours).
- The system SHALL support resuming interrupted collection jobs on restart.
- The system SHALL support filtering sensitive fields from discovery results.
- The system SHALL expose `__collectible` and `__inputId` internal fields on all collector outputs.

---

### Source: Amazon S3 (Collector)
- **Description:** Ingests data from Amazon S3 buckets, including Splunk DDSS datasets.
- **Requirements:**
  - The system SHALL retrieve objects from specified S3 buckets and paths.
  - The system SHALL support path templating with tokens (`${host}`, `${year}`, `${_time:%Y}`).
  - The system SHALL support DDSS partitioning scheme for optimized Splunk dataset handling.
  - The system SHALL handle gzip-compressed files (`.gz` extension, `x-gzip` MIME type) automatically.
  - The system SHALL support path extractors using JavaScript expressions to enrich discovery results.
  - The system SHALL support recursive subdirectory traversal (enabled by default).
  - The system SHALL support configurable max batch size for metadata objects.
  - The system SHALL discard events outside configured time ranges by default, with a toggle to disable filtering.
  - The system SHALL support custom S3 service endpoints and configurable signature versions (default v4).
  - The system SHALL support connection reuse (enabled by default).
  - The system SHALL support Standard, Intelligent-Tiering, and Glacier Instant Retrieval storage classes.
  - The system SHALL NOT support Glacier or Deep Glacier storage classes.
- **Auth model:**
  - The system SHALL support Auto mode using environment variables or attached IAM roles.
  - The system SHALL support Manual mode with explicit AWS access key and secret key.
  - The system SHALL support Assume Role for cross-account access with configurable session duration (900-43200 seconds).
- **Protocol:** AWS S3 API over HTTPS (TLS), outbound TCP port 443.
- **Required permissions:** `s3:GetObject`, `s3:ListBucket`, `s3:GetBucketLocation`, `kms:Decrypt` (for encrypted data).

---

### Source: Azure Blob Storage (Collector)
- **Description:** Collects data from Azure Blob Storage containers and Azure Data Lake Storage Gen2.
- **Requirements:**
  - The system SHALL retrieve files from specified Azure Blob Storage containers.
  - The system SHALL support path templating with time-based tokens.
  - The system SHALL support path extractors for field enrichment.
  - The system SHALL support recursive subdirectory traversal (enabled by default).
  - The system SHALL optionally include Azure Blob metadata at `__collectible.metadata`.
  - The system SHALL optionally include Azure Blob tags at `__collectible.tags`.
  - The system SHALL support configurable character encoding (UTF-8, UTF-16LE, Latin-1).
  - The system SHALL support hot and cool access tiers; archive tier SHALL NOT be supported.
- **Auth model:**
  - The system SHALL support Manual connection string authentication.
  - The system SHALL support Secrets-based connection string authentication.
  - The system SHALL support Client Secret (Service Principal) authentication with Tenant ID, Client ID, and client secret.
  - The system SHALL support Certificate (Service Principal) authentication.
  - The system SHALL support Shared Access Signatures (account-level only, requiring List and Read permissions).
- **Protocol:** Azure Blob Storage API over HTTPS.
- **Required permissions:** Storage Blob Data Reader (minimum); Storage Blob Data Owner if tags enabled.

---

### Source: Cribl Lake (Collector)
- **Description:** Retrieves data from Cribl Lake datasets.
- **Requirements:**
  - The system SHALL retrieve data from specified Cribl Lake datasets.
  - The system SHALL be available exclusively on Cribl.Cloud deployments.
  - The system SHALL support hybrid Worker Groups on version 4.8 or higher.
- **Auth model:** Implicit via Cribl.Cloud platform authentication.
- **Protocol:** Internal Cribl.Cloud communication.

---

### Source: Database (Collector)
- **Description:** Ingests structured data from relational databases.
- **Requirements:**
  - The system SHALL support MySQL, Oracle (12.1+), PostgreSQL, and SQL Server.
  - The system SHALL execute SQL SELECT queries against configured database connections.
  - The system SHALL support query validation enforcing single SELECT statements (toggleable).
  - The system SHALL provide `${earliest}` and `${latest}` variables in ISO 8601 format.
  - The system SHALL support up to 1 GB of large objects (CLOBs, LOBs, NCLOBs) per field.
  - The system SHALL support state tracking with monotonically increasing numeric columns for incremental collection.
  - The system SHALL persist state even on partial job failures.
  - The system SHALL execute a single collect task on a single Worker Process.
  - The system SHALL omit semicolons for Oracle queries.
- **Auth model:** Database connection credentials configured as reusable connection objects.
- **Protocol:** Database-specific wire protocols (MySQL, Oracle, PostgreSQL, SQL Server).

---

### Source: Filesystem/NFS (Collector)
- **Description:** Ingests data from locally mounted filesystem locations.
- **Requirements:**
  - The system SHALL retrieve data from specified filesystem directories.
  - The system SHALL support path templating with variable tokens.
  - The system SHALL handle gzip-compressed files automatically.
  - The system SHALL NOT follow symlinks.
  - The system SHALL support recursive subdirectory traversal (enabled by default).
  - The system SHALL support destructive mode to delete files post-collection (disabled by default).
  - The system SHALL support configurable character encoding.
  - The system SHALL support custom command piping via stdin/stdout.
  - The system SHALL be restricted to customer-managed hybrid Worker Nodes in Cribl.Cloud.
- **Auth model:** Filesystem permissions of the Cribl Stream process user.
- **Protocol:** Local filesystem I/O.

---

### Source: Google Cloud Storage (Collector)
- **Description:** Extracts data objects from Google Cloud Storage buckets.
- **Requirements:**
  - The system SHALL retrieve objects from specified GCS buckets and paths.
  - The system SHALL support path templating with time-based tokens.
  - The system SHALL support path extractors for field enrichment.
  - The system SHALL support recursive subdirectory traversal (enabled by default).
  - The system SHALL support configurable character encoding (UTF-8, UTF-16LE, Latin-1); encoding SHALL be ignored for Parquet files.
  - The system SHALL support custom GCS endpoints.
  - The system SHALL support replay functionality for historical data collection.
  - The system SHALL support disabling time filter to process all events regardless of time range.
- **Auth model:**
  - The system SHALL support Auto mode using `GOOGLE_APPLICATION_CREDENTIALS` or instance credentials.
  - The system SHALL support Manual mode with direct service account JSON key.
  - The system SHALL support Secret mode referencing stored credentials.
- **Protocol:** GCS API over HTTPS.
- **Required permissions:** `storage.buckets.get`, `storage.objects.get`, `storage.objects.list`.

---

### Source: Health Check (Collector)
- **Description:** Monitors endpoint availability by sending HTTP requests and generating events.
- **Requirements:**
  - The system SHALL support GET and POST HTTP methods for health checks.
  - The system SHALL generate success events on HTTP 200 and error events on non-200/timeout/failure.
  - The system SHALL support four discovery strategies: None, Item List, JSON Response, HTTP Request.
  - The system SHALL distribute health check tasks across all available Workers.
  - The system SHALL support configurable request timeout and retry configuration (Backoff, Static, Disabled).
  - The system SHALL support retry limits (0-20 attempts), backoff multiplier, and configurable HTTP codes triggering retry.
  - The system SHALL honor Retry-After headers up to 20 seconds.
  - The system SHALL support template literal expressions for dynamic URL/header/body values.
  - The system SHALL support URI encoding via `C.Encode.uri()`.
  - The system SHALL expose `__collectStats` with method, URL, and elapsed milliseconds.
- **Auth model:**
  - The system SHALL support None, HTTP Basic, Basic via credentials secret, Login-based (POST token), Login via secret, OAuth, and OAuth via secret.
  - The system SHALL support applying authentication to discovery, health checks, or both.
- **Protocol:** HTTP/HTTPS.

---

### Source: REST/API Endpoint (Collector)
- **Description:** Pulls data from REST API endpoints for services lacking native Cribl connectors.
- **Requirements:**
  - The system SHALL execute jobs through Discovery, Collection, Event Breaking, and Filtering phases.
  - The system SHALL support GET, POST, POST with body, and custom HTTP verbs.
  - The system SHALL support URL interpolation with variables (`${authToken}`, `${earliest}`, `${latest}`).
  - The system SHALL support pagination: None, Response Body/Header Attributes, RFC 5988, Offset/Limit, Page/Size.
  - The system SHALL support "Stop on empty results" to terminate pagination when Event Breaker returns zero events.
  - The system SHALL support discovery types: HTTP Request, JSON Response, Item List, None.
  - The system SHALL support strict discover response parsing (JSON, XML, NDJSON, plain text).
  - The system SHALL support custom discovery code with JavaScript transformation.
  - The system SHALL support state tracking with customizable update and merge expressions.
  - The system SHALL persist state even on partial job failures.
  - The system SHALL support response header capture into `resHeaders` field.
  - The system SHALL support round-robin DNS across multiple IPs.
  - The system SHALL support configurable retry with Backoff, Static, or Disabled algorithms.
- **Auth model:**
  - The system SHALL support Basic, Login (JWT/token via POST), OAuth, Google Service Account OAuth (all with direct or secret variants).
  - The system SHALL support HMAC signature generation.
  - The system SHALL support custom API key headers via `C.Secret()` expressions.
- **Protocol:** HTTP/HTTPS with configurable TLS validation.

---

### Source: Script (Collector)
- **Description:** Enables custom data collection through user-defined scripts.
- **Requirements:**
  - The system SHALL execute discover scripts that output one task per line to stdout.
  - The system SHALL execute collect scripts, passing each discovered item via `$CRIBL_COLLECT_ARG` environment variable.
  - The system SHALL provide `EARLIEST` and `LATEST` environment variables when time ranges are configured.
  - The system SHALL execute scripts with the same permissions as the Cribl Stream process user.
  - The system SHALL NOT be able to terminate scripts once started.
  - The system SHALL support configurable shell (default `/bin/bash`).
  - The system SHALL be restricted to customer-managed hybrid Worker Nodes in Cribl.Cloud.
- **Auth model:** None (inherits OS-level permissions).
- **Protocol:** Local process execution via stdin/stdout.

---

### Source: Splunk Search (Collector)
- **Description:** Gathers results from Splunk search queries.
- **Requirements:**
  - The system SHALL execute Splunk SPL queries against a specified search head URL.
  - The system SHALL support both JSON and CSV output modes.
  - The system SHALL support configurable search endpoints (default `/services/search/v2/jobs/export`).
  - The system SHALL support earliest/latest time boundaries in exact or relative format.
  - The system SHALL support configurable request timeout and retry configuration.
  - The system SHALL support round-robin DNS.
  - The system SHALL support certificate validation toggle.
  - The system SHALL require allowlisting of worker egress IPs for Splunk Cloud deployments.
- **Auth model:**
  - The system SHALL support None, Basic HTTP, Basic via credentials secret, Bearer token, and Bearer token via secret.
- **Protocol:** HTTPS REST API to Splunk search head.

---

## Push Sources

Push sources receive data pushed to them by external systems. They listen on configured addresses/ports.

### General Push Source Requirements

- The system SHALL listen on configurable hostname/IP and port combinations.
- The system SHALL support persistent queues for buffering during downstream outages, with Always On and Smart modes.
- The system SHALL support configurable buffer size limits, queue file sizes, and disk space limits.
- The system SHALL support optional gzip compression for persistent queue data.
- The system SHALL support IP allowlist and denylist via regex patterns.
- The system SHALL support activity logging with configurable sample rates.
- The system SHALL support health check endpoints where applicable.

---

### Source: Amazon Data Firehose
- **Description:** Receives data from AWS Data Firehose delivery streams via HTTP endpoint.
- **Requirements:**
  - The system SHALL listen for HTTP requests from AWS Data Firehose delivery streams.
  - The system SHALL support gzip-compressed inbound data via `Content-Encoding: gzip` header.
  - The system SHALL support TLS server-side encryption.
  - The system SHALL support capture of request headers into `__headers` field.
  - The system SHALL expose Firehose-specific metadata: `__firehoseArn`, `__firehoseReqId`, `__firehoseEndpoint`, `__firehoseToken`.
  - The system SHALL provide a health check endpoint at `/cribl_health`.
  - The system SHALL support configurable keep-alive timeout (1-600 seconds, default 5).
  - The system SHALL support requests-per-socket limits for load distribution across Workers.
  - The system SHALL listen on port 10443 internally for Cribl.Cloud deployments.
- **Auth model:** Auth tokens as shared secrets in Authorization header; empty tokens permit unauthorized access.
- **Protocol:** HTTP/HTTPS push.

---

### Source: Cloudflare
- **Description:** Receives logs from Cloudflare's Logpush service using HEC protocol.
- **Requirements:**
  - The system SHALL accept data on `/services/collector`, `/event` (JSON), and `/raw` endpoints.
  - The system SHALL support gzip-compressed inbound data.
  - The system SHALL support TLS with optional mutual authentication (mTLS).
  - The system SHALL apply event breakers only to `/raw` endpoint; `/event` endpoint SHALL bypass breakers.
  - The system SHALL support per-token index restrictions and field assignments.
  - The system SHALL support per-token and summary request metrics (bytes, requests, events, errors).
  - The system SHALL support CORS configuration for browser-based clients.
  - The system SHALL support configurable active request limit per Worker Process (default 256).
  - The system SHALL support X-Forwarded-For header handling for proxy scenarios.
- **Auth model:** Token-based authentication with enable/disable toggle; empty tokens permit unauthorized access.
- **Protocol:** HTTP/HTTPS (HEC protocol).

---

### Source: Datadog Agent
- **Description:** Ingests data from Datadog Agent instances.
- **Requirements:**
  - The system SHALL accept logs (HTTP only), metrics (gauge, rate, counter, histogram), service checks, and agent metadata/events.
  - The system SHALL NOT receive APM traces via Datadog Agent routing.
  - The system SHALL use Datadog API v1 (`use_v2_api.series` must be `false`).
  - The system SHALL support gzip compression for logs and deflate for other data types.
  - The system SHALL optionally extract individual metric events.
  - The system SHALL support API key validation forwarding to Datadog.
  - The system SHALL support many-to-many routing via `Allow API key from events` toggle.
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL expose `__agent_api_key` and `__agent_event_type` internal fields.
- **Auth model:** API key-based via Datadog Agent configuration.
- **Protocol:** HTTP/HTTPS push.

---

### Source: Elasticsearch API
- **Description:** Receives data via Elasticsearch Bulk API protocol, acting as an Elasticsearch endpoint mimic.
- **Requirements:**
  - The system SHALL accept data on configurable Elasticsearch API endpoints with automatic `_bulk` appending.
  - The system SHALL support gzip-compressed inbound data.
  - The system SHALL automatically transform `@timestamp` to `_time` (preserving millisecond precision) and `host.name` to `host`.
  - The system SHALL support proxy mode for forwarding non-Bulk API requests to downstream Elasticsearch.
  - The system SHALL support API version detection for Elasticsearch 6.8.4, 8.3.2, or custom versions.
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL support configurable active request limit (default 256 per Worker).
  - The system SHALL expose `__host`, `__id`, `__index`, `__type`, `__pipeline` internal fields.
- **Auth model:**
  - The system SHALL support None, Basic, Basic via credentials secret, and Auth tokens (bearer).
- **Protocol:** HTTP/HTTPS (Elasticsearch Bulk API).

---

### Source: Grafana
- **Description:** Receives metrics and logs from Grafana Agent via Prometheus remote write and Loki protocols.
- **Requirements:**
  - The system SHALL accept metrics on configurable Remote Write API endpoint (default `/api/prom/push`).
  - The system SHALL accept logs on configurable Logs API endpoint (default `/loki/api/v1/push`).
  - The system SHALL handle snappy-compressed incoming data.
  - The system SHALL support optional structured metadata parsing from Loki payloads.
  - The system SHALL infer metric types from names (`_total`, `_sum`, `_count`, `_bucket` = counter; others = gauge).
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL expose `__labels` for log events and `__structuredMetadata` when enabled.
- **Auth model:**
  - The system SHALL support separate authentication for Loki and Prometheus endpoints.
  - The system SHALL support None, Bearer token, Bearer via secret, HTTP Basic, and Basic via secret.
- **Protocol:** HTTP/HTTPS (Prometheus remote write + Loki push).

---

### Source: HTTP/S (Bulk API)
- **Description:** Receives data over HTTP/S from Cribl Bulk API, Splunk HEC, and Elasticsearch Bulk API formats.
- **Requirements:**
  - The system SHALL listen on configurable port (default preconfigured on 10080).
  - The system SHALL accept JSON-formatted events (one per line, newline-delimited).
  - The system SHALL support Cribl HTTP API (`/_bulk`), Elastic API (`/elastic/_bulk`), and Splunk HEC (`/services/collector`) endpoints.
  - The system SHALL support gzip-compressed inbound data.
  - The system SHALL enforce a 51,200-byte event size limit (system default event breaker).
  - The system SHALL support Splunk HEC acknowledgement (optional).
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL support configurable active request limit (default 256 per Worker).
  - The system SHALL support per-token field injection with field precedence logic.
- **Auth model:** Token-based shared secrets in Authorization header; empty permits unauthorized access.
- **Protocol:** HTTP/HTTPS (multi-protocol: Cribl Bulk, Splunk HEC, Elasticsearch Bulk).

---

### Source: Raw HTTP/S
- **Description:** Receives raw HTTP data, converting each request into events processed through Event Breakers.
- **Requirements:**
  - The system SHALL listen on configurable port (Cribl.Cloud uses ports 20000-20010).
  - The system SHALL apply configurable event breaker rulesets to incoming data.
  - The system SHALL support URI path filtering with wildcard patterns.
  - The system SHALL support HTTP method filtering with wildcard patterns.
  - The system SHALL support gzip-compressed inbound data.
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL support configurable active request limit (default 256, on-prem only).
  - The system SHALL support X-Forwarded-For header handling.
  - The system SHALL expose `__channel` and `__headers` internal fields.
- **Auth model:** Token-based shared secrets; empty permits unauthorized access.
- **Protocol:** HTTP/HTTPS.

---

### Source: Loki
- **Description:** Receives log data from Grafana Loki via Protobuf-based protocol.
- **Requirements:**
  - The system SHALL accept data on configurable Logs API endpoint (default `/loki/api/v1/push`).
  - The system SHALL handle snappy-compressed Protobuf messages from Loki Promtail agents.
  - The system SHALL support optional structured metadata extraction into `__structuredMetadata`.
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL expose `__labels` internal field for routing decisions.
- **Auth model:**
  - The system SHALL support None, Auth token (bearer), Auth token via secret, Basic, and Basic via secret.
- **Protocol:** HTTP/HTTPS (snappy-compressed Protobuf).

---

### Source: Metrics
- **Description:** Receives metrics in StatsD, StatsD Extended, and Graphite wire formats.
- **Requirements:**
  - The system SHALL automatically detect the protocol from the first data received.
  - The system SHALL support StatsD format (`MetricName:value|type`).
  - The system SHALL support StatsD Extended format with dimensions (`MetricName:value|type|#dim=value`).
  - The system SHALL support Graphite format with optional semicolon-separated dimensions.
  - The system SHALL listen on configurable UDP and/or TCP ports.
  - The system SHALL transform metrics into structured fields: `_metric`, `_metric_type`, `_value`, `_time`.
  - The system SHALL support TLS on TCP connections only.
  - The system SHALL drop non-matching lines after protocol auto-detection.
  - The system SHALL support the internal `__criblMetric` field for native downstream serialization.
- **Auth model:** None required for basic operation; IP allowlist for access control.
- **Protocol:** UDP and/or TCP (StatsD/Graphite wire protocols).

---

### Source: Model Driven Telemetry
- **Description:** Receives network device metrics via Model Driven Telemetry (MDT) using gRPC.
- **Requirements:**
  - The system SHALL receive data via gRPC protocol on configurable address and port (default 57000).
  - The system SHALL support self-describing Key/Value Protocol Buffers with YANG data model.
  - The system SHALL operate in dial-out mode only (device initiates connection).
  - The system SHALL support TLS on gRPC connections.
  - The system SHALL support configurable active connection limit (default 1000 per Worker).
  - The system SHALL support configurable shutdown timeout (default 5000ms).
- **Auth model:** Auth tokens as shared secrets; empty permits unauthorized access. Per-token custom fields supported.
- **Protocol:** gRPC with Protocol Buffers.

---

### Source: NetFlow & IPFIX
- **Description:** Receives network flow data via UDP in NetFlow v5, v9, and IPFIX (v10) formats.
- **Requirements:**
  - The system SHALL support NetFlow v5, v9, and IPFIX (v10) with toggleable version support.
  - The system SHALL listen on configurable UDP address and port.
  - The system SHALL break out fields and include message headers for each record.
  - The system SHALL support Community ID specification via `C.Net.communityIDv1()`.
  - The system SHALL support pass-through mode generating `__netflowRaw` for direct NetFlow destination routing.
  - The system SHALL forward packets verbatim without modification in pass-through mode.
  - The system SHALL cache NetFlow v9 templates per exporter (identified by Template ID, Source ID, and IP address).
  - The system SHALL synchronize templates across Workers via Leader Node key-value store.
  - The system SHALL represent IPv4 as dotted octets, IPv6 as colon-separated, MACs as colon-separated strings.
  - The system SHALL support configurable UDP socket buffer size (256 bytes to 4GB).
  - The system SHALL NOT support TLS.
- **Auth model:** None; IP allowlist/denylist for access control.
- **Protocol:** UDP only.

---

### Source: OpenTelemetry (OTel)
- **Description:** Receives traces, metrics, and logs from OTLP-compliant senders.
- **Requirements:**
  - The system SHALL support OTLP versions 0.10.0 and 1.3.1 (default).
  - The system SHALL support gRPC (default port 4317) and HTTP (port 4318) transports.
  - The system SHALL accept binary Protobuf encoding; JSON Protobuf SHALL NOT be supported.
  - The system SHALL support DEFLATE and gzip compression, plus uncompressed data.
  - The system SHALL support optional extraction of individual spans, data points, and log records.
  - The system SHALL act as pass-through (one event per OTel payload) when extraction is disabled.
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL expose `__otlp.version`, `__otlp.type`, and `__otlp.extracted` internal fields.
  - The system SHALL support configurable active connection limit (gRPC: default 1000) and active request limit (HTTP: default 256).
  - The system SHALL handle OTLP 0.19.0 field name changes that are incompatible with 0.10.0.
  - HTTP transport SHALL NOT be available on Cribl.Cloud managed workers.
- **Auth model:**
  - The system SHALL support None, Auth token (bearer), Auth token via secret, Basic, and Basic via secret.
- **Protocol:** gRPC or HTTP/HTTPS (OTLP binary Protobuf).

---

### Source: Prometheus Remote Write
- **Description:** Receives metric data from Prometheus via remote write protocol.
- **Requirements:**
  - The system SHALL accept snappy-compressed Prometheus remote write requests.
  - The system SHALL listen on configurable address, port, and API endpoint (default `/write`).
  - The system SHALL infer metric types from names (`_total`, `_sum`, `_count`, `_bucket` = counter; others = gauge).
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL support X-Forwarded-For header handling for proxy scenarios.
  - The system SHALL return 403 for IP allowlist/denylist violations and 503 when connection limits exceeded.
- **Auth model:**
  - The system SHALL support None, Bearer token (static or secret), and HTTP Basic (credentials or secret).
- **Protocol:** HTTP/HTTPS (Prometheus remote write, snappy-compressed).

---

### Source: SNMP Trap
- **Description:** Receives data from SNMP traps via UDP.
- **Requirements:**
  - The system SHALL listen on configurable UDP port (default 162).
  - The system SHALL support SNMPv3 authentication with three security levels: username only, user auth without privacy, and user auth with privacy.
  - The system SHALL support authentication protocols: MD5, SHA1, SHA224, SHA256, SHA384, SHA512, None.
  - The system SHALL support privacy protocols: AES128, AES256b (Blumenthal), AES256r (Reeder), None.
  - The system SHALL support allowing or dropping unmatched/unauthenticated traps.
  - The system SHALL mark successfully decrypted traps with `__didDecrypt: true`.
  - The system SHALL forward SNMP packets verbatim without modification to SNMP destinations.
  - The system SHALL NOT modify incoming SNMP packet contents.
  - The system SHALL expose `__snmpVersion`, `__srcIpPort`, and `__snmpRaw` internal fields.
  - The system SHALL NOT support TLS.
- **Auth model:** SNMPv3 authentication with configurable users, protocols, and keys.
- **Protocol:** UDP only (SNMP).

---

### Source: Splunk HEC
- **Description:** Receives data via Splunk HTTP Event Collector protocol.
- **Requirements:**
  - The system SHALL accept data on `/event` (JSON), `/raw` (unstructured), and `/s2s` (Splunk-to-Splunk) endpoints.
  - The system SHALL automatically detect the appropriate endpoint for forwarding.
  - The system SHALL apply event breakers only to `/raw` endpoint.
  - The system SHALL support gzip-compressed inbound data via `Content-Encoding: gzip`.
  - The system SHALL support HEC acknowledgments with "fake ack" responses affirming receipt.
  - The system SHALL support per-token index restrictions and field injection.
  - The system SHALL accept tokens in both `Splunk <token>` and plain `<token>` formats.
  - The system SHALL accept tokens via query parameter (`?token=value`).
  - The system SHALL drop Splunk control fields (`crcSalt`, `savedPort`) by default.
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL support per-token and summary metrics (bytes, requests, events, errors).
  - The system SHALL preserve Universal Forwarder timezone information via `__TZ` field.
  - The system SHALL support `__s2sVersion` for S2S protocol version identification.
  - The system SHALL support CORS headers for browser-based clients.
- **Auth model:** Token-based; empty permits unauthorized access.
- **Protocol:** HTTP/HTTPS (Splunk HEC).

---

### Source: Splunk TCP
- **Description:** Receives data from Splunk Universal and Heavy Forwarders via S2S protocol.
- **Requirements:**
  - The system SHALL listen on configurable port (default 9997).
  - The system SHALL support Splunk S2S v3 and v4 protocols (configurable maximum version).
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL support automatic and disabled compression handling.
  - The system SHALL support Proxy Protocol v1/v2.
  - The system SHALL support "Use Universal Forwarder time zone" providing `__TZ` field.
  - The system SHALL drop Splunk control fields by default (storing in `__ctrlFields` if disabled).
  - The system SHALL support metric extraction from S2S protocol data.
  - The system SHALL apply event breaker rulesets only to raw, unparsed data.
  - The system SHALL support configurable active connection limit (default 1000 per Worker).
  - The system SHALL support socket idle timeout and maximum lifespan settings.
  - The system SHALL support forced termination timeout to prevent resource leaks.
- **Auth model:** Token-based shared secrets; empty permits unauthorized access.
- **Protocol:** TCP (Splunk S2S v3/v4).

---

### Source: Syslog
- **Description:** Receives syslog data over UDP/TCP from various devices.
- **Requirements:**
  - The system SHALL support RFC 3164 and RFC 5424 syslog formats.
  - The system SHALL support message-length prefixes per RFC 5425/6587.
  - The system SHALL listen on configurable UDP and/or TCP ports.
  - The system SHALL parse messages into structured fields: `_time`, `facility`, `facilityName`, `severity`, `severityName`, `host`, `appname`, `procid`, `msgid`, `structuredData`, `message`.
  - The system SHALL capture non-compliant data as `_raw` with `__syslogFail` flag.
  - The system SHALL support TCP load balancing to distribute traffic across worker processes.
  - The system SHALL treat each UDP packet as a complete message when "Single Message per UDP" is enabled.
  - The system SHALL support configurable default timezone for timestamps lacking timezone info.
  - The system SHALL support configurable maximum inbound UDP message size (16,384 bytes).
  - The system SHALL support TLS on TCP connections with optional mutual authentication.
  - The system SHALL support Proxy Protocol v1/v2.
  - The system SHALL support configurable active connection limit (default 1000 per Worker).
  - The system SHALL support configurable UDP socket buffer size.
  - The system SHALL forward unencrypted port 514 traffic to 10514.
- **Auth model:** None; TLS and IP allowlist for access control.
- **Protocol:** UDP and/or TCP (syslog).

---

### Source: TCP JSON
- **Description:** Receives newline-delimited JSON data over TCP.
- **Requirements:**
  - The system SHALL accept newline-delimited JSON (NDJSON) with optional header line.
  - The system SHALL support header-based authentication via `authToken` field and common `fields` injection.
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL support optional TCP load balancing across Worker Processes.
  - The system SHALL support Proxy Protocol v1/v2.
  - The system SHALL support configurable active connection limit (default 1000 per Worker).
  - The system SHALL support socket idle timeout and maximum lifespan settings.
  - The system SHALL map `_time`, `host`, `source`, `_raw` to corresponding Splunk fields when routed to Splunk.
- **Auth model:** Manual shared secret or Secret-referenced; empty permits unauthorized access.
- **Protocol:** TCP (NDJSON).

---

### Source: TCP (Raw)
- **Description:** Receives unstructured data via TCP connections.
- **Requirements:**
  - The system SHALL accept raw data with optional connection headers containing auth tokens and metadata.
  - The system SHALL support configurable event breaker rulesets with buffer timeout (10ms-12 hours).
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL support Proxy Protocol for original source IP preservation.
  - The system SHALL support configurable active connection limit (default 1000 per Worker).
  - The system SHALL support socket idle timeout, maximum lifespan, and forced termination timeout.
  - The system SHALL expose `__inputId`, `__srcIpPort`, and `__channel` internal fields.
- **Auth model:** Manual auth token or Secret-referenced; empty permits unauthorized access.
- **Protocol:** TCP.

---

### Source: UDP (Raw)
- **Description:** Receives unparsed data via UDP protocol.
- **Requirements:**
  - The system SHALL treat each UDP message (or line within message) as an independent event.
  - The system SHALL support "Single msg per UDP" toggle to treat each packet as one event.
  - The system SHALL support optional raw bytes capture in `__rawBytes` field.
  - The system SHALL generate events with `_raw`, `_time`, `source` (format `udp|<IP>|<port>`), and `host` fields.
  - The system SHALL support configurable UDP socket buffer size (SO_RCVBUF, 256 bytes to ~4GB).
  - The system SHALL support configurable in-memory buffer size limit (default 1000 events).
  - The system SHALL NOT support TLS.
  - The system SHALL NOT support event breakers.
- **Auth model:** None; IP allowlist regex for access control.
- **Protocol:** UDP only.

---

### Source: Windows Event Forwarder
- **Description:** Receives Windows events via Windows Event Forwarding (WEF) mechanism.
- **Requirements:**
  - The system SHALL receive events from Windows Event Collectors (Windows 10, Server 2012+).
  - The system SHALL support Client Certificate authentication with OCSP revocation checking.
  - The system SHALL support Kerberos authentication with SPN and keytab configuration.
  - The system SHALL support subscription-based event collection with at least one subscription required.
  - The system SHALL support Raw XML and RenderedText format options per subscription.
  - The system SHALL support configurable heartbeat intervals and batch timeouts per subscription.
  - The system SHALL support historical event reading with bookmark tracking.
  - The system SHALL support SLDC compression (enabled by default).
  - The system SHALL support XPath-based query configuration (Simple and Raw XML modes).
  - The system SHALL store bookmark information using `machineId` as keys.
  - The system SHALL support configurable keep-alive timeout (default 90 seconds).
  - The system SHALL support TLS.
  - The system SHALL expose `__subscriptionName` and `__subscriptionVersion` internal fields.
  - Kerberos authentication SHALL NOT be supported on Cribl-managed Cloud workers.
- **Auth model:** Client Certificate or Kerberos authentication.
- **Protocol:** HTTPS (WEF/WinRM, default port 5986).

---

### Source: Zscaler Cloud NSS
- **Description:** Receives log data from Zscaler Nanolog Streaming Service via HEC protocol.
- **Requirements:**
  - The system SHALL accept data on HEC endpoints (default `/services/collector`).
  - The system SHALL support gzip-compressed inbound data.
  - The system SHALL support Zscaler HEC Acks with configurable 200 response toggle.
  - The system SHALL support per-token index restrictions, field mappings, and enable/disable.
  - The system SHALL support TLS.
  - The system SHALL support event breaker rulesets.
  - The system SHALL support CORS configuration.
  - The system SHALL expose `__hecToken`, `__inputId`, `__srcIpPort`, `__ctrlFields`, `__TZ` internal fields.
- **Auth model:** Token-based with optional secrets storage; empty permits unauthorized access.
- **Protocol:** HTTP/HTTPS (HEC protocol).

---

## Pull Sources

Pull sources actively retrieve data from external systems that hold data in queues, streams, or APIs.

### General Pull Source Requirements

- The system SHALL actively poll or subscribe to external data systems.
- The system SHALL support field enrichment via JavaScript expressions.
- The system SHALL support pre-processing pipelines before routing.

---

### Source: Amazon Kinesis Data Streams
- **Description:** Consumes data records from AWS Kinesis Data Streams.
- **Requirements:**
  - The system SHALL consume from specified Kinesis stream names (not ARNs).
  - The system SHALL support configurable shard iterator start position (Earliest or Latest Record).
  - The system SHALL support record data formats: Cribl (NDJSON), Newline JSON, CloudWatch Logs, Event per line.
  - The system SHALL rely on Leader Node to store shard state persistently (in `$CRIBL_HOME/state/`).
  - The system SHALL report sequence numbers from Workers to Leader every five minutes.
  - The system SHALL support adaptive polling (1-second delay when caught up, immediate otherwise).
  - The system SHALL support duplicate prevention options (next record vs. reread last two batches).
  - The system SHALL support Consistent Hashing or Round Robin shard distribution across Workers.
  - The system SHALL support shard selection expressions via JavaScript.
  - The system SHALL support KPL checksum verification.
  - The system SHALL support configurable records limits per call (5,000-10,000) and total (minimum 20,000).
  - The system SHALL expose `__checksum`, `__encryptionType`, `__partitionKey`, `__sequenceNumber` internal fields.
- **Auth model:**
  - The system SHALL support Auto (SDK credential chain), Manual (static credentials), and Secret modes.
  - The system SHALL support AssumeRole for cross-account access.
- **Protocol:** AWS Kinesis API over HTTPS.
- **Required permissions:** `kinesis:GetRecords`, `kinesis:GetShardIterator`, `kinesis:ListShards`.

---

### Source: Amazon SQS
- **Description:** Receives events from Amazon Simple Queue Service.
- **Requirements:**
  - The system SHALL poll specified SQS queues by name, URL, or ARN.
  - The system SHALL support Standard and FIFO queue types.
  - The system SHALL support auto-creation of queues.
  - The system SHALL support configurable message limit per poll (1-10, default 10).
  - The system SHALL support configurable visibility timeout (default 600 seconds).
  - The system SHALL support configurable number of receivers (default 3).
  - The system SHALL support configurable poll timeout (1-20 seconds, default 10).
  - The system SHALL support connection reuse (enabled by default).
  - The system SHALL expose `__sqsMessageId` and `__sqsReceiptHandle` internal fields.
- **Auth model:**
  - The system SHALL support Auto (SDK credential chain), Manual, and Secret modes.
  - The system SHALL support AssumeRole for cross-account access.
  - The system SHALL support SSO providers (SAML, Okta) via temporary credentials.
- **Protocol:** AWS SQS API over HTTPS.
- **Required permissions:** `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes`, `sqs:GetQueueUrl`, optionally `sqs:CreateQueue`.

---

### Source: Amazon S3 (Pull)
- **Description:** Ingests data from S3 using SQS notifications for object creation events.
- **Requirements:**
  - The system SHALL monitor an SQS queue for S3 object creation event notifications.
  - The system SHALL support Amazon Security Lake event subscriptions as an alternative trigger.
  - The system SHALL process compressed files (.gz, .tgz, .tar.gz) and Parquet files (Linux only).
  - The system SHALL support Standard, Intelligent-Tiering, and Glacier Instant Retrieval storage classes.
  - The system SHALL support configurable filename filter via regex (default `.*`).
  - The system SHALL delete SQS messages after successful processing and retain them on errors.
  - The system SHALL support checkpointing to resume file processing after interruption.
  - The system SHALL support tagging S3 objects after successful ingestion.
  - The system SHALL support configurable Parquet chunk size (1-100 MB).
  - The system SHALL support configurable visibility timeout with automatic extension during processing.
  - The system SHALL support custom command processing via stdin/stdout.
  - The system SHALL support configurable socket timeout (default 300 seconds).
- **Auth model:**
  - The system SHALL support Auto (SDK credential chain), Manual, and Secret modes.
  - The system SHALL support AssumeRole for cross-account/region access.
- **Protocol:** AWS S3 + SQS APIs over HTTPS.
- **Required permissions:** `s3:GetObject`, `s3:ListBucket`, `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:ChangeMessageVisibility`, `sqs:GetQueueAttributes`, `sqs:GetQueueUrl`; optionally `s3:GetObjectTagging`, `s3:PutObjectTagging`, `kms:Decrypt`.

---

### Source: Amazon Security Lake
- **Description:** Ingests security data from AWS Security Lake using OCSF-normalized Parquet files.
- **Requirements:**
  - The system SHALL retrieve Parquet files from S3 via SQS notifications.
  - The system SHALL process Parquet files on Linux systems only.
  - The system SHALL support checkpointing to track processing progress and prevent duplicates.
  - The system SHALL automatically extend visibility timeout during processing.
  - The system SHALL support configurable Parquet chunk size (1-100 MB, default 5 MB).
  - The system SHALL support configurable character encoding (UTF-8, UTF-16LE, Latin-1).
  - The system SHALL store Parquet chunks in `CRIBL_TMP_DIR` and remove them after reading.
- **Auth model:**
  - The system SHALL support Auto (SDK credential chain), Manual, and Secret modes.
- **Protocol:** AWS S3 + SQS APIs over HTTPS.

---

### Source: Google Cloud Pub/Sub
- **Description:** Receives real-time messages from Google Cloud Pub/Sub.
- **Requirements:**
  - The system SHALL subscribe to specified Pub/Sub topics and subscriptions.
  - The system SHALL treat all Workers as members of a Consumer Group with load sharing.
  - The system SHALL support monitoring subscriptions directly (bypassing topic management).
  - The system SHALL support auto-creation of topics and subscriptions.
  - The system SHALL support ordered delivery mode for sequence preservation.
  - The system SHALL support configurable concurrent streams (default 5).
  - The system SHALL support configurable request timeout (default 60 seconds).
  - The system SHALL support configurable backlog limit (default 1000 events).
  - The system SHALL expose `__messageId`, `__publishTime`, `__projectId`, `__subscriptionIn` internal fields.
- **Auth model:**
  - The system SHALL support Auto (`GOOGLE_APPLICATION_CREDENTIALS`), Manual (JSON key), and Secret modes.
- **Protocol:** Google Cloud Pub/Sub API (gRPC/HTTPS).
- **Required permissions:** `pubsub.subscriber`, `pubsub.viewer`; `pubsub.editor` for auto-creation.

---

### Source: Azure Event Hubs
- **Description:** Ingests data from Azure Event Hubs using Kafka-compatible protocol.
- **Requirements:**
  - The system SHALL connect to Event Hubs Kafka brokers (default port 9093).
  - The system SHALL use binary protocol over TCP (no HTTP proxy support).
  - The system SHALL require direct network connectivity to Event Hubs brokers.
  - The system SHALL support configurable consumer group (default `Cribl`, should be unique per Event Hub).
  - The system SHALL support "From Beginning" toggle for initial subscription position.
  - The system SHALL support configurable heartbeat, session, rebalance, connection, and request timeouts.
  - The system SHALL support configurable offset commit intervals.
  - The system SHALL support retry with exponential backoff (default 5 attempts).
- **Auth model:**
  - The system SHALL support SASL PLAIN with connection strings.
  - The system SHALL support OAUTHBEARER with Microsoft Entra ID (Client ID, Tenant ID, Scope).
- **Protocol:** Kafka binary protocol over TCP/TLS (port 9093).
- **Required permissions:** Azure Event Hubs Data Receiver role.

---

### Source: Azure Blob Storage (Pull)
- **Description:** Ingests data from Azure Blob Storage using Event Grid notifications via queue.
- **Requirements:**
  - The system SHALL receive notifications via Azure Event Grid when new blobs are added.
  - The system SHALL support configurable filename filter via regex (default `.*`).
  - The system SHALL support block blobs only; append blobs and archive tier SHALL NOT be supported.
  - The system SHALL support Parquet files on Linux (`.parquet`, `.parq`, `.pqt` extensions).
  - The system SHALL support configurable message limit per poll (1-32 messages).
  - The system SHALL support configurable visibility timeout with auto-extension during processing.
  - The system SHALL support skip-on-error toggle for corrupted files.
  - The system SHALL support configurable Parquet chunk size (1-100 MB, default 5 MB) and download timeout.
  - The system SHALL support custom command processing via stdin/stdout.
  - The system SHALL expose `__accountName`, `__source`, `__topic` internal fields.
- **Auth model:**
  - The system SHALL support Manual connection string, Secret connection string, Client Secret, and Certificate (service principal) authentication.
- **Protocol:** Azure Blob Storage + Queue APIs over HTTPS.
- **Required permissions:** Storage Blob Data Reader, Storage Blob Data Contributor.

---

### Source: Confluent Cloud
- **Description:** Ingests Kafka topics from Confluent Cloud managed platform.
- **Requirements:**
  - The system SHALL connect to Confluent Cloud bootstrap servers.
  - The system SHALL automatically detect and decompress Gzip, Snappy, LZ4, or ZSTD compressed data.
  - The system SHALL support multiple topics per source.
  - The system SHALL recommend unique Group IDs per source to minimize rebalancing.
  - The system SHALL support Schema Registry integration for Avro and JSON schemas.
  - The system SHALL use randomized partition assignment (v4.8.2+).
  - The system SHALL handle non-Unix `_time` values by storing original in `__origTime`.
  - The system SHALL support configurable heartbeat, session, rebalance, connection timeouts.
- **Auth model:**
  - The system SHALL support SASL (PLAIN, SCRAM-256, SCRAM-512, GSSAPI/Kerberos).
  - The system SHALL support OAuth (Token URL, Client ID, client secret).
  - The system SHALL support mutual TLS.
- **Protocol:** Kafka binary protocol over TCP/TLS.

---

### Source: CrowdStrike FDR
- **Description:** Ingests data from CrowdStrike Falcon Data Replicator via S3/SQS.
- **Requirements:**
  - The system SHALL read SQS notifications for CrowdStrike-maintained S3 files.
  - The system SHALL support configurable filename filter via regex.
  - The system SHALL support checkpointing for resume after interruption.
  - The system SHALL automatically extend visibility timeout during processing.
  - The system SHALL support configurable message limit (1-10, default 1) and visibility timeout (default 21,600 seconds/6 hours).
  - The system SHALL support configurable character encoding (UTF-8, UTF-16LE, Latin-1).
  - The system SHALL support event breaker rulesets.
  - The system SHALL support custom command processing.
- **Auth model:**
  - The system SHALL support Auto (SDK credential chain), Manual, and Secret modes.
  - The system SHALL support AssumeRole for cross-account access.
- **Protocol:** AWS S3 + SQS APIs over HTTPS.

---

### Source: Office 365 Services
- **Description:** Ingests service health and incident data from Microsoft Graph service communications API.
- **Requirements:**
  - The system SHALL poll Microsoft Graph API for Current Status and Messages content types.
  - The system SHALL support configurable poll intervals (must divide evenly into 60 minutes).
  - The system SHALL reject invalid poll intervals (e.g., 23, 42, 45, 75 minutes).
  - The system SHALL support configurable retry strategies (Backoff, Static, Disabled).
  - The system SHALL support configurable request timeout (default 300 seconds).
- **Auth model:**
  - The system SHALL require Azure AD application registration with Application-type permissions.
  - The system SHALL require `ServiceHealth.Read.All` and `ServiceMessage.Read.All` permissions.
  - The system SHALL support manual or secret-stored client credentials.
- **Protocol:** HTTPS (Microsoft Graph REST API).

---

### Source: Office 365 Activity
- **Description:** Ingests audit data from Office 365 Management Activity API.
- **Requirements:**
  - The system SHALL support content types: Active Directory, Exchange, SharePoint, General, DLP.All.
  - The system SHALL support configurable poll intervals per content type (must divide evenly into 60 minutes).
  - The system SHALL support subscription plans: Enterprise, GCC, GCC High, DoD.
  - The system SHALL support configurable ingestion lag to compensate for Microsoft delivery delays (up to 7,200 minutes).
  - The system SHALL require manual subscription activation via PowerShell or curl.
  - The system SHALL support configurable retry strategies with Retry-After header support.
- **Auth model:**
  - The system SHALL require Azure AD application with `ActivityFeed.Read` and `ActivityFeed.ReadDlp` permissions.
  - The system SHALL support manual or secret-stored client credentials.
- **Protocol:** HTTPS (Office 365 Management Activity API).

---

### Source: Office 365 Message Trace
- **Description:** Retrieves mail-flow metadata from Office 365 for security analysis.
- **Requirements:**
  - The system SHALL poll the Office 365 Reporting Web Service endpoint.
  - The system SHALL support configurable poll intervals (must divide evenly into 60 minutes).
  - The system SHALL support date range configuration with backward offset using relative format.
  - The system SHALL support configurable retry strategies.
  - The system SHALL handle OAuth token expiration after 1 hour (collection jobs exceeding this window will fail with 401).
  - The system SHALL be deprecated; migration to Microsoft Graph Source required before April 8, 2026.
- **Auth model:**
  - The system SHALL support Basic, Basic via secret, OAuth, OAuth via secret, and OAuth Certificate authentication.
  - The system SHALL require `Message Tracking` and `View-Only Recipients` permissions.
- **Protocol:** HTTPS (Office 365 Reporting Web Service REST API).

---

### Source: Microsoft Graph
- **Description:** Ingests Microsoft 365 Message Trace data via Microsoft Graph API.
- **Requirements:**
  - The system SHALL poll the Microsoft Graph API for message trace data.
  - The system SHALL support configurable poll intervals (must divide evenly into 60 minutes).
  - The system SHALL support pagination with multiple API calls per collection.
  - The system SHALL run one collection task per poll interval on a single Worker.
  - The system SHALL support date range configuration with relative time formats.
  - The system SHALL support configurable retry strategies.
  - The system SHALL support job timeout and stuck job mitigation.
- **Auth model:**
  - The system SHALL support OAuth, OAuth via text secret, and OAuth Certificate authentication.
  - The system SHALL require `ExchangeMessageTrace.Read.All` application permissions.
  - The system SHALL support subscription plans: Enterprise, GCC, GCC High, DoD.
- **Protocol:** HTTPS (Microsoft Graph REST API).

---

### Source: Prometheus Scraper
- **Description:** Pulls batched metric data from Prometheus targets on a scheduled basis.
- **Requirements:**
  - The system SHALL support static, DNS, and AWS EC2 discovery types for target identification.
  - The system SHALL scrape configurable paths (default `/metrics`) at configurable poll intervals.
  - The system SHALL distribute collection tasks across Workers after discovery.
  - The system SHALL support DNS discovery via A, AAAA, or SRV records.
  - The system SHALL support AWS EC2 discovery with region and instance filters.
  - The system SHALL support extra dimensions configuration (defaults to `host` and `source`).
  - The system SHALL support configurable HTTP connection timeout (default 30 seconds).
  - The system SHALL support self-signed certificates when verification is disabled.
- **Auth model:**
  - The system SHALL support Manual (inline Basic auth) and Secret (stored credentials) modes.
  - The system SHALL support AWS AssumeRole for EC2 discovery.
- **Protocol:** HTTP/HTTPS (Prometheus scrape endpoint).

---

### Source: Kafka
- **Description:** Ingests data records from Kafka clusters.
- **Requirements:**
  - The system SHALL connect to Kafka bootstrap servers.
  - The system SHALL automatically detect and decompress Gzip, Snappy, LZ4, or ZSTD formats.
  - The system SHALL use binary protocol over TCP (no HTTP proxy support).
  - The system SHALL treat Workers as consumer group members managed by Kafka.
  - The system SHALL recommend unique Group IDs per source to prevent cascade rebalancing.
  - The system SHALL use randomized partition assignment (v4.8.2+).
  - The system SHALL support Schema Registry for Avro and JSON encoded data.
  - The system SHALL handle non-Unix `_time` values by storing original in `__origTime`.
  - The system SHALL support configurable byte limits per partition (default 1MB) and total (default 10MB).
  - The system SHALL support configurable heartbeat, session, rebalance, connection, and request timeouts.
  - The system SHALL support configurable offset commit intervals and thresholds.
  - The system SHALL default to 5-second polling intervals.
- **Auth model:**
  - The system SHALL support SASL (PLAIN, SCRAM-256, SCRAM-512, GSSAPI/Kerberos).
  - The system SHALL support OAuth (Token URL, Client ID, client secret).
- **Protocol:** Kafka binary protocol over TCP/TLS.

---

### Source: Amazon MSK
- **Description:** Ingests data from Amazon Managed Streaming for Apache Kafka clusters.
- **Requirements:**
  - The system SHALL connect to MSK bootstrap servers via Kafka protocol.
  - The system SHALL automatically detect and decompress Gzip, Snappy, LZ4, or ZSTD formats.
  - The system SHALL support only IAM authentication for MSK sources.
  - The system SHALL automatically enable TLS when using IAM authentication.
  - The system SHALL recommend unique Group IDs per source.
  - The system SHALL use randomized partition assignment (v4.8.2+).
  - The system SHALL support configurable Kafka consumer settings (heartbeat, session, rebalance, connection, request, auth timeouts).
  - The system SHALL support configurable retry with exponential backoff.
  - The system SHALL remain operational during Leader failover (existing workers continue).
- **Auth model:**
  - The system SHALL support only IAM authentication: Auto (SDK credential chain), Manual, or Secret modes.
- **Protocol:** Kafka binary protocol over TCP/TLS.

---

### Source: Splunk Search (Pull)
- **Description:** Retrieves data from Splunk via scheduled search queries.
- **Requirements:**
  - The system SHALL execute scheduled Splunk SPL searches on configurable cron intervals.
  - The system SHALL connect to specified search head URL (default `https://localhost:8089`).
  - The system SHALL support JSON and CSV output modes.
  - The system SHALL support earliest/latest time boundaries in absolute and relative formats.
  - The system SHALL support stuck job mitigation via request timeout and job timeout settings.
  - The system SHALL stop scheduling searches when Leader is down.
  - The system SHALL support configurable retry strategies.
  - The system SHALL support round-robin DNS.
- **Auth model:**
  - The system SHALL support None, Basic, Basic via secret, Bearer token, and Bearer token via secret.
- **Protocol:** HTTPS (Splunk REST API).

---

### Source: Wiz
- **Description:** Polls the Wiz cloud security platform API for security events.
- **Requirements:**
  - The system SHALL poll four Wiz API endpoints: Audit Logs (10,000 limit), Configuration Findings (10,000 limit), Issues (no limit), Vulnerabilities (no limit).
  - The system SHALL use `createdAt` timestamp for fetching new events (not `updatedAt`).
  - The system SHALL support state tracking with customizable update and merge expressions.
  - The system SHALL support configurable cron schedule for polling.
  - The system SHALL support configurable job timeout and time-to-live.
  - The system SHALL support retry strategies (Backoff, Static, Disabled).
  - The system SHALL support system proxy configuration.
- **Auth model:**
  - The system SHALL authenticate via OAuth with GraphQL endpoint, Client ID (53-char), and Client Secret (64-char).
  - The system SHALL support configurable authentication URL and audience.
- **Protocol:** HTTPS (Wiz GraphQL API).

---

### Source: OpenAI
- **Description:** Collects organization-level telemetry from OpenAI's platform.
- **Requirements:**
  - The system SHALL support 10 content types: Audit Logs, Costs, Users, Projects, Completions, Embeddings, Moderations, Images, Audio Speeches, Audio Transcriptions.
  - The system SHALL support independent cron-based polling per endpoint.
  - The system SHALL support state tracking with time-based updates and customizable merge expressions.
  - The system SHALL respect OpenAI rate-limit headers.
  - The system SHALL support configurable retry strategies.
  - The system SHALL support system proxy configuration.
- **Auth model:**
  - The system SHALL authenticate via stored API key credential.
  - The system SHALL support optional OpenAI-Organization and OpenAI-Project header values.
- **Protocol:** HTTPS (OpenAI REST API).

---

## System Sources

System sources collect data from the underlying operating system where Cribl Stream or Cribl Edge is running.

---

### Source: AppScope (Deprecated)
- **Description:** Provides visibility into Linux applications without code modification via open-source instrumentation.
- **Requirements:**
  - The system SHALL support UNIX Domain Socket and Network (TCP) connection modes.
  - The system SHALL support configurable AppScope rules matching by process name or command-line arguments.
  - The system SHALL support event breaker rulesets.
  - The system SHALL support disk spooling for Cribl Search integration.
  - The system SHALL support TLS on TCP connections with optional mutual authentication.
  - The system SHALL support Proxy Protocol.
  - The system SHALL report Kubernetes pod metadata as `kube_**` properties when `CRIBL_K8S_POD` is set.
  - The system SHALL be deprecated and removed in a future release.
- **Auth model:** Manual shared secret or Secret-referenced via `authToken`.
- **Protocol:** UNIX socket or TCP.

---

### Source: Datagen
- **Description:** Generates sample data from datagen files for testing and simulation.
- **Requirements:**
  - The system SHALL generate events from specified datagen files on each Worker Process.
  - The system SHALL support configurable events per second per Worker Node (default 10).
  - The system SHALL NOT require TLS or event breakers.
- **Auth model:** None (internal data generation).
- **Protocol:** None (local process).

---

### Source: Exec
- **Description:** Periodically executes commands and collects stdout output.
- **Requirements:**
  - The system SHALL execute shell commands on interval-based (seconds) or cron (UTC) schedules.
  - The system SHALL accept multiline scripts (Bash, Python, PowerShell) via stdin.
  - The system SHALL capture command stdout as event data.
  - The system SHALL support configurable retry limits for failed commands.
  - The system SHALL support event breaker rulesets with configurable buffer timeout.
  - The system SHALL execute commands with the same permissions as the Cribl Stream process user.
  - The system SHALL support disabling via `CRIBL_NOEXEC` environment variable.
  - The system SHALL require prepending `powershell` to commands on Windows.
- **Auth model:** None (local execution, inherits OS permissions).
- **Protocol:** None (local process execution).

---

### Source: File Monitor
- **Description:** Ingests data from text files, compressed archives, and binary log files.
- **Requirements:**
  - The system SHALL support Auto discovery (Linux only, detects files open for writing) and Manual discovery modes.
  - The system SHALL support compressed formats: zip, gzip, zstd, and tar (DEFLATE only for zip).
  - The system SHALL support binary files as base64-encoded chunks.
  - The system SHALL support configurable polling interval (default 10 seconds).
  - The system SHALL support filename allowlist with wildcard patterns and `!` exclusions.
  - The system SHALL support "Collect from End" to jump to file end on first discovery (enabled by default).
  - The system SHALL support minimum/maximum age duration filters.
  - The system SHALL use file header/tail hashes for state tracking (not filenames).
  - The system SHALL support configurable idle timeout (default 300 seconds).
  - The system SHALL support hash length configuration (default 256 bytes) and salt file hash.
  - The system SHALL support delete files after idle timeout (Manual mode only).
  - The system SHALL NOT ingest the same file multiple times.
  - The system SHALL be available on customer-managed hybrid Workers only in Cribl.Cloud.
  - Auto mode SHALL be supported on Linux only.
- **Auth model:** None (filesystem permissions).
- **Protocol:** Local filesystem I/O.

---

### Source: Journal Files
- **Description:** Collects data from systemd journald logging service on Linux.
- **Requirements:**
  - The system SHALL collect from specified journal search paths supporting environment variables.
  - The system SHALL support LZ4 and ZSTD compression formats.
  - The system SHALL support journal allowlist with wildcard filtering (default `system`).
  - The system SHALL support configurable polling interval (default 10 seconds).
  - The system SHALL support JavaScript filter expressions for include/exclude (default `severity <= 4`).
  - The system SHALL support "Current boot only" toggle to skip non-current boot events.
  - The system SHALL support configurable age duration limits.
  - The system SHALL be disabled by default.
  - The system SHALL be available on hybrid workers only in Cribl.Cloud.
- **Auth model:** None (local journal access, user-level by default).
- **Protocol:** Local systemd journal API.

---

### Source: System Metrics
- **Description:** Collects performance metrics from Linux hosts.
- **Requirements:**
  - The system SHALL collect host metrics: system, CPU, memory, network, disk.
  - The system SHALL support process-specific metrics via configurable Process Sets with JavaScript filter expressions.
  - The system SHALL support container metrics via Docker socket.
  - The system SHALL support configurable polling interval (default 10 seconds).
  - The system SHALL support detail levels: Basic, All, Custom, Disabled.
  - The system SHALL support per-CPU metrics, per-interface metrics, and per-device metrics.
  - The system SHALL support network protocol-level metrics (ICMP, TCP, UDP).
  - The system SHALL support disk device/mountpoint filtering and filesystem type selection.
  - The system SHALL support disk spooling with configurable retention (default 24 hours, 100 MB limit).
  - The system SHALL support Linux only for Cribl Stream/Edge.
- **Auth model:** None (local system access).
- **Protocol:** Local system APIs.

---

### Source: System State
- **Description:** Collects snapshots of host system status on a configurable schedule.
- **Requirements:**
  - The system SHALL support eleven collectors: Host Info, Disks & File Systems, DNS, Firewall, Hosts File, Interfaces, Listening Ports, Logged-In Users, Routes, Services, Users and Groups.
  - The system SHALL support configurable polling interval (default 300 seconds).
  - The system SHALL support disk spooling with configurable retention.
  - The system SHALL support macOS with a subset of collectors on Cribl Edge.
  - The system SHALL require separate Worker Groups for Windows and Linux.
  - The system SHALL be available on hybrid workers only in Cribl.Cloud.
- **Auth model:** None (local system access).
- **Protocol:** Local system APIs.

---

## Internal Sources

Internal sources receive data from other Cribl instances and expose operational telemetry.

---

### Source: Cribl HTTP
- **Description:** Receives data from Cribl HTTP Destinations for zero-cost relay between Cribl instances.
- **Requirements:**
  - The system SHALL receive data from paired Cribl HTTP Destinations.
  - The system SHALL prevent double-billing for data relayed between Cribl instances sharing a Leader, identical licenses, or the same Cribl.Cloud Organization.
  - The system SHALL preserve forwarded internal fields in `__forwardedAttrs` structure to prevent data clobbering.
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL require distributed deployment (not single-instance mode).
  - The system SHALL require version compatibility (3.5.4+ communicates only with 3.5.4+).
  - The system SHALL support configurable active request limit (default 256 per Worker).
  - The system SHALL support health check endpoint.
  - The system SHALL support request header capture.
  - The system SHALL support activity logging with configurable sample rate.
- **Auth model:** Token-based authentication (required for Cribl.Cloud).
- **Protocol:** HTTP/HTTPS (Cribl internal protocol).

---

### Source: Cribl TCP
- **Description:** Receives data from Cribl TCP Destinations for data relay between Cribl Edge and Stream.
- **Requirements:**
  - The system SHALL receive data from paired Cribl TCP Destinations.
  - The system SHALL prevent double-billing for relayed data.
  - The system SHALL preserve forwarded internal fields in `__forwardedAttrs` structure.
  - The system SHALL support TLS with optional mutual authentication.
  - The system SHALL require distributed deployment (not single-instance mode).
  - The system SHALL require version compatibility (3.5.4+ communicates only with 3.5.4+).
  - The system SHALL support optional TCP load balancing across Worker Processes.
  - The system SHALL support Proxy Protocol v1/v2.
  - The system SHALL support configurable active connection limit, idle timeout, and max socket lifespan.
- **Auth model:** TLS-based; Cribl.Cloud supports Cribl-provided certificates.
- **Protocol:** TCP (Cribl internal protocol).

---

### Source: Cribl Internal
- **Description:** Captures Cribl Stream's own internal logs and metrics for self-monitoring.
- **Requirements:**
  - The system SHALL provide two data streams: CriblLogs and CriblMetrics.
  - CriblLogs SHALL capture internal logs from Worker Processes (distributed) or entire instance (single-instance).
  - CriblLogs SHALL exclude API Process logs.
  - CriblMetrics SHALL deliver event throughput and transformation metrics aggregated every 2 seconds at Worker Process level.
  - The system SHALL support configurable metric name prefix (default `cribl.logstream.`).
  - The system SHALL support "Full fidelity" toggle to include/exclude disabled field metrics.
  - The system SHALL NOT require authentication or external communication.
  - In Cribl.Cloud managed environments, logs SHALL contain only Sources and Destinations-related data.
- **Auth model:** None (internal data source).
- **Protocol:** None (internal process).
