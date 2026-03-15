# Change: Add route-based event routing

## Why
Routes are the core mechanism that connects sources to destinations through processing pipelines. Without routes, events have no way to flow through the system. This proposal defines the routing table, filter evaluation, final-flag cloning semantics, and the default catch-all behavior needed for MVP data flow.

## What Changes
- Define route resources with filter expression, pipeline reference, destination reference, enabled toggle, and final flag
- Establish sequential (top-to-bottom) evaluation order for routes
- Define final-flag semantics: matched events stop when final is ON, cloned and continue when final is OFF
- Provide a default/catch-all route at the bottom for unmatched events
- Provide a built-in DevNull destination for discarding events
- Route configurations stored in DynamoDB
- New capability: `routes`

### Explicitly Out of Scope for MVP
- **QuickConnect** visual wiring interface
- **Output Router** meta-destination for post-pipeline fan-out
- **Route Groups** for UI grouping of consecutive routes
- **Data Preview** pane on the routes table
- **Route statistics** display (event/byte counts)
- **Clone fields** (additional fields attached to cloned events)
- **Destination expressions** (dynamic destination via expression)
- **Unreachable route warnings**

## Impact
- Affected specs: `routes` (new capability)
- Affected code: New Ash resources, LiveView components, and REST API endpoints
- Dependencies: `event-model` (defines the events being routed)
- Downstream: Pipeline execution, destination output, and source integration will connect through routes
