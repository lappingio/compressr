# Change: Add Schema Registry for Log Type Classification and Per-Type Schema Management

## Why
Sources often carry multiple distinct log types (nginx, syslog, application JSON, CloudTrail, etc.) in a single stream. Without automatic classification and per-type schema tracking, Iceberg destinations produce one giant sparse table per source with poor Parquet compression and expensive Athena scans. A schema registry that classifies log types, tracks per-type schemas, and reports volume breakdowns enables automatic table-per-type routing, dramatically improving storage efficiency and query costs.

## What Changes
- Add a log type classification engine that uses structural fingerprinting to detect distinct log types within a source stream
- Add per-type schema management: each detected log type gets its own schema (field names, types, sample values) stored in DynamoDB
- Add volume tracking per log type within each source (events/sec, bytes/sec, percentage breakdown)
- Add discovery mode for new sources: observe stream and report detected log types with schemas and volumes
- Add new log type detection alerts when previously unseen types appear in a source
- Add LiveView UI for browsing sources, log types, schemas, field details, volume charts, and sample events
- Add REST API endpoints for listing log types, getting schemas, and getting volume breakdowns
- Integrate with Iceberg destination for automatic table-per-type routing with tight per-type schemas
- Integrate with schema drift detection so drift operates per log type, not per source

## Impact
- Affected specs: schema-registry (new), schema-drift-detection (integration point), destinations (Iceberg table routing)
- Affected code: source pipeline (classification stage), DynamoDB schema tables, LiveView UI, REST API, Iceberg destination routing logic
- Dependencies: add-sources (source behaviour), add-schema-drift-detection (per-type drift), add-iceberg-destination (table routing)
