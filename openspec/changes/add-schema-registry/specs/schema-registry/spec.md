## ADDED Requirements

### Requirement: Log Type Classification
The system SHALL automatically detect distinct log types within a source stream using structural fingerprinting as the primary classification method. Structural fingerprinting SHALL derive a log type identity from the event's field set, field naming patterns, and format markers (e.g., JSON structure, syslog header, key=value pairs). The system SHALL also support regex pattern matching (configurable per source), field presence rules (e.g., "has request_path and status_code implies HTTP access log"), and operator-defined classification rules. Classification methods SHALL be composable with configurable priority ordering. Classification of a previously seen log type SHALL complete in sub-millisecond time via fingerprint lookup.

#### Scenario: Structural fingerprinting classifies events by field set
- **WHEN** events arrive at a source with fields `remote_addr`, `request_path`, `status_code`, `bytes_sent`
- **THEN** the system SHALL compute a structural fingerprint from the field set and assign them to a log type (e.g., "http_access")
- **WHEN** subsequent events arrive with the same field set
- **THEN** the system SHALL match the fingerprint in sub-millisecond time and assign the same log type

#### Scenario: Field presence rules classify events
- **WHEN** a source is configured with a field presence rule: "has request_path AND status_code implies http_access"
- **THEN** events containing both `request_path` and `status_code` SHALL be classified as "http_access" regardless of other fields present

#### Scenario: Regex pattern matching classifies events
- **WHEN** a source is configured with a regex classification pattern mapping `^<\d+>` to "syslog"
- **THEN** events whose `_raw` field matches the pattern SHALL be classified as "syslog"

#### Scenario: Operator-defined rules override automatic classification
- **WHEN** an operator defines a classification rule for a source
- **THEN** the operator rule SHALL take precedence over automatic structural fingerprinting for matching events

#### Scenario: Multiple log types detected in single source
- **WHEN** a source stream contains events with distinctly different field sets (e.g., nginx access logs, kernel messages, sshd auth logs, cron logs)
- **THEN** the system SHALL detect each distinct type and classify events independently
- **THEN** each log type SHALL have its own identity and schema

### Requirement: Per-Type Schema Tracking
The system SHALL maintain a separate schema for each detected log type. Each schema SHALL capture field names, inferred types (string, integer, float, boolean, timestamp, nested object, array), and sample values. Schemas SHALL NOT be union schemas across log types; each log type's schema SHALL contain only the fields observed in events of that specific type. Schemas SHALL be updated incrementally as new fields are discovered in subsequent samples of the same log type.

#### Scenario: Schema inferred from classified events
- **WHEN** events are classified as a specific log type
- **THEN** the system SHALL infer a schema from the event fields, recording field names, types, and sample values
- **THEN** the schema SHALL contain only fields observed in events of that log type

#### Scenario: Schema updated when new fields appear in same log type
- **WHEN** a new field appears in events of an already-known log type
- **THEN** the system SHALL add the new field to that log type's schema
- **THEN** existing fields in the schema SHALL remain unchanged

#### Scenario: Separate schemas for different log types
- **WHEN** a source has two detected log types: "http_access" with fields `remote_addr, path, status` and "sshd_auth" with fields `user, source_ip, status, method`
- **THEN** the system SHALL maintain two independent schemas
- **THEN** each schema SHALL only contain its own log type's fields

### Requirement: Volume Tracking Per Log Type
The system SHALL track event volume per log type within each source. Volume metrics SHALL include events per second, bytes per second, and percentage of total source volume. Volume metrics SHALL be computed using sliding window counters and SHALL be available in real time via LiveView and REST API.

#### Scenario: Volume breakdown reported per source
- **WHEN** a source has multiple detected log types
- **THEN** the system SHALL report the volume breakdown as percentages (e.g., "nginx 62%, kernel 24%, sshd 11%, cron 3%")
- **THEN** the breakdown SHALL include events/sec and bytes/sec per log type

#### Scenario: Volume metrics update in real time
- **WHEN** events are flowing through a source with classified log types
- **THEN** volume counters SHALL update in real time
- **THEN** LiveView sessions displaying volume data SHALL receive live updates

### Requirement: Schema Registry DynamoDB Persistence
Log type records SHALL be stored in DynamoDB with source ID as partition key and log type ID as sort key. Each log type record SHALL contain the log type name, structural fingerprint, classification method used, first-seen timestamp, and last-seen timestamp. Per-type schemas SHALL be stored in DynamoDB with log type ID as partition key and version as sort key. Each schema record SHALL contain the full field specification, schema fingerprint, created timestamp, and event count used for inference. Volume snapshots SHALL be periodically persisted to DynamoDB for historical analysis.

#### Scenario: Log type record persisted on first detection
- **WHEN** a new log type is detected in a source stream
- **THEN** the system SHALL persist a log type record to DynamoDB with the source ID, log type ID, name, fingerprint, and first-seen timestamp

#### Scenario: Schema persisted on creation and update
- **WHEN** a schema is inferred or updated for a log type
- **THEN** the system SHALL persist the schema to DynamoDB with a new version entry
- **THEN** previous schema versions SHALL be retained for historical review

#### Scenario: Volume snapshots persisted periodically
- **WHEN** the configured snapshot interval elapses (default 1 minute)
- **THEN** the system SHALL persist current volume metrics for all active log types to DynamoDB

### Requirement: Discovery Mode
The system SHALL support a discovery mode for newly configured sources. In discovery mode, the system SHALL observe the first N events (configurable, default 10,000) by sampling every event, classify all detected log types, infer per-type schemas, and measure volume breakdown. After the learning phase, the system SHALL generate a discovery report listing all detected log types with their schemas and volume percentages. After the initial learning phase, the system SHALL transition to steady-state sampling (configurable ratio, default 1:100) for ongoing classification of new events.

#### Scenario: Discovery mode activates for new source
- **WHEN** a new source is configured and started
- **THEN** the system SHALL enter discovery mode and sample every event for the first N events (default 10,000)
- **THEN** the system SHALL classify log types, infer schemas, and measure volume during this phase

#### Scenario: Discovery report generated after learning phase
- **WHEN** the learning phase completes (N events observed)
- **THEN** the system SHALL generate a discovery report listing detected log types, their schemas, and volume breakdown
- **THEN** the report SHALL be available via LiveView UI and REST API

#### Scenario: Transition to steady-state sampling
- **WHEN** the learning phase completes
- **THEN** the system SHALL reduce sampling to the configured ratio (default 1:100)
- **THEN** the system SHALL continue to detect new log types from sampled events

### Requirement: New Log Type Detection
The system SHALL detect when a previously unseen log type appears in a source stream after the initial learning phase. Upon detection, the system SHALL alert the operator via LiveView real-time notification, configurable webhook (HTTP POST), and the system's notification framework. The alert SHALL include the source ID, new log type name, event count observed, time window, and a schema preview of the new type.

#### Scenario: New log type detected after learning phase
- **WHEN** events with a previously unseen structural fingerprint appear in a source after the learning phase has completed
- **THEN** the system SHALL classify this as a new log type
- **THEN** the system SHALL infer a schema from the new events

#### Scenario: LiveView notification for new log type
- **WHEN** a new log type is detected
- **THEN** the system SHALL push a real-time notification to all connected LiveView sessions
- **THEN** the notification SHALL include the source name, new log type name, event count, and schema preview

#### Scenario: Webhook notification for new log type
- **WHEN** a new log type is detected on a source with a webhook URL configured
- **THEN** the system SHALL send an HTTP POST to the configured webhook URL with a JSON payload containing the source ID, new log type name, event count, time window, and schema preview

### Requirement: Iceberg Destination Table-Per-Type Routing
When a source with classified log types flows to an Iceberg destination, the schema registry SHALL enable automatic table-per-type routing. Each detected log type SHALL be routed to its own Iceberg table with a schema derived from the log type's per-type schema. This SHALL produce tight, type-specific Iceberg tables instead of a single sparse union table. New Iceberg tables SHALL be created automatically when new log types are detected. Table naming SHALL follow a configurable convention (default: `{source_name}_{log_type_name}`).

#### Scenario: Each log type routed to its own Iceberg table
- **WHEN** a source with 4 detected log types (nginx, kernel, sshd, cron) flows to an Iceberg destination
- **THEN** the system SHALL create 4 separate Iceberg tables, each with a schema matching only its log type's fields
- **THEN** events SHALL be routed to the corresponding table based on their classified log type

#### Scenario: New Iceberg table created for new log type
- **WHEN** a new log type is detected in a source that flows to an Iceberg destination
- **THEN** the system SHALL automatically create a new Iceberg table for the new log type
- **THEN** the new table SHALL be registered in AWS Glue Catalog

#### Scenario: Tight schema improves Parquet compression
- **WHEN** events are written to a type-specific Iceberg table
- **THEN** the Parquet files SHALL contain only columns relevant to that log type
- **THEN** column cardinality and type consistency SHALL be higher than a union table, improving compression ratios

### Requirement: Schema Drift Detection Integration
Schema drift detection SHALL operate per log type, not per source. When drift is detected in a specific log type, the drift alert SHALL identify which log type experienced the drift. A schema change in one log type (e.g., new field in nginx logs) SHALL NOT trigger drift alerts for other log types in the same source (e.g., sshd logs).

#### Scenario: Drift detected per log type not per source
- **WHEN** nginx access log events in source "prod-syslog" gain a new field `upstream_response_time`
- **THEN** the system SHALL report a drift event for the "nginx_access" log type only
- **THEN** the system SHALL NOT report drift for "kernel", "sshd", or "cron" log types in the same source

#### Scenario: Drift alert includes log type context
- **WHEN** schema drift is detected in a log type
- **THEN** the drift alert SHALL include the log type name and ID in addition to the source ID and field details

### Requirement: Query Assistance
The schema registry SHALL support field-level search across all log types and sources. Given a field name or partial field name, the system SHALL return which log types contain that field, along with the field's type and sample values. This enables operators to locate where specific data lives across their sources.

#### Scenario: Search for field across log types
- **WHEN** an operator searches for the field "status" across the schema registry
- **THEN** the system SHALL return all log types containing a "status" field
- **THEN** each result SHALL include the source name, log type name, field type, and sample values

#### Scenario: Query assistance identifies table for analysis
- **WHEN** an operator asks "where are auth failures?"
- **THEN** the system SHALL search for fields related to authentication (e.g., "auth", "status", "login")
- **THEN** the results SHALL indicate which log types and Iceberg tables contain relevant fields

### Requirement: Schema Registry REST API
The system SHALL expose REST API endpoints for the schema registry. All endpoints SHALL require OIDC authentication. Endpoints SHALL include: list log types per source, get schema for a log type, get volume breakdown per source, get volume breakdown per log type, search fields across all log types, and get discovery report for a source.

#### Scenario: List log types for a source
- **WHEN** an authenticated user sends a GET request to `/api/sources/:source_id/log-types`
- **THEN** the system SHALL return a list of all detected log types for that source with names, fingerprints, event counts, and volume percentages

#### Scenario: Get schema for a log type
- **WHEN** an authenticated user sends a GET request to `/api/sources/:source_id/log-types/:type_id/schema`
- **THEN** the system SHALL return the full schema for that log type including field names, types, and sample values

#### Scenario: Get volume breakdown for a source
- **WHEN** an authenticated user sends a GET request to `/api/sources/:source_id/volume-breakdown`
- **THEN** the system SHALL return volume metrics for all log types in that source including events/sec, bytes/sec, and percentage breakdown

#### Scenario: Search fields across schema registry
- **WHEN** an authenticated user sends a GET request to `/api/schema-registry/search?field=:field_name`
- **THEN** the system SHALL return all log types containing the specified field with source context, field type, and sample values

#### Scenario: Unauthenticated request rejected
- **WHEN** a request to any schema registry API endpoint lacks a valid OIDC session or token
- **THEN** the system SHALL respond with HTTP 401

### Requirement: Schema Registry LiveView UI
The system SHALL provide a LiveView-based schema browser UI. The UI SHALL display a hierarchical view of sources, their detected log types, and per-type schemas. The UI SHALL include volume breakdown charts showing percentage per log type within each source. The UI SHALL display sample events for each log type. The UI SHALL provide a field search interface to find which log types contain a specific field. The UI SHALL display real-time notifications when new log types are detected.

#### Scenario: Browse sources and log types
- **WHEN** an operator navigates to the schema browser page
- **THEN** they SHALL see a list of all sources with the number of detected log types per source
- **WHEN** the operator selects a source
- **THEN** they SHALL see all detected log types with volume percentages

#### Scenario: View log type schema details
- **WHEN** an operator selects a log type in the schema browser
- **THEN** they SHALL see the full schema: field names, inferred types, and sample values
- **THEN** the view SHALL include the log type's first-seen and last-seen timestamps

#### Scenario: View volume breakdown chart
- **WHEN** an operator views a source in the schema browser
- **THEN** they SHALL see a chart showing the volume breakdown by log type (percentage, events/sec, bytes/sec)
- **THEN** the chart SHALL update in real time as events flow

#### Scenario: View sample events per log type
- **WHEN** an operator selects a log type and requests sample events
- **THEN** the system SHALL display recent sample events of that log type

#### Scenario: Search fields across schema browser
- **WHEN** an operator enters a field name in the schema browser search bar
- **THEN** the system SHALL display all log types containing that field across all sources

#### Scenario: New log type notification in UI
- **WHEN** a new log type is detected in any source
- **THEN** the schema browser SHALL display a notification banner with the source name, new log type name, and event count

### Requirement: Schema Registry Telemetry
The system SHALL emit telemetry metrics for schema registry operations. The following metrics SHALL be emitted: `compressr.schema_registry.log_type_detected` (counter, tagged by source_id), `compressr.schema_registry.classification_time` (histogram, tagged by source_id), `compressr.schema_registry.new_type_discovered` (counter, tagged by source_id), `compressr.schema_registry.events_classified` (counter, tagged by source_id and log_type_id).

#### Scenario: Telemetry emitted on log type detection
- **WHEN** a log type is first detected in a source
- **THEN** the system SHALL emit a `compressr.schema_registry.log_type_detected` telemetry counter event tagged with the source ID

#### Scenario: Telemetry emitted for classification performance
- **WHEN** events are classified by the classification engine
- **THEN** the system SHALL emit a `compressr.schema_registry.classification_time` telemetry histogram event measuring the classification duration

#### Scenario: Telemetry emitted for new type discovery
- **WHEN** a new log type is discovered after the initial learning phase
- **THEN** the system SHALL emit a `compressr.schema_registry.new_type_discovered` telemetry counter event tagged with the source ID

### Requirement: Classification Performance
The classification engine SHALL NOT process every event in steady state. After the initial learning phase (configurable, default 10,000 events sampled at 100%), the system SHALL sample events at a configurable ratio (default 1:100) for ongoing classification. Events that match a known fingerprint SHALL be classified via fingerprint lookup without deep inspection. The classification stage SHALL NOT block or delay event processing; events SHALL proceed to routing immediately after fingerprint tagging, with any new-type analysis happening asynchronously.

#### Scenario: Sampling reduces classification overhead
- **WHEN** a source has completed the learning phase
- **THEN** only 1 in every 100 events (default) SHALL be fully classified
- **THEN** the remaining events SHALL be tagged with their log type via fingerprint lookup only

#### Scenario: Classification does not block event processing
- **WHEN** an event passes through the classification stage
- **THEN** the event SHALL be tagged with its log type and proceed to routing immediately
- **THEN** any new-type analysis or schema inference SHALL happen asynchronously

#### Scenario: Configurable sampling ratio
- **WHEN** an operator configures a sampling ratio of 1:50 for a source
- **THEN** the system SHALL sample 1 in every 50 events for full classification after the learning phase
