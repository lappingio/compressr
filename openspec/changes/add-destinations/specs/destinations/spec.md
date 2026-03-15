## ADDED Requirements

### Requirement: Destination Behaviour Interface
The system SHALL define a `Compressr.Destination` Elixir behaviour that all destination types MUST implement. The behaviour SHALL define callbacks for initialization, event writing, flushing buffered data, stopping gracefully, and reporting health status.

#### Scenario: Destination module implements behaviour
- **WHEN** a new destination type is created
- **THEN** it MUST implement all callbacks defined by `Compressr.Destination`: `init/1`, `write/2`, `flush/1`, `stop/1`, `healthy?/1`

#### Scenario: Destination initialization
- **WHEN** a destination process starts with a valid configuration map
- **THEN** the `init/1` callback SHALL return `{:ok, state}` with internal state for the destination
- **THEN** the destination SHALL be registered in the destination registry

#### Scenario: Destination graceful stop
- **WHEN** `stop/1` is called on a running destination
- **THEN** the destination SHALL flush any buffered data before terminating
- **THEN** the destination SHALL deregister from the destination registry

### Requirement: Destination Configuration Resource
The system SHALL model destination configuration as an Ash resource persisted in DynamoDB. Each destination configuration SHALL include: a unique ID, a type (s3, elasticsearch, splunk_hec, devnull), a configuration map, an enabled/disabled flag, a backpressure mode, an optional post-processing pipeline ID, batch settings, and format settings.

#### Scenario: Create destination configuration
- **WHEN** a user creates a destination with a unique ID, valid type, and required configuration
- **THEN** the configuration SHALL be persisted to DynamoDB
- **THEN** the destination SHALL appear in the destination list

#### Scenario: Update destination configuration
- **WHEN** a user modifies a destination's configuration
- **THEN** the running destination process SHALL be restarted with the new configuration

#### Scenario: Delete destination configuration
- **WHEN** a user deletes a destination
- **THEN** the destination process SHALL be stopped gracefully
- **THEN** the configuration SHALL be removed from DynamoDB

### Requirement: Destination Enabled/Disabled Toggle
The system SHALL support enabling and disabling individual destinations. A disabled destination SHALL NOT accept or process events. Disabling a destination SHALL trigger a graceful drain of any buffered data before the destination stops processing.

#### Scenario: Disable a running destination
- **WHEN** a user disables an enabled destination
- **THEN** the destination SHALL flush all buffered data
- **THEN** the destination SHALL stop accepting new events
- **THEN** the destination health status SHALL report as disabled

#### Scenario: Enable a disabled destination
- **WHEN** a user enables a disabled destination
- **THEN** the destination process SHALL start and begin accepting events
- **THEN** the destination health status SHALL report as healthy once ready

### Requirement: Backpressure Configuration
The system SHALL support three backpressure modes per destination: **block** (refuse new events, applying back-pressure upstream), **drop** (discard events when the destination cannot keep up), and **queue** (buffer events to a persistent queue). The queue mode SHALL be accepted in configuration but SHALL NOT be functional until the persistent queuing subsystem is implemented (deferred dependency).

#### Scenario: Block mode under backpressure
- **WHEN** a destination configured with block mode cannot accept events fast enough
- **THEN** the system SHALL apply back-pressure to upstream pipeline stages, refusing new events until the destination is ready

#### Scenario: Drop mode under backpressure
- **WHEN** a destination configured with drop mode cannot accept events fast enough
- **THEN** the system SHALL discard events that exceed the destination's capacity
- **THEN** the system SHALL emit a metric counting dropped events

#### Scenario: Queue mode configured before implementation
- **WHEN** a destination is configured with queue backpressure mode
- **THEN** the system SHALL accept the configuration
- **THEN** the system SHALL log a warning that persistent queuing is not yet implemented and fall back to block mode

### Requirement: Batching and Format Configuration
The system SHALL support configurable batching and output format per destination. Batch settings SHALL include: maximum batch size (number of events), maximum batch bytes, and flush interval. Format settings SHALL include output format selection (JSON or Raw).

#### Scenario: Batch flush by event count
- **WHEN** the number of buffered events reaches the configured maximum batch size
- **THEN** the destination SHALL flush the batch to the downstream system

#### Scenario: Batch flush by interval
- **WHEN** the configured flush interval elapses with buffered events
- **THEN** the destination SHALL flush the batch regardless of batch size

#### Scenario: Batch flush by byte size
- **WHEN** the total byte size of buffered events reaches the configured maximum batch bytes
- **THEN** the destination SHALL flush the batch to the downstream system

### Requirement: Post-Processing Pipeline
The system SHALL support an optional post-processing pipeline reference per destination. When configured, events SHALL pass through the referenced pipeline before being written to the destination. If no post-processing pipeline is configured, events SHALL be written directly.

#### Scenario: Destination with post-processing pipeline
- **WHEN** events are routed to a destination that has a post-processing pipeline configured
- **THEN** the events SHALL be processed by the referenced pipeline before delivery to the destination

#### Scenario: Destination without post-processing pipeline
- **WHEN** events are routed to a destination with no post-processing pipeline
- **THEN** the events SHALL be written directly to the destination without additional processing

### Requirement: Destination Health Reporting
The system SHALL report health status for each destination. Health statuses SHALL include: healthy (operating normally), unhealthy (experiencing errors or connectivity issues), and disabled (administratively turned off).

#### Scenario: Healthy destination
- **WHEN** a destination is enabled and successfully delivering events
- **THEN** the health status SHALL report as healthy

#### Scenario: Unhealthy destination
- **WHEN** a destination encounters repeated delivery failures or connectivity errors
- **THEN** the health status SHALL report as unhealthy

#### Scenario: Disabled destination health
- **WHEN** a destination is administratively disabled
- **THEN** the health status SHALL report as disabled

### Requirement: S3 Destination
The system SHALL provide an S3 destination that stages files locally, compresses them, and uploads to Amazon S3 or S3-compatible stores. The S3 destination SHALL use the object storage behaviour defined in the project architecture. The S3 destination SHALL support configurable partitioning (default: date-based path structure), S3 storage class selection (Standard, Intelligent-Tiering, Glacier Instant Retrieval, Glacier Flexible Retrieval, Glacier Deep Archive), output formats (JSON, Raw), compression (gzip), and file close conditions (size limit, time limit, idle timeout).

#### Scenario: S3 upload with default partitioning
- **WHEN** events are written to an S3 destination with default configuration
- **THEN** files SHALL be staged locally, compressed with gzip, and uploaded to S3
- **THEN** files SHALL be partitioned using a date-based path structure

#### Scenario: S3 storage class selection
- **WHEN** an S3 destination is configured with a specific storage class
- **THEN** uploaded objects SHALL use the configured S3 storage class

#### Scenario: S3 file close on size limit
- **WHEN** a staged file reaches the configured size limit
- **THEN** the file SHALL be closed, compressed, and uploaded to S3

#### Scenario: S3 file close on time limit
- **WHEN** a staged file has been open for the configured maximum time
- **THEN** the file SHALL be closed, compressed, and uploaded to S3 regardless of size

### Requirement: Elasticsearch Destination
The system SHALL provide an Elasticsearch destination that sends events via the Elasticsearch Bulk API. The destination SHALL support configurable index name with per-event override via an `__index` field, authentication (none, basic username/password, API key), field normalization (`_time` to `@timestamp`, `host` to `host.name`), gzip payload compression, and HTTP retry with exponential backoff.

#### Scenario: Elasticsearch bulk indexing
- **WHEN** events are flushed to the Elasticsearch destination
- **THEN** the events SHALL be sent as a Bulk API request to the configured Elasticsearch endpoint

#### Scenario: Elasticsearch per-event index override
- **WHEN** an event contains an `__index` field
- **THEN** the event SHALL be indexed into the index specified by `__index` instead of the default index

#### Scenario: Elasticsearch field normalization
- **WHEN** events are written to the Elasticsearch destination
- **THEN** the `_time` field SHALL be normalized to `@timestamp`
- **THEN** the `host` field SHALL be normalized to `host.name`

#### Scenario: Elasticsearch retry on failure
- **WHEN** an Elasticsearch Bulk API request fails with a retryable error
- **THEN** the system SHALL retry with exponential backoff

### Requirement: Splunk HEC Destination
The system SHALL provide a Splunk HEC destination that sends events to the Splunk HTTP Event Collector `/services/collector/event` endpoint. The destination SHALL support HEC auth token configuration, configurable body size limit (default 4096 KB), configurable flush period (default 1 second), gzip payload compression, and HTTP retry with exponential backoff. The destination SHALL use the `_raw` field for log events when present; otherwise it SHALL serialize the full event as JSON.

#### Scenario: Splunk HEC event delivery
- **WHEN** events are flushed to the Splunk HEC destination
- **THEN** the events SHALL be sent as a POST request to `/services/collector/event` with the configured HEC auth token

#### Scenario: Splunk HEC raw field usage
- **WHEN** an event contains a `_raw` field
- **THEN** the Splunk HEC payload SHALL use the `_raw` field value as the event data

#### Scenario: Splunk HEC full event serialization
- **WHEN** an event does not contain a `_raw` field
- **THEN** the Splunk HEC payload SHALL serialize the entire event as JSON

#### Scenario: Splunk HEC retry on failure
- **WHEN** a Splunk HEC request fails with a retryable HTTP status
- **THEN** the system SHALL retry with exponential backoff

### Requirement: DevNull Destination
The system SHALL provide a DevNull destination that discards all received events without processing or forwarding. The DevNull destination SHALL require no configuration and SHALL be pre-configured upon system installation.

#### Scenario: DevNull discards events
- **WHEN** events are written to the DevNull destination
- **THEN** the events SHALL be discarded immediately
- **THEN** no data SHALL be transmitted or stored

#### Scenario: DevNull pre-configured on install
- **WHEN** the system is installed
- **THEN** a DevNull destination SHALL exist with no user configuration required

### Requirement: Destination REST API
The system SHALL provide REST API endpoints for destination management: list all destinations, get a single destination by ID, create a destination, update a destination, and delete a destination. API paths SHALL mirror Cribl Stream's destination API paths where practical.

#### Scenario: List destinations via API
- **WHEN** a GET request is made to the destinations list endpoint
- **THEN** the system SHALL return all configured destinations with their current health status

#### Scenario: Create destination via API
- **WHEN** a POST request is made with valid destination configuration
- **THEN** the system SHALL create the destination, persist the configuration, and start the destination process

#### Scenario: Delete destination via API
- **WHEN** a DELETE request is made for a destination ID
- **THEN** the system SHALL stop the destination process gracefully and remove the configuration
