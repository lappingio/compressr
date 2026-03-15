# Change: Add Schema Drift Detection

## Why
Log formats change without warning -- applications get upgraded, developers add fields, vendors alter payloads. Operators currently have no way to know that their source data shape has changed until something breaks downstream (failed Iceberg writes, missing fields in dashboards, broken pipeline functions). Schema drift detection gives operators early, automatic visibility into structural changes in their event streams so they can respond before data quality degrades.

## What Changes
- Adds a new `schema-drift-detection` capability that runs as a lightweight per-source process
- Learns the expected schema per source by observing the first N events, or accepts an explicit operator-defined schema
- Compares every incoming event's structure against the known schema using a fingerprint/hash for sub-millisecond performance
- Detects: new fields, missing fields, type changes (string to number), format changes (date format shift), field renames (heuristic)
- Alerts operators via LiveView UI notifications, webhooks, or the notification system when drift is detected
- Shows a diff with what changed, when it started, and the percentage of events matching the new vs old shape
- Logs drift events with timestamps and sample before/after events
- Emits telemetry metrics: `compressr.schema.drift_detected`, `compressr.schema.fields_added`, `compressr.schema.fields_removed`, `compressr.schema.type_changes`
- Integrates with the Iceberg destination to warn about table schema evolution impact when drift is detected on a source flowing to Iceberg
- Operators can acknowledge drift (accept new schema), suppress specific fields, and configure sensitivity (any change vs breaking only)
- Learned schemas are persisted in DynamoDB per source

## Impact
- Affected specs: `sources` (integration point -- drift detection attaches to source lifecycle), `destinations` (Iceberg impact warnings)
- Affected code: Source supervisor (drift process co-located with source), DynamoDB schema storage, LiveView notification system, telemetry module
- New capability: `schema-drift-detection`
- No breaking changes to existing functionality
