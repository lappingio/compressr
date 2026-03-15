## ADDED Requirements

### Requirement: Route Definition
The system SHALL allow users to define named routes. Each route SHALL consist of:
- A unique, case-sensitive name
- An optional description
- A filter expression evaluated against incoming events
- A reference to exactly one processing pipeline
- A reference to exactly one destination
- A "Final" flag (boolean, default ON)
- An "Enabled" flag (boolean, default ON)
- A position integer that determines evaluation order

Route configurations SHALL be stored in DynamoDB.

#### Scenario: Create a route with all fields
- **WHEN** a user creates a route with name "web-logs", filter `source=='apache'`, pipeline "extract-fields", destination "s3-archive", final ON, and enabled ON
- **THEN** the system SHALL persist the route and it SHALL appear in the routes table at the specified position

#### Scenario: Reject duplicate route name
- **WHEN** a user creates a route with a name that already exists
- **THEN** the system SHALL reject the creation and return a validation error indicating the name is taken

#### Scenario: Route name case sensitivity
- **WHEN** a route named "WebLogs" exists and a user creates a route named "weblogs"
- **THEN** the system SHALL allow the creation because names are case-sensitive

### Requirement: Route Filter Expressions
The system SHALL evaluate route filters using expressions that reference event fields. The system SHALL support the literal value `true` as a catch-all filter that matches all events. Filter expressions SHALL support field references (e.g., `source=='foo.log' && host=='bar'`) and comparison operators.

#### Scenario: Filter matches event fields
- **WHEN** a route has filter `source=='apache'` and an event arrives with `source` field set to `"apache"`
- **THEN** the system SHALL consider the event matched by this route

#### Scenario: Filter does not match
- **WHEN** a route has filter `source=='apache'` and an event arrives with `source` field set to `"nginx"`
- **THEN** the system SHALL NOT consider the event matched by this route and SHALL continue evaluation to the next route

#### Scenario: Catch-all filter
- **WHEN** a route has filter `true`
- **THEN** the system SHALL match all events regardless of their field values

### Requirement: Sequential Route Evaluation
The system SHALL evaluate routes in ascending position order (lowest position first, top to bottom in the UI). When a user reorders routes, the system SHALL update position values and re-evaluate routing behavior based on the new order.

#### Scenario: Routes evaluated in position order
- **WHEN** three routes exist with positions 1, 2, and 3, and an event arrives
- **THEN** the system SHALL evaluate the route at position 1 first, then position 2, then position 3

#### Scenario: Reordering changes evaluation
- **WHEN** a user moves a route from position 3 to position 1
- **THEN** the system SHALL update all affected positions and the moved route SHALL be evaluated first

### Requirement: Final Flag
Each route SHALL have a "Final" flag that defaults to ON. When Final is ON and an event matches the route's filter, the event SHALL be sent to the route's pipeline and destination, and SHALL NOT continue to subsequent routes. When Final is OFF and an event matches, the system SHALL clone the event: the clone SHALL be sent to the route's pipeline and destination, and the original event SHALL continue evaluation against subsequent routes.

#### Scenario: Final ON stops matched events
- **WHEN** a route has Final ON and filter `source=='apache'`, and an event with `source=='apache'` arrives
- **THEN** the event SHALL be routed to this route's pipeline and destination
- **THEN** the event SHALL NOT be evaluated against any subsequent routes

#### Scenario: Final OFF clones matched events
- **WHEN** a route has Final OFF and filter `source=='apache'`, and an event with `source=='apache'` arrives
- **THEN** a clone of the event SHALL be sent to this route's pipeline and destination
- **THEN** the original event SHALL continue evaluation against subsequent routes

#### Scenario: Non-matched events always continue
- **WHEN** an event does not match a route's filter, regardless of the Final flag setting
- **THEN** the event SHALL continue to the next route in the evaluation order

### Requirement: Enabled/Disabled Toggle
Each route SHALL have an "Enabled" flag that defaults to ON. The system SHALL skip disabled routes during event evaluation. Users SHALL be able to toggle a route's enabled state without deleting it.

#### Scenario: Disabled route is skipped
- **WHEN** a route is disabled and an event arrives
- **THEN** the system SHALL skip that route entirely and proceed to the next enabled route

#### Scenario: Re-enabling a route
- **WHEN** a previously disabled route is re-enabled
- **THEN** the system SHALL include it in event evaluation at its current position

### Requirement: Default Catch-All Route
The system SHALL provide a default catch-all route at the bottom of the route table. The default route SHALL have a filter of `true` and Final set to ON. The default route SHALL route all unmatched events to a configurable default destination. The default route SHALL always remain at the last position and SHALL NOT be reorderable above other routes.

#### Scenario: Unmatched events reach default route
- **WHEN** an event does not match any preceding route's filter
- **THEN** the event SHALL be routed to the default catch-all route's destination

#### Scenario: Default route is always last
- **WHEN** a user attempts to reorder the default route above another route
- **THEN** the system SHALL prevent the reorder and the default route SHALL remain at the last position

### Requirement: DevNull Destination
The system SHALL provide a built-in DevNull destination that silently discards all events routed to it. The DevNull destination SHALL require no configuration and SHALL be available immediately. The DevNull destination SHALL be usable as any route's destination for testing, validation, or intentional event dropping.

#### Scenario: Events routed to DevNull are discarded
- **WHEN** a route sends events to the DevNull destination
- **THEN** the system SHALL discard those events without outputting them to any external system

#### Scenario: DevNull requires no setup
- **WHEN** the system starts for the first time
- **THEN** the DevNull destination SHALL be available without any user configuration

### Requirement: Route CRUD API
The system SHALL provide REST API endpoints for creating, reading, updating, deleting, and listing routes. The system SHALL provide an endpoint for reordering routes by updating position values. The system SHALL validate that pipeline and destination references point to existing resources.

#### Scenario: List all routes
- **WHEN** a user sends a GET request to the routes list endpoint
- **THEN** the system SHALL return all routes ordered by position

#### Scenario: Create a route via API
- **WHEN** a user sends a POST request with valid route fields
- **THEN** the system SHALL create the route and return it with an assigned ID and position

#### Scenario: Delete a route
- **WHEN** a user sends a DELETE request for an existing route
- **THEN** the system SHALL remove the route and re-compact positions of remaining routes

#### Scenario: Reject invalid pipeline reference
- **WHEN** a user creates a route referencing a pipeline ID that does not exist
- **THEN** the system SHALL reject the request with a validation error

### Requirement: Routes Table UI
The system SHALL provide a LiveView routes table displaying all routes in position order. The table SHALL show columns for: enabled toggle, route name, filter expression, pipeline, destination, and final toggle. The system SHALL support drag-and-drop reordering of routes within the table. The system SHALL support inline toggling of the enabled and final flags. The system SHALL display the default catch-all route at the bottom of the table in a visually distinct manner.

#### Scenario: View routes table
- **WHEN** a user navigates to the routes page
- **THEN** the system SHALL display all routes in a table ordered by position with the default route at the bottom

#### Scenario: Drag-and-drop reorder
- **WHEN** a user drags a route from one position to another in the table
- **THEN** the system SHALL update position values and re-render the table in the new order

#### Scenario: Inline toggle enabled
- **WHEN** a user clicks the enabled toggle on a route in the table
- **THEN** the system SHALL update the route's enabled state and reflect the change immediately in the UI
