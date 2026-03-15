## ADDED Requirements

### Requirement: Schema Learning
The system SHALL learn the expected schema for each source by observing the first N events (configurable, default 1000) after a source is started. The learned schema SHALL capture field names, inferred types (string, integer, float, boolean, timestamp, nested object, array), and optional format metadata (e.g., date format patterns). Alternatively, an operator MAY define an explicit schema for a source, which SHALL take precedence over the learned schema. Learned schemas SHALL be persisted in DynamoDB keyed by source ID and reused on source restart.

#### Scenario: Schema learned from first N events
- **WHEN** a source is started with no existing persisted schema and no explicit schema defined
- **THEN** the system SHALL observe the first N events (default 1000) and build a baseline schema from the observed field names and inferred types
- **THEN** the learned schema SHALL be persisted to DynamoDB

#### Scenario: Explicit schema overrides learning
- **WHEN** a source is configured with an explicit schema definition
- **THEN** the system SHALL use the explicit schema as the baseline without observing events
- **THEN** drift detection SHALL compare events against the explicit schema

#### Scenario: Persisted schema reused on restart
- **WHEN** a source restarts and a persisted schema exists in DynamoDB for that source ID
- **THEN** the system SHALL load the persisted schema and skip the learning phase
- **THEN** drift detection SHALL be active immediately using the persisted schema

### Requirement: Schema Fingerprinting
The system SHALL compute a structural fingerprint (hash) of each event's shape, derived from the event's field names and value types. The fingerprint computation SHALL complete in sub-millisecond time per event. When an event's fingerprint matches the baseline schema's fingerprint, the system SHALL skip deep comparison. When fingerprints differ, the system SHALL perform a detailed comparison to classify the drift.

#### Scenario: Fingerprint match skips deep comparison
- **WHEN** an incoming event's structural fingerprint matches the baseline schema fingerprint
- **THEN** the system SHALL not perform a deep field-by-field comparison
- **THEN** the event SHALL proceed through the pipeline with no additional processing overhead

#### Scenario: Fingerprint mismatch triggers deep comparison
- **WHEN** an incoming event's structural fingerprint differs from the baseline schema fingerprint
- **THEN** the system SHALL perform a deep comparison to identify which fields changed and how

### Requirement: Drift Detection
The system SHALL detect the following categories of schema drift by comparing incoming events against the baseline schema: new fields (fields present in the event but not in the schema), missing fields (fields in the schema but absent from the event), type changes (a field's inferred type differs from the schema, e.g., string to number), format changes (a field's format pattern differs, e.g., date format shift), and field renames (heuristic detection when a field disappears and a similarly-named field appears). The drift detection process SHALL run as a lightweight per-source GenServer, always active for every enabled source.

#### Scenario: New field detected
- **WHEN** an incoming event contains a field not present in the baseline schema
- **THEN** the system SHALL classify this as a "new field" drift event
- **THEN** the system SHALL record the field name, inferred type, and first-seen timestamp

#### Scenario: Missing field detected
- **WHEN** an incoming event lacks a field that is present in the baseline schema
- **THEN** the system SHALL classify this as a "missing field" drift event
- **THEN** the system SHALL record the field name and first-seen timestamp

#### Scenario: Type change detected
- **WHEN** an incoming event contains a field whose inferred type differs from the baseline schema type for that field
- **THEN** the system SHALL classify this as a "type change" drift event
- **THEN** the system SHALL record the field name, old type, new type, and first-seen timestamp

#### Scenario: Format change detected
- **WHEN** an incoming event contains a field whose format pattern differs from the baseline schema format for that field (e.g., date format changed from ISO 8601 to Unix timestamp)
- **THEN** the system SHALL classify this as a "format change" drift event

#### Scenario: Field rename detected via heuristic
- **WHEN** an incoming event lacks a field from the baseline schema AND contains a new field with a similar name (based on edit distance or common rename patterns)
- **THEN** the system SHALL classify this as a possible "field rename" drift event
- **THEN** the system SHALL include both the old and new field names in the drift report

### Requirement: Drift Alerting
The system SHALL alert operators when schema drift is detected. Alerts SHALL be delivered via LiveView UI notifications (real-time push), configurable webhook (HTTP POST to a configured URL), and the system's notification framework. Each alert SHALL include the source ID, drift type, affected fields, first-seen timestamp, and the percentage of recent events matching the new shape vs the old shape. The system SHALL log drift events with timestamps and sample before/after events for comparison.

#### Scenario: LiveView drift notification
- **WHEN** schema drift is detected on a source
- **THEN** the system SHALL push a real-time notification to all connected LiveView sessions showing the source name, drift type, and affected fields

#### Scenario: Webhook drift notification
- **WHEN** schema drift is detected on a source that has a webhook URL configured
- **THEN** the system SHALL send an HTTP POST to the configured webhook URL with a JSON payload containing the source ID, drift type, affected fields, sample events, and timestamps

#### Scenario: Drift diff display
- **WHEN** an operator views a drift alert
- **THEN** the system SHALL display a diff showing what changed, when it started, and the percentage of events matching the new shape vs the old shape

#### Scenario: Drift event logging
- **WHEN** schema drift is detected
- **THEN** the system SHALL log the drift event with the source ID, drift type, timestamp, and sample before/after events
- **THEN** drift events SHALL be persisted in DynamoDB for historical review

### Requirement: Drift Telemetry
The system SHALL emit telemetry metrics for schema drift events. The following metrics SHALL be emitted: `compressr.schema.drift_detected` (counter, tagged by source_id), `compressr.schema.fields_added` (counter, tagged by source_id), `compressr.schema.fields_removed` (counter, tagged by source_id), `compressr.schema.type_changes` (counter, tagged by source_id).

#### Scenario: Telemetry emitted on drift detection
- **WHEN** schema drift is detected on a source
- **THEN** the system SHALL emit a `compressr.schema.drift_detected` telemetry counter event tagged with the source ID

#### Scenario: Telemetry emitted for specific drift types
- **WHEN** a new field is detected in a drift event
- **THEN** the system SHALL emit a `compressr.schema.fields_added` telemetry counter event
- **WHEN** a missing field is detected in a drift event
- **THEN** the system SHALL emit a `compressr.schema.fields_removed` telemetry counter event
- **WHEN** a type change is detected in a drift event
- **THEN** the system SHALL emit a `compressr.schema.type_changes` telemetry counter event

### Requirement: Operator Drift Controls
Operators SHALL be able to acknowledge drift, which accepts the new schema as the baseline and resets drift state for that source. Operators SHALL be able to suppress specific fields from drift detection so that known-volatile fields do not trigger alerts. Operators SHALL be able to configure drift sensitivity per source: `all_changes` mode alerts on any structural change, while `breaking_only` mode alerts only on missing fields and type changes (not on new fields or format changes).

#### Scenario: Acknowledge drift accepts new baseline
- **WHEN** an operator acknowledges a drift event for a source
- **THEN** the system SHALL update the baseline schema to match the new event shape
- **THEN** the system SHALL persist the updated schema to DynamoDB
- **THEN** the system SHALL reset drift state and stop alerting for the acknowledged changes

#### Scenario: Suppress field from drift detection
- **WHEN** an operator configures a field to be suppressed from drift detection on a source
- **THEN** the system SHALL exclude that field from all future drift comparisons for that source

#### Scenario: Breaking-only sensitivity mode
- **WHEN** a source is configured with `breaking_only` sensitivity
- **THEN** the system SHALL only alert on missing fields and type changes
- **THEN** the system SHALL not alert on new fields or format changes

#### Scenario: All-changes sensitivity mode
- **WHEN** a source is configured with `all_changes` sensitivity (the default)
- **THEN** the system SHALL alert on all drift types: new fields, missing fields, type changes, format changes, and field renames

### Requirement: Iceberg Destination Drift Integration
When schema drift is detected on a source that routes events to an Iceberg destination, the system SHALL generate an impact warning describing how the drift will affect the Iceberg table schema. The warning SHALL include: new columns that will be added to the table, type changes that may cause schema evolution conflicts, and any fields that will be dropped if using an explicit Iceberg schema.

#### Scenario: Drift triggers Iceberg impact warning
- **WHEN** schema drift is detected on a source whose events flow to an Iceberg destination
- **THEN** the system SHALL generate an impact warning listing the Iceberg table columns that will be added or modified
- **THEN** the impact warning SHALL be included in the drift alert notification (LiveView and webhook)

#### Scenario: Type change warns about Iceberg evolution conflict
- **WHEN** a type change drift is detected on a field that maps to an existing Iceberg table column
- **THEN** the system SHALL warn that the type change may cause a schema evolution conflict in the Iceberg table
- **THEN** the warning SHALL include the current Iceberg column type and the new inferred type

### Requirement: Schema Drift Detection Lifecycle
The schema drift detection process SHALL be started alongside every enabled source process by the source supervisor. The drift detection process SHALL restart when the source process restarts. The drift detection process SHALL stop when the source is disabled. Every event emitted by the source SHALL pass through drift detection before entering the routing layer. Drift detection SHALL not block or delay event processing beyond the sub-millisecond fingerprint comparison.

#### Scenario: Drift detection starts with source
- **WHEN** a source process is started
- **THEN** the system SHALL start a co-located drift detection GenServer for that source

#### Scenario: Drift detection stops with source
- **WHEN** a source is disabled or stopped
- **THEN** the system SHALL stop the drift detection process for that source

#### Scenario: Drift detection does not block event processing
- **WHEN** an event passes through drift detection
- **THEN** the event SHALL continue to the routing layer without waiting for drift classification to complete
- **THEN** drift classification MAY proceed asynchronously after the fingerprint check

### Requirement: Schema Drift DynamoDB Persistence
Learned schemas SHALL be stored in DynamoDB with the source ID as the partition key. Each schema record SHALL contain the schema snapshot (field specs), structural fingerprint, learning timestamp, and event count used for learning. Drift events SHALL be stored in DynamoDB with the source ID as partition key and timestamp as sort key. Each drift event record SHALL contain the drift type, affected fields, sample before/after events, and percentage of events matching old vs new shape.

#### Scenario: Schema persisted to DynamoDB
- **WHEN** a schema is learned or updated via drift acknowledgment
- **THEN** the system SHALL persist the schema snapshot to DynamoDB keyed by source ID

#### Scenario: Drift events persisted to DynamoDB
- **WHEN** a drift event is detected
- **THEN** the system SHALL persist the drift event record to DynamoDB with source ID and timestamp
- **THEN** historical drift events SHALL be queryable by source ID in chronological order
