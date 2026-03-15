# Project Context

## Purpose
Compressr is an open-source alternative to [Cribl Stream](https://cribl.io). It provides an observability data pipeline that collects, routes, reduces, enriches, and normalizes streaming data (logs, metrics, traces) between sources and destinations. The goal is to replicate Cribl Stream's core interfaces — both the web UI and the programmatic (REST/API) interface — using Cribl's public documentation as the reference for interface design and behavior.

### Key Differentiator: Object Storage Replay with Tiered Rehydration
Cribl Stream cannot natively ingest and replay data it has stored in S3 buckets. Compressr treats object storage as a first-class source, not just a destination, and provides built-in support for **asynchronous tiered-storage rehydration and replay**.

The core abstraction is an **object storage interface** with a **tiered retrieval behaviour** — any storage backend that supports non-synchronous fetch from cold/archive tiers can implement it. The system manages the full lifecycle: initiate restore → poll for availability → replay when ready. This is operationally painful enough that most teams never do it; compressr solves it once so no one has to build it again.

**First implementation**: AWS S3 with Glacier tiers (Instant, Flexible, Deep Archive). The interface design ensures future backends (Azure Blob with Cool/Archive tiers, GCS with Coldline/Archive, MinIO, etc.) can be added without changing the replay or pipeline logic.

## Tech Stack
- **Language**: Elixir
- **Web Framework**: Phoenix (LiveView for real-time UI)
- **Domain Framework**: Ash Framework (resources, APIs, authorization)
- **Runtime**: Erlang/OTP (BEAM VM — chosen specifically for native distributed clustering, concurrency, and fault tolerance; the BEAM's ability to form peer clusters of identical nodes is the architectural foundation that eliminates the need for Cribl's leader/worker topology)
- **Database**: DynamoDB (key-value store — no relational database; fits AWS-first strategy and avoids pushing a relational model on a pipeline tool)
- **AWS SDK**: ex_aws / ex_aws_dynamo
- **Build Tool**: Mix
- **Package Manager**: Hex

## Project Conventions

### Code Style
- Follow standard Elixir conventions and `mix format` for formatting
- Use Ash resources for domain modeling where applicable
- Phoenix contexts for bounded domain logic
- Prefer pattern matching and pipeline operators (`|>`) over nested calls

### Architecture Patterns
- **Ash Resources** for data modeling, CRUD, and API generation
- **Phoenix LiveView** for real-time web UI — strongly preferred, no separate frontend framework
- **OTP distributed clustering** instead of leader/worker architecture — all nodes are peers that coordinate via Erlang distribution, pg (process groups), and CRDT-based state where needed. No special "leader" or "worker" roles; any node can do any work. The cluster self-organizes to find the most efficient path to completing a task
- **GenServers / Supervisors** for stream processing pipelines and fault-tolerant worker management
- **Cribl-compatible API surface** — mirror Cribl Stream's REST API paths and payloads where practical, to ease migration
- Reference Cribl Stream's public documentation (docs.cribl.io) to extract and replicate interface contracts
- **Behaviour-based abstractions** for pluggable backends — object storage and tiered retrieval are defined as Elixir behaviours so implementations are swappable (e.g., S3 today, Azure Blob or GCS tomorrow)

### Testing Strategy
- ExUnit for all tests
- Test Ash resources and actions in isolation
- Integration tests for API endpoints
- Property-based testing (StreamData) for stream processing logic where appropriate

### Git Workflow
- Feature branches from `main` with descriptive names (e.g., `feature/add-pipeline-routes`, `fix/source-auth`)
- All changes require PRs with descriptive bodies before merge
- Conventional commit messages with detailed explanations
- Enable auto-merge with squash for PRs

## Domain Context
Cribl Stream is an observability pipeline product. Key domain concepts include:

- **Sources**: Ingest points for data (e.g., Syslog, HTTP, Kafka, Splunk HEC, file monitors)
- **Destinations**: Output targets for processed data (e.g., S3, Splunk, Elasticsearch, SIEM tools)
- **Routes**: Rules that direct data from sources through processing pipelines to destinations
- **Pipelines**: Ordered sequences of processing functions applied to events
- **Functions**: Individual transformations within a pipeline (e.g., regex extract, drop, mask, eval, aggregation)
- **Packs**: Packaged, shareable configurations (pipelines, routes, functions)
- **Cluster Nodes**: Processing nodes that are all equal peers — no leader/worker distinction. Nodes coordinate via Erlang distribution to share work and find optimal processing paths. This is a deliberate departure from Cribl Stream's leader/worker model, which adds unnecessary operational complexity
- **Events**: Individual data records flowing through the system (typically log lines, metrics, or traces)
- **Replay**: Re-ingesting historical data from object storage back through pipelines — treating stored data as a source
- **Object Storage**: Any blob/object storage backend (S3, Azure Blob, GCS, MinIO, etc.) — compressr defines a behaviour interface, not a hard dependency on any one provider
- **Storage Tiers**: Many object stores have cold/archive tiers where retrieval is asynchronous (request restore, wait, then fetch). Compressr abstracts this as a tiered retrieval behaviour: initiate restore → poll status → replay when ready. First implementation: AWS S3 Glacier tiers

The programmatic interface (REST API) is a first-class citizen — compressr should be fully configurable and operable via API, not just the UI.

## Target Market
Small and medium businesses (0–10 TB/day ingest, scaling to 50 TB/day) that are being priced out of the observability market. Splunk, Datadog, and Cribl itself charge per-GB or per-TB fees that make log management prohibitively expensive for these organizations. Compressr is open source and free — the goal is to eliminate the pipeline tax on companies that just want to control where their data goes.

Key implications for design:
- **Single-node must be exceptional**: Most SMBs start with one box. `docker run compressr` should handle 500 GB–1 TB/day with zero external dependencies beyond DynamoDB (free tier).
- **Growth path must be invisible**: Adding a second node should just work — no migration, no re-architecture, no mode switch.
- **No per-message costs in the hot path**: Event buffering must use local disk (not SQS or similar pay-per-message services) to avoid recreating the cost problem we're solving.
- **Glacier replay is the killer feature for this market**: SMBs store logs in S3/Glacier because they can't afford hot storage. Compressr makes that data accessible again without custom tooling.

## Important Constraints
- Must be open source
- **AWS-first**: Optimize for AWS deployment and AWS-native services (S3, Glacier, SQS, Kinesis, CloudWatch, etc.) as the primary target environment
- Interface design (API paths, payloads, UI workflows) should closely follow Cribl Stream's documented interfaces to enable easier adoption and migration
- Compressr is NOT affiliated with Cribl — it is an independent, clean-room implementation based on public documentation only

## Early Priorities
- **OpenID Connect (OIDC) authentication**: Integrate OIDC as the primary auth mechanism as early as possible. Users should be able to authenticate via any OIDC provider (Okta, Auth0, AWS Cognito, Azure AD, Google, etc.) from the start rather than bolting it on later. Google OAuth as a built-in fallback provider — most orgs have Google accounts, so it serves as a sensible default for teams that haven't set up a dedicated IdP.

## Architecture Decisions

### Cluster Data Flow Model
- **Process at source**: Events are ingested and processed (pipeline) on the source node to reduce volume before forwarding
- **Destination ownership**: Each destination instance is owned by exactly one node at a time via consistent hash ring
- **End-to-end acknowledgment**: Source node holds events until destination node confirms durable receipt; destination node disk-buffers before ACKing
- **Consistent hash ring**: Sources and destinations are assigned to nodes via hash ring; adding/removing nodes triggers automatic rebalancing
- **Node failure recovery**: If a destination node dies, the ring reassigns ownership and the source node retries to the new owner (it still has the unACKed events)

### Event Buffering Strategy
- **Post-pipeline events are mutated** — data for one destination cannot be reconstructed from an archive that went through a different pipeline. The buffer must hold the exact post-pipeline data per destination.
- **Source nodes buffer, not destination nodes** — source nodes hold processed events until the destination-owning node ACKs. If the destination is unavailable, source nodes write undeliverable events to local disk, tagged by destination ID.
- **Destination node ACKs only after durable write** — the destination-owning node writes to its local buffer before ACKing the source. This ensures the source retains events until they're durably stored somewhere.
- **Buffer QoS / priority allocation** — each destination gets a configurable priority (integer) and buffer reservation (percentage of available disk). Reservations are guaranteed minimums, not caps. Unreserved space is shared, highest priority first. When capacity is reached, lowest-priority destinations get backpressured or dropped first. Example: CloudTrail at 50% priority, app logs at 20%.
- **Buffer is behind a `Compressr.Buffer` behaviour** — implementation TBD (RocksDB or SQLite, to be decided by benchmarking). No SQS or pay-per-message services in the hot path. Zero marginal cost. RocksDB's sorted keys enable efficient ordered drain.
- **Buffer sizing**: Operators size local SSD based on expected worst-case outage duration. At 1 TB/day to a single destination, a 100 GB buffer covers ~2.4 hours.

### Node Failure During Destination Outage
- **Failure detection**: Erlang's built-in node monitoring (`:nodedown`) detects failures within seconds. No leader election.
- **Ownership reassignment**: Consistent hash ring deterministically assigns the destination to the next node. Every node computes the same answer independently.
- **Source nodes retain unACKed events**: Anything sent to the failed node that wasn't ACKed is still on the source nodes. They drain to the new destination owner.
- **Accepted risk**: Events that were ACKed by the failed node (written to its disk) but not yet flushed to the sink are lost if the node's disk is unrecoverable. This is a double-fault (destination down AND node hardware failure), which is an acceptable risk for the SMB market.
- **Future: per-destination shadow archive** (opt-in) — for destinations that need zero-loss guarantees even during double-faults, optionally write a shadow copy of post-pipeline events to S3. Deferred to a later proposal.

### Disk I/O Constraints
- On-box I/O is limited to two purposes: (1) network I/O to DynamoDB for config persistence, (2) local disk buffering for in-flight events during backpressure.
- No external queues or pay-per-message services in the hot path.

### Expression Language
- **VRL-inspired expression language compiled to BEAM bytecode** — not a port of VRL's Rust code or an exact copy of VRL's syntax, but an Elixir implementation inspired by VRL's design philosophy: expression-oriented, purpose-built for observability data, compile-time error checking, no runtime overhead. Own syntax that may diverge where it makes sense, but familiar enough that VRL users feel at home.
- Expressions compile to BEAM bytecode (or pattern match functions) at config save time, not interpreted per-event.
- Forced error handling — expressions that can fail must handle the failure explicitly or the config won't save.
- Built-in functions purpose-built for observability: string manipulation, regex, type coercion, IP/CIDR matching, parsing, hashing/masking.
- No loops, no side effects, no filesystem/network access — it's an expression language, not a programming language.
- Reference VRL's [design doc](https://github.com/vectordotdev/vrl/blob/main/DESIGN.md) and [function reference](https://vector.dev/docs/reference/vrl/functions/) for design inspiration.
- If profiling shows expression evaluation is a bottleneck, the optimization path is: (1) more efficient BEAM compilation, (2) targeted Rust NIF for the hot path. Don't optimize before profiling.

## Open Design Questions
- **Disk buffer technology selection**: RocksDB (via Rox NIF) vs. embedded SQLite (via Exqlite). RocksDB's LSM tree is better suited for the append-heavy, sequential-read buffer workload. Needs benchmarking on typical EC2 instance storage to confirm.

## External Dependencies
- Cribl Stream public documentation (docs.cribl.io) — used as reference for interface design, not for code
- **AWS S3** — first object storage implementation (including Glacier tiers: Instant, Flexible, Deep Archive)
- **AWS SDK** (ex_aws) — S3 operations, Glacier restore requests, restore status polling
- Additional AWS services as needed (SQS, Kinesis, CloudWatch) as sources/destinations
- Future storage backends (Azure Blob Storage, GCS, MinIO) via the same object storage behaviour
