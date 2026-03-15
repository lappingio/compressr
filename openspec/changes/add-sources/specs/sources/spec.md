## ADDED Requirements

### Requirement: Source Behaviour
The system SHALL define a common `Compressr.Source` behaviour that all source types implement. Each source SHALL have an ID, a type, a name, a configuration map, an enabled/disabled toggle, and an optional pre-processing pipeline reference. Sources SHALL emit `Compressr.Event` structs into the routing layer.

#### Scenario: Source emits events
- **WHEN** a source receives or retrieves data
- **THEN** it produces one or more `Compressr.Event` structs with `_raw` populated and `__inputId` set to the source ID
- **THEN** the events are handed to the routing layer for further processing

#### Scenario: Disabled source does not run
- **WHEN** a source is configured but its enabled toggle is set to false
- **THEN** the source process is not started and no events are emitted

#### Scenario: Source with pre-processing pipeline
- **WHEN** a source has a pre-processing pipeline configured
- **THEN** events pass through that pipeline before entering the routing layer

### Requirement: Source Configuration Persistence
Source configurations SHALL be stored in DynamoDB. Each configuration record SHALL contain the source ID, type, name, type-specific configuration, enabled flag, and optional pre-processing pipeline ID.

#### Scenario: Source config persisted to DynamoDB
- **WHEN** a source is created via the API
- **THEN** its configuration is stored in DynamoDB and the source process is started if enabled

#### Scenario: Source config updated
- **WHEN** a source configuration is updated
- **THEN** the running source process is restarted with the new configuration

### Requirement: Source Lifecycle Management
The system SHALL manage source processes via an OTP supervisor. Sources SHALL be started on node boot based on their persisted enabled state. Sources SHALL be stoppable, restartable, and report their current status (running, stopped, error).

#### Scenario: Sources start on boot
- **WHEN** a compressr node starts
- **THEN** all enabled source configurations are loaded from DynamoDB and their processes are started

#### Scenario: Source process crashes and restarts
- **WHEN** a source process crashes
- **THEN** the supervisor restarts it according to its restart strategy

### Requirement: Syslog Source
The system SHALL provide a Syslog source type that listens for syslog messages over UDP and TCP. The source SHALL support configurable bind address and port. TCP listeners SHALL optionally support TLS. The source SHALL parse both RFC 5424 and RFC 3164 syslog message formats.

#### Scenario: Receive syslog over UDP
- **WHEN** a syslog message is sent to the configured UDP port
- **THEN** the source parses the message and emits an event with `_raw` set to the message body and structured fields extracted from the syslog header

#### Scenario: Receive syslog over TCP
- **WHEN** a syslog message is sent over a TCP connection to the configured port
- **THEN** the source applies the configured event breaking method (newline-delimited or octet-counting) and emits an event per message

#### Scenario: Syslog with TLS on TCP
- **WHEN** TLS is enabled on a TCP syslog source
- **THEN** the source requires a valid TLS handshake before accepting data

#### Scenario: Syslog source is unauthenticated
- **WHEN** a syslog message arrives on the configured port
- **THEN** it is accepted without any data plane authentication

### Requirement: HTTP and Splunk HEC Source
The system SHALL provide an HTTP source type that exposes Splunk HEC-compatible endpoints. The source SHALL listen on a configurable address and port with optional TLS. The source SHALL implement `/services/collector/event` (JSON), `/services/collector/raw` (raw text), and `/services/collector/health` endpoints.

#### Scenario: Ingest event via HEC JSON endpoint
- **WHEN** a POST request with a valid HEC token is sent to `/services/collector/event` with a JSON payload
- **THEN** the source parses the JSON and emits one event per object in the payload

#### Scenario: Ingest event via HEC raw endpoint
- **WHEN** a POST request with a valid HEC token is sent to `/services/collector/raw` with raw text
- **THEN** the source emits one event per line of the text payload

#### Scenario: HEC health check
- **WHEN** a GET request is sent to `/services/collector/health`
- **THEN** the source responds with HTTP 200 and a health status body

#### Scenario: Invalid HEC token rejected
- **WHEN** a request is sent to a HEC endpoint with an invalid or missing token
- **THEN** the source responds with HTTP 401 and does not emit any events

### Requirement: Per-Source Data Plane Authentication
Data plane authentication SHALL be configured per source. HTTP/HEC sources SHALL require a bearer token (HEC token) configured on the source. Syslog sources SHALL operate without data plane authentication. Control plane authentication (source configuration CRUD) is handled separately by OIDC.

#### Scenario: HEC token validates against source config
- **WHEN** an HTTP request includes a bearer token matching the source's configured HEC token
- **THEN** the request is authenticated and events are accepted

#### Scenario: Syslog requires no data plane auth
- **WHEN** data arrives at a syslog source
- **THEN** it is accepted regardless of sender identity

### Requirement: Source Configuration API
The system SHALL expose REST API endpoints for source CRUD operations (create, read, update, delete, list). All source configuration endpoints SHALL require OIDC authentication. The API SHALL validate type-specific configuration before saving. The API SHALL expose source status (running, stopped, error, event counters).

#### Scenario: Create a source via API
- **WHEN** an authenticated admin sends a POST request with valid source configuration
- **THEN** the source is created, persisted to DynamoDB, and started if enabled

#### Scenario: Unauthenticated source CRUD is rejected
- **WHEN** a request to a source configuration endpoint lacks a valid OIDC session or token
- **THEN** the system responds with HTTP 401

#### Scenario: Invalid source config rejected on create
- **WHEN** a create request contains invalid type-specific configuration (e.g., missing port for syslog)
- **THEN** the system responds with HTTP 422 and a validation error

#### Scenario: List sources with status
- **WHEN** an authenticated user sends a GET request to the source list endpoint
- **THEN** the system returns all configured sources with their current status and event counters

### Requirement: S3 Collector Source
The system SHALL provide an S3 source type that operates as a pull-based collector. The source SHALL list objects in a configured S3 bucket with optional prefix and suffix filters. The source SHALL support ad hoc and scheduled collection runs. The source SHALL track collection state in DynamoDB to avoid re-processing objects.

#### Scenario: Scheduled S3 collection
- **WHEN** a scheduled collection interval elapses
- **THEN** the source lists new objects in the configured bucket, retrieves them, and emits events

#### Scenario: Ad hoc S3 collection
- **WHEN** an administrator triggers an ad hoc collection run via API
- **THEN** the source immediately lists and processes objects matching the configured filters

#### Scenario: Already-collected objects are skipped
- **WHEN** the source lists objects in S3 during a collection run
- **THEN** objects that have already been collected (tracked in DynamoDB) are skipped

#### Scenario: S3 object decompression
- **WHEN** a collected S3 object is gzip-compressed
- **THEN** the source decompresses it before emitting events

### Requirement: S3 Glacier Tiered-Storage Rehydration
The system SHALL support ingesting objects stored in S3 Glacier tiers (Instant Retrieval, Flexible Retrieval, Deep Archive). The source SHALL use the object storage tiered retrieval behaviour to initiate restore, poll for availability, and replay objects when they become accessible. The system SHALL manage the full Glacier restore lifecycle automatically. Before initiating any non-instant Glacier restore, the system SHALL present a dynamic cost estimate showing all available retrieval tiers with their cost, time, and per-GB rate, and require operator confirmation. The tier selection SHALL be made at replay time, not pre-configured — the operator picks the speed/cost tradeoff for each replay job.

#### Scenario: Operator-initiated replay presents tier and mode options
- **WHEN** an operator requests a replay of data stored in Glacier Flexible Retrieval or Deep Archive
- **THEN** the system SHALL calculate the total data size (object count and bytes) for the requested time range
- **THEN** the system SHALL present a tier selection showing all available options with estimated cost, estimated retrieval time, and per-GB rate (e.g., Bulk $2.12 / 5-12 hrs, Standard $8.47 / 3-5 hrs, Expedited $84.70 / 1-5 min)
- **THEN** the system SHALL present a replay mode selection: as-available or ordered
- **THEN** the system SHALL wait for the operator to select tier, mode, and confirm before initiating restores

#### Scenario: API-initiated replay accepts tier and mode parameters
- **WHEN** a replay is initiated via the REST API
- **THEN** the request SHALL include a `retrieval_tier` parameter (bulk, standard, expedited) and a `replay_mode` parameter (as_available, ordered)
- **THEN** the API response SHALL include the estimated cost and estimated retrieval time before the restore begins
- **WHEN** no `retrieval_tier` is specified, the system SHALL default to `bulk` (lowest cost)
- **WHEN** no `replay_mode` is specified, the system SHALL default to `as_available`

### Requirement: As-Available Replay Mode
In as-available mode, the system SHALL process each restored object as soon as it becomes available, regardless of chronological order. The system SHALL configure an S3 Event Notification via EventBridge to listen for `s3:ObjectRestore:Completed` events for the target bucket and prefix. EventBridge SHALL deliver notifications to an SQS queue. The replay process SHALL consume from the SQS queue and immediately process each restored object. This mode minimizes time-to-first-data — the operator starts seeing events minutes after the first object thaws, rather than waiting hours for all objects to restore.

#### Scenario: EventBridge notification triggers immediate processing
- **WHEN** S3 completes restoring an object from Glacier
- **THEN** S3 fires an `s3:ObjectRestore:Completed` event to EventBridge
- **THEN** EventBridge delivers the event to the replay job's SQS queue
- **THEN** the replay process picks up the message and processes the object immediately

#### Scenario: Multiple objects thaw at different times
- **WHEN** a replay job has initiated restores for 1,000 objects
- **THEN** objects thaw over a window (e.g., 5-12 hours for Bulk)
- **THEN** each object is processed as soon as its EventBridge notification arrives
- **THEN** events arrive at the destination out of chronological order

#### Scenario: EventBridge and SQS cleanup after replay
- **WHEN** all objects in the replay job have been processed
- **THEN** the system SHALL remove the EventBridge rule and SQS queue created for that replay job

### Requirement: Ordered Replay Mode
In ordered mode, the system SHALL build a manifest of all objects in the requested time range, sorted chronologically. The system SHALL walk the manifest in sequence, processing one object at a time. If the next object in sequence is not yet restored, the system SHALL poll that specific object's restore status at a configurable interval until it becomes available. No EventBridge or SQS is needed — the system knows exactly which object it needs next and waits for it. This mode guarantees chronological event ordering at the cost of higher time-to-first-data.

#### Scenario: Objects processed in chronological order
- **WHEN** a replay job is initiated in ordered mode
- **THEN** the system SHALL build a sorted manifest of all objects in the time range
- **THEN** the system SHALL process objects strictly in manifest order

#### Scenario: System waits for next object in sequence
- **WHEN** the next object in the manifest is not yet restored
- **THEN** the system SHALL poll that object's restore status at a configurable interval (default 60 seconds)
- **THEN** the system SHALL NOT skip ahead to a later object that may already be available

#### Scenario: Ordered replay progresses as objects thaw
- **WHEN** objects thaw out of manifest order (e.g., object 5 thaws before object 3)
- **THEN** the system SHALL wait for object 3 before processing
- **THEN** once object 3 is processed, objects 4 and 5 (already available) SHALL be processed immediately without polling

#### Scenario: Object in Glacier Instant Retrieval
- **WHEN** a collection run encounters an object in S3 Glacier Instant Retrieval
- **THEN** the source retrieves it synchronously (no async restore needed, no cost confirmation required) and emits events

#### Scenario: Actual cost tracked after replay completes
- **WHEN** a replay job completes (all objects processed)
- **THEN** the system SHALL record the actual bytes restored, the tier used, the replay mode, the wall-clock duration, and the actual cost
- **THEN** the actual cost SHALL be compared to the pre-action estimate and made available in the cost dashboard

### Requirement: Source Management UI
The system SHALL provide a LiveView-based UI for managing sources. Administrators SHALL be able to view all sources with real-time status, create new sources with type-specific configuration forms, edit existing sources, enable/disable sources, and delete sources.

#### Scenario: View source list with live status
- **WHEN** an administrator navigates to the source management page
- **THEN** they see all configured sources with real-time status indicators (running, stopped, error)

#### Scenario: Create source via UI
- **WHEN** an administrator selects a source type and fills in the configuration form
- **THEN** the source is created and appears in the list with its current status

#### Scenario: Enable/disable source via UI
- **WHEN** an administrator toggles a source's enabled state in the UI
- **THEN** the source process is started or stopped accordingly and the status updates in real time
