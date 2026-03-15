## ADDED Requirements

### Requirement: Core Event Structure
The system SHALL represent events as Elixir maps containing key-value pairs. Every event MUST contain the `_raw` field (original data) and the `_time` field (Unix epoch timestamp). Additional user-defined fields MAY be added dynamically.

#### Scenario: Event created from raw string data
- **WHEN** raw string data arrives from a source
- **THEN** the system creates an event map with `_raw` set to the original string and `_time` set to the current Unix epoch timestamp

#### Scenario: Event created from structured JSON data
- **WHEN** JSON-parseable data arrives from a source
- **THEN** the system creates an event map with parsed fields as top-level keys, `_raw` set to the original JSON string, and `_time` set to the current Unix epoch timestamp

#### Scenario: Event created with explicit timestamp
- **WHEN** data arrives with an extracted or explicit timestamp
- **THEN** the system creates an event map with `_time` set to the provided timestamp value instead of the current time

### Requirement: Internal Fields
The system SHALL use the `__` (double underscore) prefix for internal fields. Internal fields are metadata used for pipeline processing and MUST NOT be serialized to external destinations. Internal fields SHALL be treated as read-only by user-facing functions.

#### Scenario: Internal fields assigned during ingestion
- **WHEN** a source ingests an event
- **THEN** the system assigns internal fields such as `__input_id` (source identifier) with the `__` prefix

#### Scenario: Internal fields excluded from external serialization
- **WHEN** an event is serialized for delivery to an external destination
- **THEN** all fields with the `__` prefix are stripped from the output

#### Scenario: Internal fields preserved for internal destinations
- **WHEN** an event is serialized for delivery to a compressr internal destination (e.g., replay storage)
- **THEN** all fields including `__` prefixed internal fields are preserved in the output

### Requirement: System Fields
The system SHALL use the `compressr_` prefix for system fields. System fields are automatically added during post-processing and SHALL be treated as read-only. Removing system fields during pipeline processing SHALL have no effect, as they are re-added after pipeline execution.

#### Scenario: System fields added during post-processing
- **WHEN** an event completes pipeline processing and enters post-processing
- **THEN** the system adds `compressr_pipe` (pipeline name), `compressr_input` (source identifier), `compressr_output` (destination identifier), and `compressr_host` (processing node) fields

#### Scenario: System fields survive pipeline removal attempts
- **WHEN** a pipeline function removes a `compressr_` prefixed field
- **THEN** the field is re-added during post-processing because system fields are applied after pipeline execution

### Requirement: Field Access and Modification
The system SHALL support reading and writing arbitrary user-defined fields on events. The system SHALL enforce that internal fields (`__` prefix) cannot be modified by user-facing pipeline functions. System fields (`compressr_` prefix) SHALL be read-only within pipelines.

#### Scenario: Adding a user-defined field
- **WHEN** a pipeline function (e.g., eval) assigns a value to a new field name without a reserved prefix
- **THEN** the field is added to the event map and available to subsequent functions

#### Scenario: Modifying an existing user-defined field
- **WHEN** a pipeline function assigns a new value to an existing user-defined field
- **THEN** the field value is updated in the event map

#### Scenario: Attempting to modify an internal field
- **WHEN** a user-facing pipeline function attempts to write to a field with the `__` prefix
- **THEN** the write operation is rejected and the internal field retains its original value

### Requirement: Event Serialization
The system SHALL support serializing events to external formats. External serialization MUST exclude internal fields (`__` prefix) and MUST include system fields (`compressr_` prefix) and all user-defined fields. The system SHALL support JSON as the default serialization format.

#### Scenario: JSON serialization of an event
- **WHEN** an event is serialized to JSON for an external destination
- **THEN** the output contains `_raw`, `_time`, all user-defined fields, and all `compressr_` system fields, but excludes all `__` prefixed internal fields

#### Scenario: Serialization preserves field types
- **WHEN** an event containing string, numeric, boolean, and nested map fields is serialized
- **THEN** field types are preserved in the serialized output
