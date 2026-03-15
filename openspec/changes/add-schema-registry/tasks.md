## 1. Log Type Classification Engine
- [ ] 1.1 Define `Compressr.SchemaRegistry.Classifier` behaviour with classify/1 callback
- [ ] 1.2 Implement structural fingerprinting classifier (field sets, field patterns, format markers)
- [ ] 1.3 Implement regex pattern matching classifier (configurable patterns)
- [ ] 1.4 Implement field presence rules classifier (e.g., has request_path + status_code = HTTP access log)
- [ ] 1.5 Implement operator-defined classification rules support
- [ ] 1.6 Implement composite classifier that chains methods with priority ordering
- [ ] 1.7 Write ExUnit tests for each classification method and edge cases

## 2. Per-Type Schema Management
- [ ] 2.1 Define `Compressr.SchemaRegistry.Schema` struct (field names, types, sample values, fingerprint)
- [ ] 2.2 Implement schema inference from event samples (type detection for string, integer, float, boolean, timestamp, nested object, array)
- [ ] 2.3 Implement schema merging for incremental learning (new fields discovered in later samples)
- [ ] 2.4 Write ExUnit tests for schema inference and merging

## 3. DynamoDB Persistence
- [ ] 3.1 Design DynamoDB table schema for log type registry (PK: source_id, SK: log_type_id)
- [ ] 3.2 Design DynamoDB table schema for per-type schemas (PK: log_type_id, SK: version)
- [ ] 3.3 Design DynamoDB table schema for volume metrics (PK: source_id#log_type_id, SK: timestamp)
- [ ] 3.4 Implement Ash resource for log type records
- [ ] 3.5 Implement Ash resource for schema records
- [ ] 3.6 Implement Ash resource for volume metric records
- [ ] 3.7 Write ExUnit tests for DynamoDB persistence operations

## 4. Discovery Mode
- [ ] 4.1 Implement discovery GenServer that observes initial events (default 10,000) and classifies all log types
- [ ] 4.2 Implement sampling strategy: every event during learning phase, then configurable sampling ratio (default 1:100)
- [ ] 4.3 Implement discovery report generation (detected log types, schemas, volume breakdown)
- [ ] 4.4 Write ExUnit tests for discovery mode lifecycle and sampling

## 5. Volume Tracking
- [ ] 5.1 Implement per-type volume counters (events/sec, bytes/sec) using :counters or ETS
- [ ] 5.2 Implement percentage breakdown calculation across log types within a source
- [ ] 5.3 Implement periodic volume snapshot persistence to DynamoDB
- [ ] 5.4 Write ExUnit tests for volume tracking accuracy

## 6. New Log Type Detection and Alerting
- [ ] 6.1 Implement new log type detection when unclassified events appear after learning phase
- [ ] 6.2 Implement LiveView real-time notification for new log type detection
- [ ] 6.3 Implement webhook notification for new log type detection
- [ ] 6.4 Implement telemetry events for new log type detection
- [ ] 6.5 Write ExUnit tests for new log type detection and alerting

## 7. Source Pipeline Integration
- [ ] 7.1 Add classification stage to source event pipeline (after source emit, before routing)
- [ ] 7.2 Tag each event with its classified log type ID
- [ ] 7.3 Ensure classification does not block event processing (sub-millisecond for fingerprint match)
- [ ] 7.4 Write ExUnit tests for pipeline integration and performance

## 8. Schema Drift Detection Integration
- [ ] 8.1 Modify drift detection to operate per log type instead of per source
- [ ] 8.2 Ensure drift alerts include log type context (which log type drifted)
- [ ] 8.3 Write ExUnit tests for per-type drift detection

## 9. Iceberg Destination Integration
- [ ] 9.1 Implement table-per-type routing: each log type maps to its own Iceberg table
- [ ] 9.2 Use per-type schema from registry to create tight Iceberg table schemas (no union schema)
- [ ] 9.3 Implement automatic table creation when new log types are detected
- [ ] 9.4 Write ExUnit tests for table-per-type routing

## 10. REST API
- [ ] 10.1 Implement GET /api/sources/:source_id/log-types (list log types for a source)
- [ ] 10.2 Implement GET /api/sources/:source_id/log-types/:type_id/schema (get schema for a log type)
- [ ] 10.3 Implement GET /api/sources/:source_id/log-types/:type_id/volume (get volume breakdown)
- [ ] 10.4 Implement GET /api/sources/:source_id/volume-breakdown (get volume breakdown across all types)
- [ ] 10.5 Implement GET /api/schema-registry/search (search which log type contains a given field)
- [ ] 10.6 Write ExUnit tests for all API endpoints

## 11. LiveView UI
- [ ] 11.1 Implement schema browser page: sources list with log type counts
- [ ] 11.2 Implement log type detail view: schema fields, types, sample values
- [ ] 11.3 Implement volume breakdown charts per source (percentage per log type)
- [ ] 11.4 Implement sample events viewer per log type
- [ ] 11.5 Implement field search across all log types ("where is field X?")
- [ ] 11.6 Implement new log type notification banner in LiveView
- [ ] 11.7 Write LiveView tests for schema browser interactions

## 12. Telemetry
- [ ] 12.1 Emit `compressr.schema_registry.log_type_detected` counter (tagged by source_id)
- [ ] 12.2 Emit `compressr.schema_registry.classification_time` histogram (tagged by source_id)
- [ ] 12.3 Emit `compressr.schema_registry.new_type_discovered` counter (tagged by source_id)
- [ ] 12.4 Emit `compressr.schema_registry.events_classified` counter (tagged by source_id, log_type_id)
- [ ] 12.5 Write ExUnit tests for telemetry event emission
