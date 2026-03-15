## 1. Destination Behaviour and Core Types
- [ ] 1.1 Define `Compressr.Destination` behaviour with callbacks: `init/1`, `write/2`, `flush/1`, `stop/1`, `healthy?/1`
- [ ] 1.2 Define destination configuration Ash resource with fields: id, type, config (map), enabled, backpressure_mode, post_processing_pipeline_id, batch_config, format_config
- [ ] 1.3 Implement DynamoDB persistence for destination configs via Ash/ex_aws_dynamo
- [ ] 1.4 Implement destination registry GenServer to track running destination processes
- [ ] 1.5 Implement destination supervisor tree (DynamicSupervisor for destination worker processes)

## 2. S3 Destination
- [ ] 2.1 Implement S3 destination module using the object storage behaviour from project.md
- [ ] 2.2 Support local file staging, compression (gzip), and upload via ex_aws_s3
- [ ] 2.3 Support configurable partitioning expression (default: date-based path)
- [ ] 2.4 Support S3 storage class selection (Standard, Intelligent-Tiering, Glacier variants)
- [ ] 2.5 Support output formats: JSON (default), Raw
- [ ] 2.6 Support configurable file close conditions: size limit, time limit, idle timeout
- [ ] 2.7 Write unit and integration tests for S3 destination

## 3. Elasticsearch Destination
- [ ] 3.1 Implement Elasticsearch destination using Bulk API
- [ ] 3.2 Support configurable index name with per-event override via `__index` field
- [ ] 3.3 Support authentication: none, basic (username/password), API key
- [ ] 3.4 Normalize `_time` to `@timestamp` and `host` to `host.name`
- [ ] 3.5 Support gzip payload compression
- [ ] 3.6 Implement HTTP connection pooling and retry with exponential backoff
- [ ] 3.7 Write unit and integration tests for Elasticsearch destination

## 4. Splunk HEC Destination
- [ ] 4.1 Implement Splunk HEC destination targeting `/services/collector/event` endpoint
- [ ] 4.2 Support HEC auth token configuration
- [ ] 4.3 Support configurable body size limit (default 4096 KB) and flush period (default 1s)
- [ ] 4.4 Use `_raw` field for log events when present; serialize full event as JSON otherwise
- [ ] 4.5 Support gzip payload compression
- [ ] 4.6 Implement HTTP connection pooling and retry with exponential backoff
- [ ] 4.7 Write unit and integration tests for Splunk HEC destination

## 5. DevNull Destination
- [ ] 5.1 Implement DevNull destination that discards all events
- [ ] 5.2 Ensure DevNull requires no configuration and is pre-configured on install
- [ ] 5.3 Write unit tests for DevNull destination

## 6. Common Infrastructure
- [ ] 6.1 Implement backpressure handling: block mode (refuse new events), drop mode (discard events)
- [ ] 6.2 Accept queue mode in configuration but return an error/warning that persistent queuing is not yet implemented
- [ ] 6.3 Implement batching logic: configurable batch size, flush interval, and max batch age
- [ ] 6.4 Implement output format selection per destination (JSON, Raw)
- [ ] 6.5 Implement destination health check reporting (healthy, unhealthy, disabled)
- [ ] 6.6 Implement enabled/disabled toggle with graceful drain on disable
- [ ] 6.7 Implement REST API endpoints for destination CRUD (mirroring Cribl API paths where practical)
- [ ] 6.8 Write integration tests for destination lifecycle (create, enable, disable, delete)
