## Compressr Operational Review -- Production Readiness Assessment

### Executive Summary

Compressr is in the design/spec phase with a freshly scaffolded Phoenix application. The architecture specs are thoughtful -- the BEAM peer clustering model, source-side buffering with end-to-end ACKs, and the consistent hash ring for destination ownership are all sound choices. But there is almost no operational infrastructure designed yet. The specs focus heavily on the data plane (sources, destinations, routes, pipelines) and barely touch the operational plane (metrics, tracing, alerting, capacity signals, upgrade coordination). This is the gap that will determine whether compressr is a weekend project or a production system.

What follows is a practical assessment organized by operational concern.

---

### 1. Observability of the System Itself

**Current state:** The health check spec (`/health`, `/ready`) is the only operational observability designed. The telemetry module at `/Users/mlapping/workspace/compressr/lib/compressr_web/telemetry.ex` is Phoenix's stock boilerplate -- VM memory, run queue lengths, and HTTP request durations. There is no spec for internal metrics emission, no OTEL integration, and no plan for how operators monitor compressr itself.

**What is needed:**

The Cribl monitoring research at `/Users/mlapping/workspace/compressr/research/cribl-stream/monitoring-metrics.md` catalogs an extensive metrics surface. Compressr does not need all of it on day one, but it needs a telemetry foundation from the start because retrofitting metrics into a data pipeline is extremely painful.

**Required metrics categories (priority order):**

1. **Throughput counters** -- `compressr.events.in` / `compressr.events.out` / `compressr.bytes.in` / `compressr.bytes.out`, labeled by source_id, destination_id, pipeline_id, node. These are the single most important metrics. Without them, you are flying blind.

2. **Buffer metrics** -- `compressr.buffer.bytes` / `compressr.buffer.events` / `compressr.buffer.capacity_pct`, labeled by destination_id and node. Operators need to know when buffer fill rate exceeds drain rate.

3. **Backpressure indicators** -- `compressr.backpressure.active` (gauge per destination), `compressr.events.dropped` (counter per destination). These are the leading indicators of trouble.

4. **Cluster health** -- `compressr.cluster.peers` (gauge), `compressr.hash_ring.rebalances` (counter), `compressr.destination.owner_changes` (counter). Hash ring churn is a signal that something is wrong.

5. **Latency histograms** -- `compressr.pipeline.duration_ms` (histogram per pipeline), `compressr.destination.flush_duration_ms` (histogram per destination). P50/P95/P99 tell you when degradation starts before it becomes an outage.

6. **BEAM-specific** -- scheduler utilization (not just run queue length), process count, atom table usage, binary memory. The BEAM has specific failure modes (atom table exhaustion, binary memory leaks from refc binaries) that generic metrics miss.

**OTEL integration recommendation:** Use `opentelemetry_api` and `opentelemetry` Erlang/Elixir packages. Emit metrics via the OTEL metrics SDK and traces via the OTEL trace SDK. Export via OTLP (gRPC or HTTP) to whatever the operator runs -- Prometheus, Grafana, Datadog, etc. This is the correct abstraction because the target market (SMBs) will have wildly different monitoring stacks. OTEL gives you one emission path and lets the operator choose the backend.

The `telemetry` library already in the dependency tree is the right hook point. Define `:telemetry.execute/3` events throughout the data path, then bridge them to OTEL via `opentelemetry_telemetry`. This means the data plane code emits telemetry events, and the export mechanism is pluggable.

**Critical gap:** There is no spec for a "CriblMetrics"-equivalent internal source. Compressr should dogfood its own metrics -- route internal telemetry through its own pipeline engine so operators can send compressr metrics to the same destinations as their application data. This is table stakes for an observability pipeline.

---

### 2. Failure Modes and Blast Radius

The architecture decisions in `project.md` describe the happy path well. Here is what the specs do not address:

**Node death during active processing:**
- Source node dies while holding unACKed events: Events are lost. The spec says "source nodes hold processed events until destination node confirms durable receipt," but if the source node dies, those in-memory events are gone. The buffer is local disk, which helps for destination outages but not for source node crashes.
- Blast radius: All events in the dead node's source pipeline that have not been ACKed by a destination owner. If this node was processing 200 GB/day, you lose whatever is in-flight (seconds to minutes of data depending on batch sizes and flush intervals).
- Mitigation gap: No spec for WAL (write-ahead log) on source nodes before pipeline processing. Events arrive over the network, get processed, then get buffered. The gap between "received" and "durably buffered post-pipeline" is a data loss window.

**Destination owner node dies during destination outage (double fault):**
- The spec explicitly accepts this risk: "Events that were ACKed by the failed node but not yet flushed to the sink are lost if the node's disk is unrecoverable." This is reasonable for the SMB market, but the spec should quantify the exposure window. How many seconds of data typically sit in the destination node's buffer? If flush intervals are 1 second and batch sizes are 4MB, the exposure is small. If flush intervals are 60 seconds, it is significant.

**Hash ring rebalancing storms:**
- Adding or removing a node triggers rebalancing. If nodes are flapping (joining and leaving rapidly due to health check misconfiguration, OOM kills, etc.), the ring churns continuously. Every rebalance means destination ownership changes, which means source nodes need to redirect traffic.
- Missing: Circuit breaker on rebalancing. If the ring has changed N times in M seconds, stop accepting changes and alert. Flapping is a well-known failure mode in consistent hashing systems.

**DynamoDB dependency:**
- All config is in DynamoDB. If DynamoDB is unreachable at boot, no sources or destinations start. If it becomes unreachable at runtime, config changes fail but running processes should continue.
- Missing: Local config cache. Nodes should cache their last-known-good config to disk so they can cold-start without DynamoDB (degraded mode, read-only config). This is critical for the "sleep at night" requirement.

**Split brain in Erlang distribution:**
- The specs mention Erlang distribution for clustering but do not address network partitions. If the cluster splits into two halves, both halves compute different hash rings. Both halves think they own destinations. You get duplicate writes to external systems.
- Missing: Partition detection and response strategy. Options: (a) use a quorum system -- nodes that cannot see a majority of peers stop accepting writes, (b) use CRDTs for state that must converge eventually, (c) accept split-brain as a risk and document it. The project mentions "CRDT-based state where needed" but does not specify what state uses CRDTs.

**Expression language compilation errors at runtime:**
- The spec says expressions compile at config save time. Good. But what about expressions that compile successfully but fail at runtime due to unexpected event shapes (missing fields, wrong types)?
- Missing: Per-function error counters and configurable error handling (drop event, pass through unchanged, route to error destination). Without this, a single malformed event can cause cascading failures if the pipeline function crashes and the supervisor restarts it in a hot loop.

---

### 3. Operational Runbooks Needed

These are the day-2 operations that every operator will need documentation for:

**Scaling up (adding nodes):**
- How does a new node join the cluster? DNS-based discovery (dns_cluster is already a dependency), environment variable, config file?
- What happens to in-flight events during rebalancing?
- How long does rebalancing take? Is there a warm-up period?
- Can you add nodes without any downtime?

**Scaling down (removing nodes):**
- Is there a graceful drain procedure? The node should stop accepting new source connections, drain its buffers, hand off destination ownership, then leave the cluster.
- What is the drain timeout? What happens if it cannot drain in time?
- Missing: `compressr.drain` CLI command or API endpoint that initiates graceful shutdown.

**Rolling upgrades:**
- The spec mentions BEAM hot code loading but does not specify how it will work in practice. Hot code loading in production BEAM systems is notoriously tricky -- it works for simple module replacements but not for supervision tree changes, state format changes, or dependency upgrades.
- Practical recommendation: Do not rely on hot code loading for version upgrades. Use rolling restart: drain node, stop node, upgrade, start node, wait for ready, move to next. This is what every production BEAM system I have operated actually does.
- Missing: Version negotiation protocol. When two nodes at different versions are in the same cluster, what protocol version do they speak? This needs to be defined before the first multi-node deployment.

**Config changes:**
- Config is in DynamoDB. When a config change is made, how does it propagate to running nodes? Push (DynamoDB Streams) or poll? What is the convergence time?
- Missing: Config change event system. Nodes should emit a metric and log entry when they pick up a config change. Operators need to verify that all nodes are running the same config version.

**Buffer management:**
- When a destination has been down for hours and buffers are filling up, what can the operator do?
- Missing: Buffer inspection CLI/API (list buffers, show fill percentage, show oldest event timestamp), manual buffer drain/purge, buffer export to S3 for later replay.

**Emergency procedures:**
- How do you kill a runaway pipeline that is consuming 100% CPU due to a bad regex?
- How do you disable a source that is being flooded without restarting the node?
- Missing: Runtime circuit breakers accessible via API or remote Erlang console.

---

### 4. Alerting Thresholds

**Critical (page someone, wake them up):**
- Buffer fill > 80% on any destination (you have ~30 minutes before data loss at typical fill rates)
- All nodes for a destination are down (no owner in the hash ring)
- Events dropped > 0 for destinations in "block" backpressure mode (should never happen, means the blocking mechanism failed)
- Node count drops below quorum (if quorum is implemented)
- DynamoDB unreachable for > 5 minutes (config changes and new source/destination creation blocked)
- BEAM memory > 90% of configured limit (OOM kill imminent)

**Warning (investigate within an hour):**
- Buffer fill > 50% on any destination
- Destination health status "unhealthy" for > 5 minutes
- Hash ring rebalances > 3 in 10 minutes (flapping)
- Event processing latency P99 > 2x baseline
- Source connection rejections > 0
- Scheduler utilization > 80% sustained for 5 minutes
- Events dropped in "drop" backpressure mode (expected but needs visibility)

**Info (review during business hours):**
- Node joined or left cluster
- Config change applied
- Destination recovered from unhealthy
- Buffer drained to 0 after backpressure event
- Source enabled/disabled

**Missing from the spec:** The entire alerting subsystem. The Cribl research doc shows Cribl supports notifications via Email, Slack, PagerDuty, AWS SNS, and Webhooks. Compressr needs at minimum OTEL-compatible alerting (emit metrics, let the operator's monitoring system handle alerting rules) and ideally a built-in notification system for operators who do not have Grafana/PagerDuty.

---

### 5. Graceful Degradation

**Concern: The system appears to cliff rather than degrade.**

The backpressure spec defines three modes: block, drop, queue. "Block" propagates pressure upstream, which means the source stops accepting data. For a syslog source over UDP, "block" means packets are silently dropped by the kernel. For TCP sources, connections stall and the sender's buffer fills up. This is correct behavior but operators need to understand the implications.

**What is missing for graceful degradation:**

- **Priority-based shedding:** The buffer QoS spec mentions priority allocation, but the route/pipeline specs do not. When the system is overloaded, which events get processed first? There is no concept of event priority in the pipeline. A "drop low-priority events under load" capability is essential.

- **Admission control:** No spec for rate limiting at sources. If a source is receiving 10x expected volume (log storm, misconfigured application), the system should be able to throttle at ingestion rather than propagating the overload through the entire pipeline.

- **Partial destination failure:** If one of several Elasticsearch nodes behind a load balancer is slow, the retry-with-backoff behavior can cause head-of-line blocking for the entire destination. Missing: connection-level health checking and circuit breaking for individual endpoints within a destination.

- **Degraded mode operation:** No spec for what happens when the system is overloaded but still functional. Can it shed non-essential work (metrics collection, UI responsiveness) to preserve data path throughput? The BEAM's scheduler is good at this naturally, but explicit priority should be given to data path processes over UI/API processes.

---

### 6. Deployment Model

**Current state:** No deployment spec exists.

**Recommendations by platform:**

**Docker (single node, SMB starting point):**
- `docker run -p 9000:9000 -v /data/compressr:/var/lib/compressr compressr` should work out of the box
- The volume mount is critical -- buffer data must survive container restarts
- Health check: `HEALTHCHECK CMD curl -f http://localhost:9000/health || exit 1`
- DynamoDB: Offer DynamoDB Local as a sidecar for true single-node operation, or support an embedded alternative (SQLite for config) so the SMB operator does not need an AWS account just to evaluate

**ECS (AWS-first, primary target):**
- Service discovery via AWS Cloud Map for Erlang clustering
- ECS service with ALB, health check on `/ready` (not `/health` -- you want the ALB to wait until the node is fully initialized)
- Task placement: spread across AZs
- Buffer storage: EBS volume or instance store. Instance store is faster but ephemeral. EBS survives task restarts but adds latency. For the SMB market, EBS is the right default (data durability over performance).
- Auto-scaling: Scale on CPU or custom metric (buffer fill percentage). NOT on event count -- event count spikes are normal and transient.

**Kubernetes:**
- StatefulSet (not Deployment) because nodes need stable identities for Erlang clustering and persistent buffer storage
- Headless service for Erlang node discovery (DNS-based, which is already supported via `dns_cluster`)
- PersistentVolumeClaims for buffer storage
- Readiness probe on `/ready`, liveness probe on `/health`
- PodDisruptionBudget to prevent draining too many nodes simultaneously during cluster maintenance
- Anti-affinity rules to spread pods across nodes/AZs

**Clustering concern for all platforms:** The Erlang distribution protocol requires nodes to be able to reach each other by hostname. This is straightforward in Kubernetes (headless service) and ECS (Cloud Map) but needs explicit documentation. The `dns_cluster` dependency handles discovery, but operators need to set the Erlang cookie, configure the node name format (`compressr@<ip>` vs `compressr@<hostname>`), and understand the EPMD (Erlang Port Mapper Daemon) port requirements (4369 + dynamic range).

---

### 7. Debugging and Troubleshooting

**What the BEAM gives you for free:**
- Remote console attachment (`:observer.start()`, `IEx.pry`)
- Process inspection (`:process_info`, `:sys.get_state`)
- Message queue depth inspection (detect mailbox buildup)
- ETS table inspection
- Distribution connection status (`:net_kernel.nodes()`)
- Recon library for production debugging without restart

**What is missing from the spec:**

- **Structured logging:** No logging spec at all. The system needs structured JSON logging with correlation IDs that flow through the entire event lifecycle (source -> pipeline -> route -> destination). When an event is dropped or errored, the operator needs to trace it back to the source.

- **Event sampling/capture:** For debugging pipeline logic, operators need to capture a sample of events at each pipeline stage. Cribl has a "capture" mode for this. Compressr needs an equivalent: "show me 10 events entering this pipeline and 10 events exiting it."

- **Distributed tracing:** When a source node processes an event and sends it to a destination owner on a different node, OTEL traces should follow the event across nodes. This requires propagating trace context through the inter-node message passing.

- **Dead letter queue:** When an event fails processing (expression error, serialization failure, destination rejection), where does it go? Currently, the specs only define "drop" as a function. There is no error destination. Failed events should be capturable for inspection.

- **Diagnostic endpoint:** A `/diag` or `/debug` endpoint (authenticated) that dumps: current hash ring state, buffer fill levels per destination, connected peers, process counts, memory breakdown, scheduler utilization. This is the "one curl command that tells me if the system is healthy" endpoint.

---

### 8. Upgrade Path

**BEAM hot code loading reality check:**

The project.md mentions BEAM hot code loading as a potential upgrade mechanism. In my experience operating BEAM systems at scale, hot code loading works for:
- Bug fixes in stateless modules
- Expression language updates
- Pipeline function logic changes

Hot code loading does NOT work well for:
- Supervision tree restructuring
- State format changes in GenServers (requires state migration callbacks)
- Dependency (Hex package) upgrades
- NIF (RocksDB/SQLite) upgrades

**Practical upgrade strategy recommendation:**

1. Rolling restart is the primary upgrade mechanism. Drain node, stop, replace binary, start, verify ready.
2. Hot code loading is a bonus for pipeline function updates and expression language changes (fast iteration without restart).
3. Version compatibility matrix: define which versions can coexist in a cluster. At minimum, N and N-1 minor versions.
4. State migration: every GenServer that holds state needs a `code_change/3` callback or the state format needs to be versioned.
5. Feature flags: new features should be behind flags so nodes at different versions can coexist safely.

**Missing:** The entire upgrade orchestration system. Who decides the order of rolling restarts? In Cribl, the leader orchestrates. In a peer cluster, you need either an external orchestrator (Kubernetes rolling update, ECS rolling deployment) or a protocol where nodes negotiate upgrade order. For the SMB market, lean on the deployment platform (K8s/ECS) for this.

---

### 9. Capacity Planning

**Leading indicators that you need more nodes:**

1. **Scheduler utilization > 70% sustained** -- the BEAM is running out of CPU. This is the most reliable leading indicator.
2. **Buffer fill rate exceeding drain rate** -- buffers are growing even when destinations are healthy. The node cannot keep up with processing volume.
3. **Pipeline latency P95 increasing** -- events are waiting longer in process mailboxes before being processed.
4. **Run queue length > 2x scheduler count** -- processes are queuing for CPU time.
5. **Memory growth trend** -- if memory usage trends upward over hours (not just GC sawtooth), binary memory or process accumulation is happening.

**What operators need:**

- A dashboard or API endpoint that shows events/second per node vs. capacity
- A formula: "this node type handles approximately X GB/day" (like Cribl's ~200 GB/day per vCPU)
- Buffer headroom: "at current ingest rate, buffer will be full in Y hours if destination goes down"
- A recommendation engine: "based on current throughput trends, add a node within N days"

**Missing from spec:** All of it. There is no capacity planning guidance, no sizing recommendations, no benchmark framework. Before the first production deployment, compressr needs benchmark numbers on representative hardware (c6g.xlarge, c6g.2xlarge) with representative workloads (syslog at 10K EPS, HEC at 50K EPS, S3 collection at 1 TB).

---

### 10. Prioritized Recommendations for Production Readiness

**P0 -- Must have before any production deployment:**

1. **Telemetry foundation.** Add `opentelemetry` + `opentelemetry_api` + OTLP exporter. Instrument the data path: events in, events out, bytes in, bytes out, pipeline latency, buffer depth. Without this, you are shipping a black box.

2. **Structured logging with correlation IDs.** Every event should carry a trace ID from ingestion to delivery. Every log line should be structured JSON. Use Elixir's Logger with a JSON formatter.

3. **Buffer metrics and inspection API.** Operators must be able to answer "how full are my buffers" and "how long until they overflow" without SSHing into the box.

4. **Local config cache.** Nodes must be able to start with stale config if DynamoDB is unreachable. The first time an SMB operator's node reboots during an AWS regional hiccup and comes up with zero sources running, they will abandon the project.

5. **Graceful drain on shutdown.** `SIGTERM` should trigger: stop accepting new connections, drain in-flight events, flush buffers, leave cluster cleanly. This is required for rolling upgrades on any platform.

6. **Split brain strategy.** Decide how network partitions are handled and document it. Even if the answer is "we accept split brain and deduplicate downstream," it needs to be an explicit decision, not an unexamined failure mode.

**P1 -- Must have within the first quarter of production use:**

7. **Dead letter destination.** Failed events need somewhere to go that is inspectable. Route processing errors to an S3 prefix or a dedicated DynamoDB table with the original event, the error, and the pipeline stage where it failed.

8. **Rate limiting / admission control at sources.** A single misconfigured application sending 100x normal volume should not take down the entire cluster.

9. **Event sampling/capture for debugging.** "Show me what events look like at this stage of the pipeline" is the number one debugging operation for pipeline operators.

10. **Deployment guides** for Docker, ECS, and Kubernetes with Terraform/Helm examples. The SMB operator who is not an SRE needs copy-paste deployment artifacts.

11. **Internal metrics as a source** (dogfooding). Compressr's own metrics should be routable through its own pipelines and sendable to its own destinations. This is both a feature (operators can send compressr metrics to their existing monitoring) and a proof point (if you cannot monitor yourself with yourself, something is wrong).

**P2 -- Important for long-term operational maturity:**

12. **Benchmark suite and sizing guide.** "How many events/second can a c6g.xlarge handle?" needs a real answer backed by repeatable benchmarks.

13. **Hash ring rebalance circuit breaker.** Prevent flapping from causing continuous rebalancing storms.

14. **Config version tracking and convergence metrics.** "All N nodes are running config version X" needs to be visible.

15. **Notification/alerting subsystem.** Even a simple webhook-based alerting system (buffer > 80%, destination unhealthy for > 5 min) is vastly better than requiring operators to set up external monitoring from day one.

16. **Operational CLI tool.** `compressr status`, `compressr drain`, `compressr ring` (show hash ring), `compressr buffer list`, `compressr config version`. The BEAM remote console is powerful but intimidating for operators who are not Erlang developers.

---

### Final Assessment

The architecture is sound. The BEAM peer cluster model eliminates Cribl's biggest operational headache (leader HA), and the source-side buffering with end-to-end ACKs is the right durability model. The choice to avoid per-message cloud services in the hot path is essential for the target market.

But the specs are almost entirely focused on the data plane. The operational plane -- how do you run this thing, monitor it, debug it, upgrade it, scale it -- is largely unspecified. For an observability pipeline, this is an existential gap. An observability tool that cannot be observed is a contradiction.

The single most important next step is the telemetry foundation (recommendation number 1). Everything else -- alerting, capacity planning, debugging -- depends on having metrics and traces flowing out of the system. Without that, every 3 AM page becomes an SSH-and-pray session, and the SMB operator who chose compressr to save money will switch to something else because the operational cost exceeds the licensing savings.
