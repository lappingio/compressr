## 1. Source Behaviour and Common Infrastructure
- [ ] 1.1 Define `Compressr.Source` behaviour with callbacks: `start_link/1`, `stop/1`, `handle_event/2`, `validate_config/1`
- [ ] 1.2 Create `Compressr.Source.Config` Ash resource for DynamoDB-backed source configuration (id, type, name, config map, enabled, pre_processing_pipeline_id)
- [ ] 1.3 Implement source lifecycle supervisor that starts/stops source processes based on enabled/disabled state
- [ ] 1.4 Implement source event emission -- sources produce `Compressr.Event` structs and hand them to the routing layer

## 2. Syslog Source
- [ ] 2.1 Implement `Compressr.Source.Syslog` behaviour for UDP listener (configurable bind address and port)
- [ ] 2.2 Implement `Compressr.Source.Syslog` behaviour for TCP listener (configurable bind address, port, TLS optional)
- [ ] 2.3 Implement RFC 5424 and RFC 3164 syslog message parsing
- [ ] 2.4 Add configurable event breaking for TCP streams (newline-delimited, octet-counting)

## 3. HTTP / Splunk HEC Source
- [ ] 3.1 Implement `Compressr.Source.HTTP` with a configurable HTTP listener (bind address, port, TLS)
- [ ] 3.2 Implement Splunk HEC-compatible `/services/collector/event` and `/services/collector/raw` endpoints
- [ ] 3.3 Implement per-source HEC token authentication (validate bearer token against source config)
- [ ] 3.4 Implement HEC health check endpoint (`/services/collector/health`)
- [ ] 3.5 Support JSON and raw text event ingestion formats

## 4. S3 Collector Source
- [ ] 4.1 Implement `Compressr.Source.S3` as a collector (pull-based) using the object storage behaviour from project.md
- [ ] 4.2 Implement S3 bucket listing with prefix/suffix filtering and configurable polling interval
- [ ] 4.3 Implement standard-tier object retrieval and event streaming (line-delimited, JSON, gzip decompression)
- [ ] 4.4 Implement Glacier tiered-storage rehydration lifecycle: initiate restore, poll for availability, replay when ready
- [ ] 4.5 Implement collection state tracking (DynamoDB) to avoid re-processing already-collected objects
- [ ] 4.6 Support ad hoc and scheduled collection runs

## 5. Source Configuration API
- [ ] 5.1 Implement REST API endpoints for source CRUD (create, read, update, delete, list) protected by OIDC auth
- [ ] 5.2 Implement source enable/disable toggle via API
- [ ] 5.3 Implement configuration validation on create/update (delegates to source type's `validate_config/1`)
- [ ] 5.4 Implement source status endpoint (running, stopped, error state, event counters)

## 6. Source Management UI
- [ ] 6.1 Implement LiveView page listing all configured sources with status indicators
- [ ] 6.2 Implement source creation form with type selection and type-specific configuration fields
- [ ] 6.3 Implement source edit/delete with confirmation
- [ ] 6.4 Implement real-time source status updates via LiveView

## 7. Tests
- [ ] 7.1 Unit tests for source behaviour contract compliance across all three source types
- [ ] 7.2 Unit tests for syslog RFC 5424 and RFC 3164 parsing
- [ ] 7.3 Integration tests for HEC endpoint (token auth, event ingestion, health check)
- [ ] 7.4 Integration tests for S3 collector (mocked S3 -- listing, retrieval, Glacier restore lifecycle)
- [ ] 7.5 Integration tests for source CRUD API (auth required, validation, enable/disable)
- [ ] 7.6 Property-based tests for syslog message parsing with StreamData
