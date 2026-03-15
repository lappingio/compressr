## Monitoring Overview

Cribl Stream provides a built-in monitoring subsystem that exposes internal metrics about its own operation, presents them through a UI dashboard, enables alerting via multiple channels, and supports forwarding all internal telemetry to external observability platforms. Monitoring data does not persist across Cribl Stream restarts. The monitoring time range is configurable from 5 minutes to 1 day.

### General Requirements

### Requirement: Internal Metrics Emission
- The system SHALL emit internal metrics covering total throughput, system health, worker resource usage, persistent queues, pipeline performance, route performance, source/destination throughput, and connection activity.
- The system SHALL prefix all internal metric names with `cribl.logstream.` by default, with the prefix being configurable.
- The system SHALL attach contextual dimension labels to all metrics, including `cribl_wp` (worker process ID), `input` (source ID), `output` (destination ID), `group` (worker group name), and `event_host` (originating hostname).
- The system SHALL support a configurable maximum number of unique metrics in memory (default: 1,000,000).
- The system SHALL support a configurable metrics garbage collection period (default: 60 seconds).
- The system SHALL support a configurable cardinality limit per Worker Group (default: 1,000).
- The system SHALL drop metrics when in-flight requests exceed 1,000, while maintaining a never-drop list for critical metrics.
- The system SHALL log dropped metrics under the `channel="clustercomm"` log channel.

---

### Requirement: Total Throughput Metrics
- The system SHALL expose `total.in_bytes` measuring inbound bytes from all sources.
- The system SHALL expose `total.in_events` measuring inbound events from all sources.
- The system SHALL expose `total.out_bytes` measuring outbound bytes to all destinations.
- The system SHALL expose `total.out_events` measuring outbound events to all destinations.
- The system SHALL expose `total.dropped_events` measuring events discarded during processing, to help identify disabled or failing destinations.

---

### Requirement: System Health Composite Metrics
- The system SHALL expose `health.inputs` indicating source health status per configured source, with values 0 (healthy/green), 1 (warning/yellow), or 2 (trouble/red).
- The system SHALL expose `health.outputs` indicating destination health status per configured destination, with values 0 (healthy/green), 1 (warning/yellow), or 2 (trouble/red).

---

### Requirement: System Resource Metrics
- The system SHALL expose `system.load_avg` measuring CPU load average.
- The system SHALL expose `system.free_mem` measuring available memory.
- The system SHALL expose `system.disk_used` measuring disk space consumption.
- The system SHALL expose `system.cpu_perc` measuring per-worker-process CPU utilization percentage.
- The system SHALL expose `system.mem_rss` measuring per-worker-process RAM consumption in bytes.

---

### Requirement: Pipeline Performance Metrics
- The system SHALL expose `pipe.in_events` measuring events entering each pipeline.
- The system SHALL expose `pipe.out_events` measuring events exiting each pipeline.
- The system SHALL expose `pipe.dropped_events` measuring events dropped within each pipeline.
- The system SHALL label pipeline metrics with the pipeline identifier to allow per-pipeline analysis.

---

### Requirement: Route Metrics
- The system SHALL expose `route.in_bytes` measuring bytes entering each route.
- The system SHALL expose `route.in_events` measuring events entering each route.
- The system SHALL expose `route.out_bytes` measuring bytes exiting each route.
- The system SHALL expose `route.out_events` measuring events exiting each route.

---

### Requirement: Source and Destination Throughput Metrics
- The system SHALL expose `source.in_bytes`, `source.in_events`, `source.out_bytes`, and `source.out_events` per configured source.
- The system SHALL expose per-sourcetype metrics: `sourcetype.in_bytes`, `sourcetype.in_events`, `sourcetype.out_bytes`, `sourcetype.out_events`.
- The system SHALL expose per-host metrics: `host.in_bytes`, `host.in_events`, `host.out_bytes`, `host.out_events`.
- The system SHALL expose per-index metrics: `index.in_bytes`, `index.in_events`, `index.out_bytes`, `index.out_events`.

---

### Requirement: Connection and I/O Metrics
- The system SHALL expose `iometrics.activeCxn` measuring active inbound connections per source/destination.
- The system SHALL expose `iometrics.closeCxn` measuring closed connections.
- The system SHALL expose `iometrics.openCxn` measuring opened connections.
- The system SHALL expose `iometrics.rejectCxn` measuring rejected connections, with a `reject_reason` dimension.
- The system SHALL expose `iometrics.p95_duration_millis` measuring 95th percentile processing time.
- The system SHALL expose `iometrics.p99_duration_millis` measuring 99th percentile processing time.
- The system SHALL expose `iometrics.total_requests` measuring total sent/received request count.
- The system SHALL expose `iometrics.failed_requests` measuring failed request count, with a `failure_reason` dimension classifying retryability.
- The system SHALL expose `iometrics.endpoints_healthy_percentage` measuring load-balanced endpoint health ratio.
- The system SHALL expose `iometrics.ingest_bps_active` and `iometrics.ingest_bps_closed` as ingestion rate histograms for active and closed connections respectively.
- The system SHALL expose `iometrics.consumer_lag` measuring Kafka partition offset lag.

---

### Requirement: Persistent Queue Metrics
- The system SHALL expose `pq.queue_size` measuring total bytes currently queued.
- The system SHALL expose `pq.in_bytes` and `pq.in_events` measuring bytes and events added to the queue within the time window.
- The system SHALL expose `pq.out_bytes` and `pq.out_events` measuring bytes and events flushed from the queue within the time window.
- The system SHALL support optional disk persistence for metrics with a configurable maximum (default: 64 GB).

---

### Requirement: Backpressure and Blocked Output Metrics
- The system SHALL expose `backpressure.outputs` indicating destinations currently under backpressure.
- The system SHALL expose `blocked.outputs` indicating destinations currently blocked.

---

### Requirement: Operational Counters
- The system SHALL expose `logged.criticals` counting critical log entries per channel.
- The system SHALL expose `logged.errors` counting error log entries per channel.
- The system SHALL expose `metrics_pool.num_metrics` counting total unique metrics in memory.
- The system SHALL expose `collector_cache.size` counting cached collector functions.
- The system SHALL expose `shutdown.lost_events` counting events dropped during worker process shutdown.

---

### Requirement: Monitoring Dashboard UI
- The system SHALL provide a Monitoring Overview dashboard displaying traffic metrics, event counts, byte throughput, and system resource utilization across Worker Groups and individual Workers.
- The system SHALL provide a Data submenu with throughput metrics isolated for Sources, Destinations, Pipelines, Routes, Packs, Projects, Data Fields, and Subscriptions.
- The system SHALL provide a System submenu with visibility into the Job Inspector (pending, in-flight, completed collection tasks), Leader nodes (HA deployments), Licensing (on-prem), and Source/Destination queue utilization.
- The system SHALL provide a Top Talkers / Reports view that ranks the five highest-volume Sources, Destinations, Pipelines, Routes, and Packs by events throughput.
- The system SHALL provide a Flows view with a graphical left-to-right visualization of data flowing through the deployment.
- The system SHALL support a global time range selector (5 minutes to 1 day, or @midnight).
- The system SHALL support per-chart local time range pickers independent of the global setting.
- The system SHALL display configuration change markers as vertical lines on monitoring charts.

---

### Requirement: Data Volume and Reduction Tracking
- The system SHALL track events in/out and bytes in/out per source, destination, pipeline, and route to enable calculation of reduction ratios.
- The system SHALL track uncompressed data amounts in throughput metrics.
- The system SHALL provide a Data Fields view that tracks event cardinality and identifies high-cardinality fields.
- The system SHALL support a configurable blocklist of fields excluded from field-level metrics (default blocklist: host, source, sourcetype, index, project).

---

### Requirement: Health Check Endpoints
- The system SHALL expose a `/health` HTTP endpoint on each instance for load balancer integration and operational health checks.
- The system SHALL expose source-level health check endpoints at `http(s)://<hostName>:<port>/cribl_health` for HTTP-based sources.

---

### Requirement: Alerting and Notifications
- The system SHALL support notifications for source conditions: High Data Volume, Low Data Volume, No Data Received, and Source Persistent Queue Usage.
- The system SHALL support notifications for destination conditions: Destination Backpressure Activated, Persistent Queue Usage, and Unhealthy Destination.
- The system SHALL support notifications for Licensing conditions: pending license expiration.
- The system SHALL deliver notifications through Internal Logs (stored in `notifications.log` on the Leader Node).
- The system SHALL display notifications as UI Events in the Monitoring dashboard.
- The system SHALL support external notification targets: Email, Slack, PagerDuty, AWS SNS, and Webhook endpoints.
- The system SHALL support configurable time windows and thresholds for notification trigger conditions (seconds, minutes, hours; KB, MB, GB for data volumes).
- The system SHALL detect backpressure at a threshold of 5% or greater of the trailing window.
- The system SHALL support dual notifications marking both condition onset (start) and condition resolution.
- The system SHALL support custom metadata as user-defined key-value fields in notification payloads.
- The system SHALL enforce RBAC (role-based access control) for notification visibility and configuration permissions.
- The system SHALL manage notifications at the Worker Group level.
- The system SHALL NOT replicate associated notifications when cloning Sources or Destinations.

---

### Requirement: Internal Log Management
- The system SHALL provide a built-in log viewer with searchable events across all system components.
- The system SHALL support configurable log levels per integration: critical, error, warn, info (default), debug, and silly.
- The system SHALL store API Server logs in `$CRIBL_HOME/log/`.
- The system SHALL store Worker Node Process logs in `$CRIBL_HOME/log/worker/<N>/`.
- The system SHALL store Worker Group logs in `$CRIBL_HOME/log/group/<GROUPNAME>/`.
- The system SHALL store Service Process logs in `$CRIBL_HOME/log/service/<serviceName>/`.
- The system SHALL store stderr-based logs in `cribl_stderr.log`.
- The system SHALL support log search via JavaScript expression filtering.
- The system SHALL support field-level interaction in log search (add, exclude, copy).
- The system SHALL support time range selection, export to JSON, recent query history, and typeahead autocompletion in the log viewer.

---

### Requirement: Cribl Internal Source for External Forwarding
- The system SHALL provide a `CriblLogs` internal source that captures internal logs for routing through pipelines and destinations.
- The system SHALL provide a `CriblMetrics` internal source that captures internal metrics for routing through pipelines and destinations.
- The system SHALL tag all internal events with `source="cribl"` and `host=<instance hostname>`.
- The system SHALL duplicate the `source` and `host` fields into `event_source` and `event_host` fields to prevent downstream systems from overwriting original values.
- The system SHALL provide a built-in `cribl_metrics_rollup` pipeline for aggregating metrics at a configurable reporting interval (default: 30 seconds) to reduce data volume.
- The system SHALL support a Full Fidelity toggle on the CriblMetrics source to optionally exclude field-level metrics for CPU reduction.
- The system SHALL limit CriblLogs in distributed mode to Worker Process logs only; Leader logs SHALL remain local.
- The system SHALL exclude API Process logs from the CriblLogs source.

---

### Requirement: Prometheus Integration
- The system SHALL provide a Prometheus destination that exports metrics via the Prometheus remote_write specification.
- The system SHALL automatically protobuf-encode and snappy-compress payloads per the Prometheus remote_write spec.
- The system SHALL by default rename metric names by replacing dot characters (`.`) with underscores (`_`) for Prometheus compatibility, with the renaming expression being customizable via JavaScript.
- The system SHALL require events to contain the internal field `__criblMetrics` for Prometheus export; events without this field SHALL be automatically dropped.
- The system SHALL support configurable request concurrency (1-32 connections, default: 5), body size limit (default: 4096 KB), and request timeout (default: 30 seconds).
- The system SHALL support automatic exponential backoff retry logic for failed Prometheus write requests.
- The system SHALL support persistent queues on the Prometheus destination for buffering during outages.
- The system SHALL support DNS round-robin, connection pooling with automatic refresh, and metadata transmission (type and metric family names) for the Prometheus destination.
- The system SHALL support multiple authentication methods for Prometheus: None, HTTP token/bearer, Basic (username/password), and stored secrets.

---

### Requirement: System Fields on Processed Events
- The system SHALL automatically add system fields to processed events including `cribl_pipe` (pipeline ID), `cribl_host` (processing node), `cribl_input` (source ID), `cribl_output` (destination ID), `cribl_route` (route/QuickConnect ID), and `cribl_wp` (Worker Process ID) for traceability and monitoring.

---

### Requirement: Monitoring Data Lifecycle
- The system SHALL NOT persist monitoring data across Cribl Stream restarts.
- The system SHALL update metrics at 2-second intervals.
- The system SHALL update internal logs at 1-minute granularity.
- The system SHALL acknowledge that CriblLogs may fail to reflect Worker Process crashes or restarts due to the difference between log granularity (1 minute) and metric update frequency (2 seconds).
