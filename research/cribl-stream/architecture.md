## Architecture Overview

Cribl Stream uses a **Leader/Worker** distributed architecture. The Leader is a centralized management node that handles configuration authoring, deployment, and operational monitoring. Worker Nodes handle all data processing (receiving, transforming, routing events). Workers are organized into **Worker Groups** -- logical collections sharing identical configuration. In single-instance mode, leader and worker functionality are collapsed into one process.

Communication flows via TCP port 4200: workers send heartbeats every 10 seconds containing hostname, IP, GUID, tags, environment variables, and software/config versions. If a worker misses two consecutive heartbeats, the leader removes it from active tracking. Workers pull configuration bundles from the leader over HTTPS on the same port. The leader UI listens on TCP 9000.

Critically, **if the leader goes down, workers continue processing data autonomously** from most sources. However, scheduled collection jobs fail and specific sources (Kinesis, Prometheus Scraper, Office 365) stop because they depend on leader-coordinated scheduling.

---

### Requirement: Centralized Configuration Management

- **What Cribl does:** The Leader node authors, validates, and deploys configuration to Worker Groups. All config changes must be committed before deployment. Workers cannot persist local config changes -- permanent changes require commit-and-deploy from the leader. Each Worker Group maintains separate config (routes, pipelines, sources, destinations, version control).
- **Why it matters:** Ensures consistency across fleet. Prevents config drift. Enables atomic rollouts to groups of workers.
- **The system SHALL** provide a mechanism to author, validate, and atomically distribute configuration to groups of peer nodes, ensuring all nodes in a group converge on identical configuration without a single leader bottleneck.

### Requirement: Worker Groups (Fleet Segmentation)

- **What Cribl does:** Worker Groups are collections of workers sharing identical configuration. Organizations create groups for organizational or geographic reasons (e.g., US, APAC, EMEA). Each group has independent routes, pipelines, sources, destinations, and version control. Groups can be cloned, deleted, and restored.
- **Why it matters:** Allows different processing logic for different data streams, regions, or tenants without running separate clusters.
- **The system SHALL** support logical groupings of nodes that share configuration, allowing different processing pipelines per group while remaining part of the same cluster.

### Requirement: Worker-to-Group Mapping

- **What Cribl does:** Mapping Rulesets use JavaScript filter expressions evaluated against worker metadata (IP, CPU count, tags, environment variables) to assign workers to groups. First-match wins. Only one ruleset is active. Fallback hierarchy: mapping rule match, then worker-specified group, then default group.
- **Why it matters:** Enables automatic fleet organization based on node characteristics without manual assignment.
- **The system SHALL** support rule-based automatic assignment of nodes to configuration groups based on node metadata, tags, and attributes.

### Requirement: Git-Based Configuration Versioning

- **What Cribl does:** Git is mandatory (v1.8.3.1+). All configuration is stored in Git. The leader maintains a local Git repo. Changes are committed then deployed. GitOps mode enables external Git repo integration with branch-based promotion (dev branch -> PR -> prod branch). Production leaders can be read-only, syncing via `/version/sync` API endpoint. Config stored in `/groups/<group_name>/local/cribl/` directory structure.
- **Why it matters:** Provides audit trail, rollback capability, and CI/CD integration for infrastructure-as-code workflows.
- **The system SHALL** store all configuration in a version-controlled format with full history, support rollback to any prior version, and integrate with external Git repositories for CI/CD workflows.

### Requirement: Distributed Deployment with Horizontal Scaling

- **What Cribl does:** Horizontal scaling adds Worker Nodes to groups. Each worker runs multiple Worker Processes (default: CPU count minus 2). Data on a single connection is handled by a single Worker Process (shared-nothing). Each process maintains independent output connections. Sizing: ~200 GB/day per vCPU (x86), ~480 GB/day per vCPU (Graviton). Minimum 4 ARM or 8 x86 vCPUs per node, max 48 vCPUs. Typical: 4-8 workers per group for 5-20 TB/day.
- **Why it matters:** Allows linear throughput scaling by adding nodes. The shared-nothing per-connection model simplifies reasoning about data flow.
- **The system SHALL** scale horizontally by adding peer nodes, with throughput growing linearly. Each node SHALL operate independently for data processing without shared state between processing paths.

### Requirement: Single-Instance Mode

- **What Cribl does:** One process handles inputs, processing, and outputs. Designed for small-volume, testing, or evaluation. No HA, no worker groups, no fleet management. All Cribl directories must reside on the same device.
- **Why it matters:** Low-barrier entry point for evaluation and small deployments.
- **The system SHALL** support a single-node deployment mode requiring no external dependencies, suitable for development, testing, and small workloads.

### Requirement: High Availability / Failover

- **What Cribl does:** Leader HA uses active/standby with shared NFS storage. Only one leader is active at a time. The primary replicates config and Git commits to a shared failover volume. On failover, the standby pulls config from NFS and all workers reconnect. Workers continue processing during leader outage (except scheduled collectors). For workers, sizing recommends 20% overhead for node downtime during patching/upgrades.
- **Why it matters:** The leader is a single point of failure for management operations. Workers are resilient by default but management plane needs HA.
- **The system SHALL** provide high availability without requiring shared storage (NFS) or active/standby coordination. In a peer cluster, any node's failure SHALL be tolerated by the remaining nodes with automatic rebalancing.

### Requirement: Upgrade and Migration

- **What Cribl does:** Upgrade order: leader first, then workers. Workers may lag one minor version behind the leader. Rolling upgrades supported with configurable batch percentage, retry delay (default 1000ms), retry count (default 5). Automatic rollback on failure: if the server fails to start or workers disconnect, rollback triggers within 30 seconds (default). Backup retention: 24 hours.
- **Why it matters:** Zero-downtime upgrades are critical for production data pipelines.
- **The system SHALL** support rolling upgrades across the cluster without data loss or downtime. Nodes SHALL tolerate version skew of at least one minor version. The system SHALL automatically roll back failed upgrades.

### Requirement: Health Checks and Monitoring

- **What Cribl does:** Exposes `/health` endpoint for load balancer integration. Source-level health at `http(s)://${hostName}:${port}/cribl_health`. Monitoring dashboards track: events in/out, bytes in/out, CPU load (1-min granularity), free memory, storage, queue utilization. Notifications for source/destination failures and license expiration. Internal searchable logs from API server and worker processes.
- **Why it matters:** External orchestrators (k8s, load balancers) need health endpoints. Operators need visibility into throughput, resource usage, and failures.
- **The system SHALL** expose health check endpoints compatible with load balancers and orchestrators. The system SHALL provide real-time monitoring of throughput, resource usage, queue depth, and error rates per node and per pipeline.

### Requirement: Internal Metrics and Telemetry

- **What Cribl does:** Generates internal metrics every 2 seconds at the Worker Process level (CriblMetrics source). Tracks in_bytes, in_events, out_bytes, out_events across dimensions: host, index, project, source, sourcetype. CriblLogs source captures internal logs at ~1-minute granularity but may miss process crashes. Metrics prefix: `cribl.logstream.*` (configurable). Leader logs are separate from worker processing logs.
- **Why it matters:** Self-monitoring is essential for observability pipelines. The system must be able to report on its own health and performance.
- **The system SHALL** generate internal metrics at sub-10-second granularity covering event throughput, byte throughput, error counts, and resource utilization. Metrics SHALL be available as a data source within the system itself (dogfooding).

### Requirement: Persistent Queuing / Disk Buffering

- **What Cribl does:** Disk-based PQ engages during backpressure events. Source PQ buffers when upstream senders exceed processing capacity. Destination PQ buffers when receivers are unreachable, slow (4.9+), or erroring. Two source modes: "Always On" (disk buffer for all events) and "Smart" (only during backpressure). Each Worker Process maintains independent queues. PQ is not infinite (bounded by disk). Not crash-safe. At-rest encryption requires volume-level config. Strict ordering option (FIFO vs. prioritize new events).
- **Why it matters:** Data pipelines must not lose data during transient destination outages. Disk buffering bridges the gap between in-memory speed and destination availability.
- **The system SHALL** support persistent disk-based queuing at both ingestion and egress points. Queues SHALL engage automatically during backpressure events. The system SHALL support configurable queue modes (always-on vs. smart engagement) and ordering guarantees (strict FIFO vs. priority for live data).

### Requirement: Backpressure Mechanisms

- **What Cribl does:** Three destination backpressure behaviors: Block (stop accepting data, propagate pressure upstream), Drop Events (discard when destination is slow), Persistent Queue (buffer to disk). For load-balanced destinations, PQ only engages when ALL receivers are blocking -- a single active connection prevents activation. Backpressure propagates from destinations back through the pipeline to sources.
- **Why it matters:** Without backpressure, the system either drops data silently or runs out of memory. Explicit backpressure modes let operators choose the tradeoff (latency vs. data loss vs. disk usage).
- **The system SHALL** implement configurable backpressure behavior per output: block (propagate upstream), drop (shed load), or buffer (persist to disk). The system SHALL propagate backpressure signals end-to-end from destinations through processing pipelines to sources.

### Requirement: Resource Management and Process Model

- **What Cribl does:** Worker Process count configurable: positive number (absolute) or negative (relative to CPUs, default -2 reserves 2 cores for overhead). Minimum 2 processes. Heap memory per process: default 2048 MB with dynamic allocation. ARM/Graviton: recommended -1 (no hyperthreading). Kubernetes: explicit values via `CRIBL_MAX_WORKERS` env var. CPU and API profiling tools built into the UI.
- **Why it matters:** Resource allocation directly impacts throughput and stability. The process-per-core model with reserved headroom prevents resource exhaustion.
- **The system SHALL** automatically configure worker processes based on available CPU resources with configurable headroom. Memory limits SHALL be enforced per process. The system SHALL expose profiling tools for diagnosing performance issues.

---

**Key takeaway for compressr:** The leader/worker split in Cribl provides four distinct capabilities that an Erlang peer cluster must replicate differently:

1. **Configuration authority** (leader is single source of truth) -- in a peer cluster, this becomes a consensus problem or Git-as-authority pattern.
2. **Fleet segmentation** (worker groups with independent configs) -- maps to node grouping with config sets distributed via cluster membership.
3. **Centralized monitoring aggregation** (leader collects all metrics) -- in a peer cluster, any node can aggregate or metrics can be queried distributedly.
4. **Upgrade orchestration** (leader-first ordering) -- in a peer cluster, rolling upgrades need coordination without a designated orchestrator, potentially using Erlang's hot code loading.
