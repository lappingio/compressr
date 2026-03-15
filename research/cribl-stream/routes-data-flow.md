## Routes Overview

Routes are the primary mechanism for directing data from sources through processing pipelines to destinations in Cribl Stream. They act as intelligent event filters that evaluate JavaScript expressions against incoming events to determine which pipeline processes them and which destination receives the output. Routes are evaluated sequentially in display order, top to bottom.

The full event processing order is: Source ingestion -> Event breaking -> Time filtering -> Field enrichment -> Source persistent queue -> Pre-processing pipeline -> Route evaluation -> Processing pipeline -> Post-processing pipeline -> Destination persistent queue -> Destination output.

### Requirement: Route Definition
- The system SHALL allow users to define named routes, each consisting of a filter expression, a pipeline/pack association, and a destination.
- The system SHALL require route names to be unique and SHALL treat names as case-sensitive.
- The system SHALL allow each route to be associated with exactly one processing pipeline or pack.
- The system SHALL allow each route to specify exactly one destination.
- The system SHALL allow an optional description field on each route.

### Requirement: Route Filter Expressions
- The system SHALL evaluate route filters using JavaScript-compatible expression syntax.
- The system SHALL support expressions referencing event fields (e.g., `source=='foo.log' && fieldA=='bar'`).
- The system SHALL support the literal value `true` as a catch-all filter that matches all events.
- The system SHALL evaluate each incoming event against route filters sequentially in display order (top to bottom).

### Requirement: Sequential Route Evaluation
- The system SHALL evaluate routes in the order they appear in the route list, from first to last.
- The system SHALL allow users to reorder routes via drag-and-drop in the UI.
- The system SHALL re-evaluate routing behavior based on the new display order when routes are reordered.

### Requirement: Final Flag (Event Flow Control)
- The system SHALL provide a "Final" toggle on each route, defaulting to ON.
- When Final is ON, the system SHALL stop matched events from continuing to subsequent routes; only non-matched events SHALL continue.
- When Final is OFF, the system SHALL allow all events (matched and non-matched) to continue to the next route.
- When Final is OFF, the system SHALL treat matched events sent to the current route's pipeline as clones of the original event.

### Requirement: Enabled/Disabled Toggle
- The system SHALL allow each route to be individually enabled or disabled inline.
- The system SHALL skip disabled routes during event evaluation.
- The system SHALL support toggling route state to facilitate development and debugging.

### Requirement: Destination Expressions
- The system SHALL support static destination selection for each route.
- The system SHALL support dynamic destination selection via JavaScript expressions when the "Expression" toggle is enabled.
- The system SHALL evaluate destination expressions at route construction time, not per-event.
- The system SHALL support expressions referencing environment context (e.g., `` `myDest_${C.logStreamEnv}` ``).

### Requirement: Unreachable Route Warnings
- The system SHALL display an orange triangle warning indicator on routes that are unreachable.
- The system SHALL consider a route unreachable when a preceding enabled route has Final toggled ON and a filter that evaluates to `true`.
- The system SHALL detect and warn about filters using randomizing methods (e.g., `Math.random()`) that cause intermittent unreachability.

### Requirement: Route Statistics Display
- The system SHALL display event count and byte count statistics for each route for the most recent 15-minute window.
- The system SHALL display percentage throughput comparing individual route traffic to total traffic across all routes.

### Requirement: Route Context Menu Operations
- The system SHALL support inserting new routes at specific positions.
- The system SHALL support copying, moving, and deleting routes.
- The system SHALL support adding comments above or below routes for documentation.
- The system SHALL support capturing sample data through a selected route.

---

## Default Route and Catch-All Behavior

### Requirement: Default/Catch-All Route
- The system SHALL recommend (and support) a catch-all route at the end of the route list using a filter of `true`.
- The system SHALL route unmatched events that pass through all routes to a configurable Default Destination.

### Requirement: endRoute Bumper
- The system SHALL display an endRoute bumper visual indicator at the bottom of the routes table when no route has Final toggled ON.
- The endRoute bumper SHALL warn administrators that events will continue to the Default Destination.
- The endRoute bumper SHALL identify the currently configured Default Destination.
- The endRoute bumper SHALL warn that duplicate events may result if the Default Destination matches a destination assigned to a route higher in the stack.
- The system SHALL provide a link from the endRoute bumper to modify the Default Destination configuration.

### Requirement: DevNull Destination
- The system SHALL provide a preconfigured DevNull destination that discards all incoming events.
- The DevNull destination SHALL require no configuration and SHALL be active immediately upon installation.
- The DevNull destination SHALL be usable as a route destination for testing and validation without sending data to external systems.

---

## Cloning / Fan-Out

### Requirement: Event Cloning via Final Flag
- When a route's Final flag is OFF, the system SHALL clone matched events before sending them to the route's pipeline.
- The original event SHALL continue evaluation against subsequent routes.
- The cloned event SHALL be processed through the current route's pipeline and sent to the route's destination.

### Requirement: Clone Fields
- When Final is OFF, the system SHALL provide an "Add Clone" button to attach additional fields (name-value pairs) to cloned events.
- Clone fields SHALL be added to the cloned copy before it is passed to the route's pipeline.

### Requirement: Cloning Best Practices
- The system documentation SHALL recommend cloning events as late as possible in the route stack to minimize downstream function processing overhead.
- The system documentation SHALL recommend designing data paths to move through as few routes as possible.
- The system documentation SHALL recommend ordering routes with most-specific first for narrow/specialized processing, or broadest first to consume high-volume events early.

---

## Drop/Filter at the Route Level

### Requirement: Drop Function in Pipelines
- The system SHALL provide a Drop function that deletes any events matching its filter expression.
- The Drop function filter SHALL use JavaScript expressions, defaulting to `true`.
- The Drop function SHALL support a Final toggle that, when enabled, prevents data from reaching any downstream functions.
- The Drop function SHALL completely remove matching events from the pipeline.

### Requirement: Route-Level Filtering Strategy
- Routes SHALL filter events via their filter expression to direct only matching events to a pipeline; non-matching events continue to subsequent routes (when Final is ON).
- To drop events at the route level, the system SHALL support routing matched events to the DevNull destination or to a pipeline containing a Drop function.

---

## Route Groups

### Requirement: Route Group Definition
- The system SHALL support grouping consecutive routes into a Route Group.
- Route Groups SHALL allow collective movement of grouped routes up and down the route stack.

### Requirement: Route Group Behavior
- Route Groups SHALL be a UI visualization only; they SHALL NOT alter route evaluation logic.
- Routes within a group SHALL maintain their global position order.
- Route Groups SHALL function analogously to Function groups in the pipeline UI.

---

## QuickConnect

QuickConnect is an alternative visual interface for connecting sources to destinations without using the traditional routes table. It is suited for simpler, parallel data paths.

### Requirement: Visual Connection Interface
- The system SHALL provide a tile-based visual interface with sources on the left and destinations on the right.
- The system SHALL allow users to drag connection lines between source tiles and destination tiles.

### Requirement: Processing Stage Insertion
- The system SHALL allow inserting processing elements into connections: Passthru (no transformation), Pipeline, or Pack.
- The system SHALL allow data to flow directly from source to destination without any processing.

### Requirement: Multiple Connections
- The system SHALL support multiple connection lines between the same source-destination pair for parallel processing.
- The system SHALL support connecting one source to multiple destinations.
- The system SHALL support connecting multiple sources to one destination.

### Requirement: QuickConnect Limitations
- QuickConnect SHALL NOT support route-level filtering or data cloning.
- QuickConnect SHALL NOT support cascading data across multiple pipelines.
- QuickConnect SHALL NOT support configuring Collector Sources (REST, Database, S3, etc.); those SHALL require the Routes interface.

### Requirement: Context Switching
- The system SHALL allow moving source configurations between QuickConnect and Routes interfaces.
- The system SHALL require user confirmation when switching contexts, as data will stop flowing through the original path.
- Configurations SHALL exist separately in each context (QuickConnect vs. Routes).

### Requirement: Tile Status and Management
- Source and destination tiles SHALL display status indicators (live, disabled, error, warning).
- Each tile SHALL provide a configure button to reopen its configuration drawer.
- Each tile SHALL provide a capture button to sample live data.
- The system SHALL automatically stack multiple tiles of the same type and display a counter.

### Requirement: Source Behavior
- Sources SHALL appear as "Disabled" until connected to a destination.

---

## Data Preview

### Requirement: Real-Time Preview
- The system SHALL provide a Data Preview tool that processes sample events through pipeline and route logic and displays results in real-time.
- The system SHALL update the preview instantly when functions are modified, added, or removed.
- The system SHALL cap simple previews at 10 MB of data.

### Requirement: Preview Views
- The system SHALL provide an IN tab showing sample data before pipeline processing.
- The system SHALL provide an OUT tab showing transformed data after pipeline processing.
- The system SHALL support Event View (JSON format), Table View (tabular format), and Metrics View (for metric events).

### Requirement: Diagnostic Capabilities
- The system SHALL provide a Status tab with graphs tracking Events In, Events Out, and Events Dropped over time.
- The system SHALL provide Pipeline Profiling with Statistics, Pipeline Profile, and Advanced CPU Profile tabs.
- The Pipeline Profile SHALL reveal individual function contributions to data volume, event counts, and processing time.

### Requirement: Advanced Preview Settings
- The system SHALL support showing dropped events with diff highlighting (amber for modifications, green for additions, red strikethrough for deletions).
- The system SHALL support showing internal fields (Cribl-added and source-specific).
- The system SHALL support rendering whitespace characters symbolically.
- The system SHALL support configurable processing timeout (default 10 seconds, minimum 1 second).
- The system SHALL support exporting captured data as JSON or NDJSON format.

### Requirement: Route-Level Data Preview
- The system SHALL provide a Data Preview pane togglable from the Routes display using the `]` (right-bracket) shortcut key.
- The system SHALL support capturing sample data through a selected route via the route's context menu.

### Requirement: Sample Data Sources
- The system SHALL support sample data created manually, imported from existing sources, generated through datagens (simulated live data), or captured and shared across teams.

---

## Output Router (Alternative Fan-Out Mechanism)

### Requirement: Output Router Destination
- The system SHALL provide an Output Router meta-destination that evaluates events against ordered filter rules to route them to downstream destinations.
- Output Router rules SHALL process sequentially from top to bottom.

### Requirement: Output Router Rule Configuration
- Each rule SHALL contain a filter expression (JavaScript), an output destination, and a Final toggle.
- The filter expression SHALL have access to fields modified by pre-processing and route pipelines but SHALL NOT have access to fields created during post-processing.
- When Final is ON (default), routing SHALL terminate after a match.
- When Final is OFF, the event SHALL continue evaluating against subsequent rules, enabling multi-destination fan-out.

### Requirement: Output Router Default Behavior
- Events matching no Output Router rules SHALL route to the Default Destination.
- An Output Router SHALL NOT route to another Output Router or to a Default Destination that points back to a router.

### Requirement: Output Router System Fields
- The system SHALL optionally add system fields to routed events, including: `cribl_pipe`, `cribl_host`, `cribl_input`, `cribl_output`, `cribl_route`, `cribl_wp`.

---

## Event Processing Order (End-to-End)

### Requirement: Processing Pipeline Stages
- The system SHALL process events through the following stages in order:
  1. Source ingestion from external systems
  2. Optional pre-processing custom command (stdin/stdout)
  3. Event Breakers to discretize byte streams into individual events
  4. Time filters to eliminate events outside specified ranges
  5. Field enrichment with key-value pairs using JavaScript expressions
  6. Optional source-side persistent queue for backpressure buffering
  7. Append `__inputId` internal field
  8. Route evaluation to map events to pipelines and destinations
  9. Pre-processing pipeline (source-attached, runs before route pipeline)
  10. Processing pipeline (route-attached, core transformation)
  11. Post-processing pipeline (destination-attached, output conditioning)
  12. Optional destination-side persistent queue
  13. Destination output

### Requirement: Pipeline Structural Consistency
- All pipeline types (pre-processing, processing, post-processing) SHALL have the same internal structure: a series of functions evaluated in top-down order.
- The three pipeline types SHALL differ only in their position in the processing chain.
