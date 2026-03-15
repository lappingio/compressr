## 1. Schema Representation and Fingerprinting
- [ ] 1.1 Define `Compressr.Schema.FieldSpec` struct (field name, type, format, optional flag)
- [ ] 1.2 Define `Compressr.Schema.SchemaSnapshot` struct (field specs map, fingerprint hash, timestamp, event count)
- [ ] 1.3 Implement structural fingerprint/hash function that produces a hash from event key structure and value types (sub-millisecond target)
- [ ] 1.4 Implement type inference for event field values (string, integer, float, boolean, timestamp, nested object, array)
- [ ] 1.5 Write unit tests for fingerprinting and type inference

## 2. Schema Learning
- [ ] 2.1 Implement schema learning GenServer (`Compressr.Schema.Learner`) that observes first N events and builds a baseline schema
- [ ] 2.2 Support configurable learning window size (default 1000 events)
- [ ] 2.3 Support explicit operator-defined schema as an alternative to learning
- [ ] 2.4 Persist learned schema to DynamoDB keyed by source ID
- [ ] 2.5 Load persisted schema on source restart (skip re-learning if schema exists)
- [ ] 2.6 Write tests for schema learning and persistence

## 3. Drift Detection Engine
- [ ] 3.1 Implement `Compressr.Schema.DriftDetector` GenServer that runs per-source
- [ ] 3.2 Implement fast-path: compare event fingerprint hash against baseline hash (sub-millisecond, skip deep comparison when hashes match)
- [ ] 3.3 Implement slow-path: when hashes differ, perform deep comparison to classify drift type (new fields, missing fields, type changes, format changes)
- [ ] 3.4 Implement field rename heuristic (detect when a field disappears and a similarly-named field appears in the same event)
- [ ] 3.5 Track drift statistics: percentage of events matching old vs new shape, first seen timestamp, sample events
- [ ] 3.6 Support sensitivity configuration: `all_changes` (alert on any structural change) vs `breaking_only` (alert only on missing fields and type changes)
- [ ] 3.7 Support field suppression: operator can mark specific fields to ignore during drift comparison
- [ ] 3.8 Write tests for drift detection, classification, and sensitivity modes

## 4. Drift Alerting and Notifications
- [ ] 4.1 Emit telemetry events: `compressr.schema.drift_detected` (counter by source_id), `compressr.schema.fields_added`, `compressr.schema.fields_removed`, `compressr.schema.type_changes`
- [ ] 4.2 Integrate with LiveView notification system to push real-time drift alerts to the UI
- [ ] 4.3 Support webhook notification for drift events (configurable URL per source)
- [ ] 4.4 Log drift events with timestamp, source ID, drift type, and sample before/after events
- [ ] 4.5 Build drift diff view: show what changed, when it started, percentage of events with new shape vs old
- [ ] 4.6 Write tests for notification emission and drift diff generation

## 5. Operator Controls
- [ ] 5.1 Implement "acknowledge drift" action: accept new schema as the baseline and reset drift state
- [ ] 5.2 Implement field suppression configuration: operators can exclude specific fields from drift detection
- [ ] 5.3 Implement sensitivity configuration: per-source toggle between `all_changes` and `breaking_only`
- [ ] 5.4 Expose drift detection configuration in the Source Configuration API (REST endpoints)
- [ ] 5.5 Write tests for operator control actions

## 6. Iceberg Destination Integration
- [ ] 6.1 When drift is detected on a source that flows to an Iceberg destination, generate an impact warning
- [ ] 6.2 Show Iceberg impact details: new columns that will be added, type changes that may cause schema evolution conflicts
- [ ] 6.3 Include Iceberg impact in drift notifications (LiveView and webhook)
- [ ] 6.4 Write tests for Iceberg impact analysis

## 7. Source Lifecycle Integration
- [ ] 7.1 Start drift detection process alongside source process in the source supervisor
- [ ] 7.2 Wire event flow so every event passes through drift detection before entering the routing layer
- [ ] 7.3 Ensure drift detection process restarts with the source process
- [ ] 7.4 Stop drift detection when source is disabled
- [ ] 7.5 Write integration tests for drift detection within source lifecycle

## 8. LiveView UI
- [ ] 8.1 Add schema drift status indicator to the source list view
- [ ] 8.2 Build drift detail view: schema diff, drift timeline, sample events, acknowledge button
- [ ] 8.3 Add drift detection configuration to source create/edit forms (learning window, sensitivity, field suppression)
- [ ] 8.4 Add real-time drift alert banner/toast in the LiveView UI
- [ ] 8.5 Write LiveView tests for drift UI components

## 9. DynamoDB Schema Storage
- [ ] 9.1 Define DynamoDB table schema for learned schemas (partition key: source_id, attributes: schema snapshot, fingerprint, updated_at)
- [ ] 9.2 Define DynamoDB table schema for drift events (partition key: source_id, sort key: timestamp)
- [ ] 9.3 Implement read/write operations for schema and drift event persistence
- [ ] 9.4 Write tests for DynamoDB persistence operations
