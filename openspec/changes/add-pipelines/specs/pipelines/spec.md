## ADDED Requirements

### Requirement: Pipeline Execution
The system SHALL execute functions within a pipeline sequentially, in top-to-bottom order as defined in the pipeline configuration. Each event entering a pipeline MUST pass through every function in sequence unless a function's filter excludes the event or a function's Final toggle stops downstream processing.

#### Scenario: Sequential function execution
- **WHEN** an event enters a pipeline containing functions A, B, and C in that order
- **THEN** the system executes function A first, then B, then C on the event

#### Scenario: Event passes through all functions
- **WHEN** an event enters a pipeline with three functions and matches all filter expressions
- **THEN** the event is processed by all three functions in order and exits the pipeline

### Requirement: Pipeline Attachment Points
The system SHALL support three pipeline attachment points: pre-processing pipelines attached to sources, processing pipelines attached to routes, and post-processing pipelines attached to destinations. Pre-processing pipelines normalize events before routing, processing pipelines transform events during routing, and post-processing pipelines prepare events before delivery.

#### Scenario: Pre-processing pipeline on a source
- **WHEN** a source has a pre-processing pipeline configured
- **THEN** all events from that source are processed by the pipeline before route evaluation

#### Scenario: Processing pipeline on a route
- **WHEN** a route has a processing pipeline configured and an event matches the route
- **THEN** the event is processed by the route's pipeline

#### Scenario: Post-processing pipeline on a destination
- **WHEN** a destination has a post-processing pipeline configured
- **THEN** all events sent to that destination are processed by the pipeline before delivery

### Requirement: Function Filter Expression
Every function in a pipeline SHALL have a filter expression that determines which events the function processes. The filter expression MUST default to matching all events when not specified. Events that do not match the filter expression SHALL pass through the function unchanged.

#### Scenario: Filter matches all events by default
- **WHEN** a function has no filter expression configured
- **THEN** the function processes all events entering it

#### Scenario: Filter excludes non-matching events
- **WHEN** a function has a filter expression and an event does not match
- **THEN** the event passes through the function unchanged and continues to the next function

#### Scenario: Filter selects matching events
- **WHEN** a function has a filter expression and an event matches
- **THEN** the function processes the matching event

### Requirement: Function Final Toggle
Every function in a pipeline SHALL support a Final toggle. When Final is enabled and the function processes an event (the event matches the filter), the event SHALL NOT be passed to any downstream functions in the pipeline.

#### Scenario: Final toggle stops downstream processing
- **WHEN** a function has Final enabled and processes an event
- **THEN** no downstream functions in the pipeline receive the event

#### Scenario: Final toggle does not affect non-matching events
- **WHEN** a function has Final enabled but an event does not match the filter
- **THEN** the event continues to downstream functions normally

### Requirement: Function Behaviour Interface
All pipeline functions SHALL be implemented as Elixir modules conforming to a common behaviour. The behaviour SHALL define callbacks for executing the function's logic on an event, validating the function's configuration, and describing the function's configurable options.

#### Scenario: Function implements the behaviour
- **WHEN** a new function type is created
- **THEN** it implements all required callbacks defined by the function behaviour

#### Scenario: Invalid function configuration is rejected
- **WHEN** a function configuration fails behaviour validation
- **THEN** the system rejects the configuration with a descriptive error

### Requirement: Pipeline Configuration Storage
Pipeline configurations SHALL be stored in DynamoDB. Each pipeline configuration MUST include the pipeline identifier, an ordered list of functions with their configurations, and metadata such as description and tags.

#### Scenario: Pipeline is persisted to DynamoDB
- **WHEN** a pipeline configuration is created or updated
- **THEN** the configuration is stored in DynamoDB with its identifier, ordered function list, and metadata

#### Scenario: Pipeline is retrieved from DynamoDB
- **WHEN** the system needs to execute a pipeline
- **THEN** it retrieves the pipeline configuration from DynamoDB by identifier

### Requirement: Eval Function
The Eval function SHALL add, modify, or remove event fields through expressions. It SHALL support name-value expression pairs for adding or modifying fields, a Remove Fields list for deleting fields, and a Keep Fields list for retaining only specified fields. Keep Fields SHALL take precedence over Remove Fields when both are specified.

#### Scenario: Add a field via expression
- **WHEN** an Eval function is configured with a name-value pair where the name is "severity" and the value expression evaluates to "high"
- **THEN** the event gains a field "severity" with value "high"

#### Scenario: Remove fields by name
- **WHEN** an Eval function is configured with a Remove Fields list containing "debug_info"
- **THEN** the "debug_info" field is removed from the event

#### Scenario: Keep Fields takes precedence over Remove Fields
- **WHEN** an Eval function has both Keep Fields containing "host" and Remove Fields containing "host"
- **THEN** the "host" field is retained on the event

### Requirement: Drop Function
The Drop function SHALL remove events from the pipeline, preventing them from reaching any downstream functions or the destination. Events matching the function's filter expression SHALL be dropped.

#### Scenario: Event matching filter is dropped
- **WHEN** a Drop function's filter expression matches an event
- **THEN** the event is removed from the pipeline and does not reach downstream functions or the destination

#### Scenario: Event not matching filter passes through
- **WHEN** a Drop function's filter expression does not match an event
- **THEN** the event continues to the next function in the pipeline

### Requirement: Mask Function
The Mask function SHALL replace patterns in event fields for redacting sensitive data. It SHALL support masking rules consisting of a match regex and a replace expression. Multiple masking rules SHALL be supported per function instance, each individually toggleable.

#### Scenario: Regex pattern is replaced
- **WHEN** a Mask function has a rule with match regex matching a credit card pattern and replace expression "XXXX"
- **THEN** all occurrences of the pattern in the configured fields are replaced with "XXXX"

#### Scenario: Multiple masking rules are applied
- **WHEN** a Mask function has two enabled rules
- **THEN** both rules are applied to the event in order

#### Scenario: Disabled masking rule is skipped
- **WHEN** a masking rule is toggled off
- **THEN** that rule is not applied to events

### Requirement: Regex Extract Function
The Regex Extract function SHALL extract fields from event data using regular expressions with named capture groups. It SHALL support configurable source field defaulting to the raw event body. Extracted fields SHALL be added to the event.

#### Scenario: Named capture groups extract fields
- **WHEN** a Regex Extract function has pattern `(?<host>[\\w.]+):(?<port>\\d+)` applied to an event containing "server.example.com:8080"
- **THEN** the event gains fields "host" with value "server.example.com" and "port" with value "8080"

#### Scenario: No match leaves event unchanged
- **WHEN** the regex pattern does not match the source field content
- **THEN** the event passes through without new fields

### Requirement: Rename Function
The Rename function SHALL modify field names on events. It SHALL support explicit rename via old-name to new-name pairs and dynamic rename via an expression. When both explicit renames and a rename expression are configured, explicit renames SHALL execute first.

#### Scenario: Explicit field rename
- **WHEN** a Rename function is configured to rename "src_ip" to "source_address"
- **THEN** the event's "src_ip" field is renamed to "source_address" with its value preserved

#### Scenario: Explicit renames execute before expression
- **WHEN** a Rename function has both explicit renames and a rename expression
- **THEN** explicit renames are applied first, then the rename expression operates on the result

### Requirement: Lookup Function
The Lookup function SHALL enrich events by matching a field value against an external lookup table and appending corresponding values from the table to the event. It SHALL support CSV lookup file format at minimum. It SHALL support configurable match modes including exact match.

#### Scenario: Exact match enriches event
- **WHEN** a Lookup function matches the event's "status_code" field value "404" against a CSV lookup table containing a row for "404" with description "Not Found"
- **THEN** the matched description "Not Found" is appended to the event

#### Scenario: No match uses default value
- **WHEN** a Lookup function does not find a match and a default value is configured
- **THEN** the default value is appended to the event

### Requirement: Comment Function
The Comment function SHALL serve as a text annotation within a pipeline. It SHALL NOT modify event data in any way. It SHALL be visible only in the pipeline configuration interface for documentation purposes.

#### Scenario: Comment does not modify events
- **WHEN** an event passes through a Comment function
- **THEN** the event exits the function identical to how it entered

#### Scenario: Comment is visible in configuration
- **WHEN** a pipeline contains a Comment function with text "Normalize timestamps before routing"
- **THEN** the comment text is displayed in the pipeline configuration interface

### Requirement: Expression Language for Functions
The system SHALL provide an expression language for use in function filter expressions and function value fields. The expression language MUST support field access on events, comparison operators, logical operators, string operations, and arithmetic operations.

**Open Question**: The specific expression language has not been decided. Cribl uses JavaScript (ES6). Compressr needs to evaluate alternatives suitable for the Elixir/BEAM ecosystem (e.g., a safe subset of Elixir expressions, a custom DSL, or an embedded scripting language). This decision will be made before implementation begins.

#### Scenario: Expression accesses event fields
- **WHEN** an expression references a field name that exists on the event
- **THEN** the expression evaluates using that field's value

#### Scenario: Expression evaluates boolean for filter
- **WHEN** a filter expression evaluates to a truthy value for an event
- **THEN** the event is considered matching the filter

#### Scenario: Expression evaluates to a value for Eval
- **WHEN** a value expression in an Eval function is evaluated against an event
- **THEN** the result is used as the new field value
