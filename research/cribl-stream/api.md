## API Overview

### General Architecture
- The system SHALL expose a RESTful API as the primary programmatic interface for managing all Cribl Stream resources.
- The system SHALL organize the API into two planes: a **Control Plane** (operational control over Cribl resources for Cloud, Hybrid, and On-Prem) and a **Management Plane** (administrative tasks, Cribl.Cloud only).
- The system SHALL use `/api/v1` as the API version prefix for all control plane endpoints.
- The system SHALL support three context scopes for control plane URLs:
  - **Global context**: `https://{host}:{port}/api/v1/...`
  - **Group/Fleet context**: `https://{host}:{port}/api/v1/m/{groupName}/...`
  - **Host context**: `https://{host}:{port}/api/v1/w/{nodeId}/...`
- The system SHALL use `https://gateway.cribl.cloud` as the base URL for Management Plane endpoints (Cloud only).

### Base URL Patterns
- Cribl.Cloud/Hybrid Control Plane: `https://${workspaceName}-${organizationId}.cribl.cloud/api/v1`
- On-Prem Single Instance: `https://${hostname}:${port}/api/v1`
- On-Prem Distributed (group scope): `https://${hostname}:${port}/api/v1/m/${groupName}`

### Request/Response Format
- The system SHALL use `application/json` as the primary media type.
- The system SHALL support `application/x-ndjson` for select endpoints (e.g., streaming data).
- The system SHALL support `application/x-www-form-urlencoded` for select endpoints.
- The system SHALL support `application/octet-stream` for binary transfers (pack export/import, lookup uploads).
- The system SHALL support `text/csv` for lookup file uploads.
- The system SHALL enforce a 5 MB maximum request body size.
- The system SHALL return JSON responses with an `items` array and `count` attribute for list/CRUD operations.

### PATCH Behavior
- The system SHALL treat Control Plane PATCH requests as full-resource replacements; omitted fields SHALL be removed from the resource.
- The system SHALL treat Management Plane PATCH requests as partial updates; only supplied fields SHALL be modified.

### HTTP Status Codes
- The system SHALL return `200 OK` for successful operations.
- The system SHALL return `204 No Content` for successful operations with no response body.
- The system SHALL return `400 Bad Request` for malformed requests.
- The system SHALL return `401 Unauthorized` for missing or invalid authentication.
- The system SHALL return `403 Forbidden` for insufficient permissions.
- The system SHALL return `404 Not Found` for non-existent resources.
- The system SHALL return `429 Too Many Requests` for rate-limited requests.
- The system SHALL return `500+` for server errors.

### Versioning
- The system SHALL version the API at `/api/v1`.
- The system SHALL maintain backward compatibility from version 4.0 through 4.17 (current).
- The system SHALL version product documentation separately (Stream, Edge, IAM each versioned).

### Diff Size Handling
- The system SHALL return `"isTooBig": true` with message "Diff too big to be displayed" for diffs exceeding 1000 lines when `diffLineLimit` is not specified.
- The system SHALL accept a `diffLineLimit` query parameter (0 = unlimited) on diff endpoints.

---

## API: Authentication

### Endpoint: POST /auth/login
- Description: Authenticate to an on-prem Cribl instance and obtain a bearer token.
- Requirements:
  - The system SHALL accept `username` and `password` in the JSON request body.
  - The system SHALL return a JSON object containing a `token` field (JWT).
  - The system SHALL NOT require authentication for this endpoint.
  - The system SHALL support configurable token expiration via Settings > General Settings > API Server Settings > Advanced (default: 3600 seconds / 1 hour).

### Endpoint: POST https://login.cribl.cloud/oauth/token
- Description: Authenticate to Cribl.Cloud/Hybrid using OAuth2 client credentials flow.
- Requirements:
  - The system SHALL accept `grant_type` ("client_credentials"), `client_id`, `client_secret`, and `audience` ("https://api.cribl.cloud").
  - The system SHALL return `access_token`, `expires_in` (86400 seconds / 24 hours for Cloud), and `token_type` ("Bearer").
  - The system SHALL require API Credentials to be created in Cribl.Cloud UI (Products > Cribl > Organization > API Credentials) yielding a Client ID and Client Secret.

### General Auth Requirements
- The system SHALL require a `Authorization: Bearer {token}` header on all API requests except `/auth/login` and `/health`.
- The system SHALL use JSON Web Tokens (JWTs) as bearer tokens.
- The system SHALL support environment variable-based authentication for CLI: `CRIBL_HOST`, `CRIBL_USERNAME`, `CRIBL_PASSWORD`.
- The system SHALL support SSO fallback via "Allow login as Local User" for on-prem SSO/OpenID deployments.

---

## API: Health

### Endpoint: GET /health
- Description: Check instance health status for operational monitoring and load balancer integration.
- Requirements:
  - The system SHALL NOT require authentication for the health endpoint.
  - The system SHALL return health status suitable for load balancer health checks.

---

## API: System Information

### Endpoint: GET /system/info
- Description: Retrieve system diagnostics.
- Requirements:
  - The system SHALL return JSON with `loadavg` (1-, 5-, 15-minute averages) and `memory` (free and total in bytes).

### Endpoint: GET /system/metrics
- Description: Retrieve internal metrics.
- Requirements:
  - The system SHALL return metrics including throughput (`total.in_bytes`, `total.in_events`, `total.out_events`, `total.out_bytes`, `total.dropped_events`).
  - The system SHALL return health indicators (0=healthy, 1=warning, 2=trouble) for `health.inputs`, `health.outputs`, `system.load_avg`, `system.free_mem`, `system.disk_used`.
  - The system SHALL return I/O metrics including `iometrics.p95_duration_millis` and `iometrics.p99_duration_millis`.

---

## API: Sources (Inputs)

### Endpoint: GET /system/inputs
- Description: List all configured sources.
- Requirements:
  - The system SHALL return all source configurations as a JSON array in `items`.
  - The system SHALL support group-scoped requests via `/m/{groupName}/system/inputs`.

### Endpoint: GET /system/inputs/{id}
- Description: Retrieve a specific source by ID.
- Requirements:
  - The system SHALL return the full source configuration for the given ID.

### Endpoint: POST /system/inputs
- Description: Create a new source.
- Requirements:
  - The system SHALL accept a JSON body defining the source configuration.
  - The system SHALL return the created source in the response.

### Endpoint: PATCH /system/inputs/{id}
- Description: Update an existing source (full replacement).
- Requirements:
  - The system SHALL require the complete resource representation (omitted fields are removed).
  - The system SHALL return the updated source configuration.

### Endpoint: DELETE /system/inputs/{id}
- Description: Delete a source.
- Requirements:
  - The system SHALL remove the source with the given ID.

### Endpoint: GET /system/inputs/status
- Description: Retrieve health/metrics for all sources.
- Requirements:
  - The system SHALL return status information for each configured source.

### Endpoint: GET /system/inputs/{id}/status
- Description: Retrieve health/metrics for a specific source.
- Requirements:
  - The system SHALL return status for the named source.

### Source Types Supported
- The system SHALL support **Collector Sources**: S3, Azure Blob, Database, Filesystem/NFS, GCS, Health Check, REST/API, Script, Splunk Search, Cribl Lake.
- The system SHALL support **Push Sources**: Splunk HEC, Syslog, Kafka, HTTP, TCP, UDP, AWS (CloudWatch, S3, SQS, Kinesis), Azure (Event Hubs, Blob), Google Cloud (Pub/Sub).
- The system SHALL support **Pull Sources**: Kinesis, SQS, S3, Kafka, Office 365.
- The system SHALL support **System/Internal Sources**: Cribl Internal metrics/logs.

---

## API: Destinations (Outputs)

### Endpoint: GET /system/outputs
- Description: List all configured destinations.

### Endpoint: GET /system/outputs/{id}
- Description: Retrieve a specific destination by ID.

### Endpoint: POST /system/outputs
- Description: Create a new destination.

### Endpoint: PATCH /system/outputs/{id}
- Description: Update an existing destination (full replacement).
- Requirements:
  - The system SHALL require complete resource representation; omitted fields SHALL be removed.
  - The system SHALL return the updated resource with `items` array and `count` attribute.

### Endpoint: DELETE /system/outputs/{id}
- Description: Delete a destination.

### Endpoint: GET /system/outputs/status
- Description: Retrieve health/metrics for all destinations.

### Endpoint: GET /system/outputs/{id}/status
- Description: Retrieve health/metrics for a specific destination.

### Destination Types Supported
- The system SHALL support 70+ destination types including: AWS (S3, Kinesis, SQS, CloudWatch), Azure (Blob, Event Hubs, Data Explorer), Google Cloud (Pub/Sub, Storage, Logging), Elasticsearch, Splunk, Databricks, ClickHouse, InfluxDB, Datadog, New Relic, Dynatrace, Prometheus, Kafka, Microsoft Sentinel, CrowdStrike, Cribl HTTP/TCP/Search/Lake, Output Router, DevNull.

---

## API: Pipelines

### Endpoint: GET /system/pipelines (inferred pattern)
- Description: List all pipelines.

### Endpoint: GET /system/pipelines/{id}
- Description: Retrieve a specific pipeline.

### Endpoint: POST /system/pipelines
- Description: Create a new pipeline.
- Requirements:
  - The system SHALL accept pipeline configuration including ordered list of functions, filter expressions, and settings.

### Endpoint: PATCH /system/pipelines/{id}
- Description: Update an existing pipeline.

### Endpoint: DELETE /system/pipelines/{id}
- Description: Delete a pipeline.

### Pipeline Requirements
- The system SHALL support three pipeline attachment points: pre-processing (on Sources), processing (on Routes), and post-processing (on Destinations).
- The system SHALL support JSON-based pipeline import/export.
- The system SHALL support configurable async function timeout limits.
- The system SHALL support pipeline tagging for filtering.

---

## API: Routes

### Endpoint: GET /system/routes
- Description: List all routes in the routing table.
- Requirements:
  - The system SHALL return routes in evaluation order.

### Endpoint: GET /system/routes/{id}
- Description: Retrieve a specific route.

### Endpoint: POST /system/routes
- Description: Add a new route.
- Requirements:
  - The system SHALL support `position` parameter ("start" or "end") to control insertion order.

### Endpoint: DELETE /system/routes/{id}
- Description: Remove a route.

### Route Requirements
- The system SHALL evaluate routes sequentially in display order.
- The system SHALL support JavaScript-compatible filter expressions.
- The system SHALL support the "Final" toggle (matched events stop vs. continue to next route).
- The system SHALL support destination expressions for dynamic destination assignment.

---

## API: Lookups

### Endpoint: GET /system/lookups
- Description: Retrieve list of existing lookups.
- Requirements:
  - The system SHALL return lookup metadata: id, size, mode, rows, version, description, tags.

### Endpoint: PUT /system/lookups?filename={name}
- Description: Upload a lookup file.
- Requirements:
  - The system SHALL accept `Content-Type: text/csv` with binary CSV body.
  - The system SHALL return a temporary filename, row count, and file size.

### Endpoint: POST /system/lookups
- Description: Create a lookup from an uploaded file.
- Requirements:
  - The system SHALL accept `id`, `fileInfo.filename` (temp filename from upload), and optional `mode` ("disk" or "memory").

### Endpoint: PATCH /system/lookups/{id}
- Description: Replace an existing lookup.
- Requirements:
  - The system SHALL accept `id`, `fileInfo.filename`, and optional `mode`.

### Endpoint: GET /system/lookups/{id}/content?raw=1
- Description: Download lookup file content.
- Requirements:
  - The system SHALL return raw CSV file content.

---

## API: Packs

### Endpoint: POST /packs/__clone__
- Description: Copy packs between worker groups.
- Requirements:
  - The system SHALL accept `srcGroup`, `dstGroups` (array), and `packs` (array of pack IDs).
  - The system SHALL return an `installed` array.

### Endpoint: GET /m/{workerGroup}/packs/{packName}/export
- Description: Export a pack as a `.crbl` file.
- Requirements:
  - The system SHALL return an `application/octet-stream` response.
  - The system SHALL accept a `mode` query parameter (merge, default_only, merge_safe).
  - The system SHALL remove encrypted fields during export for security.

### Endpoint: PUT /m/{workerGroup}/packs?filename={name}
- Description: Upload an exported pack file.
- Requirements:
  - The system SHALL accept `Content-Type: application/octet-stream`.
  - The system SHALL return a `source` field with filename and random ID.

### Endpoint: POST /m/{workerGroup}/packs
- Description: Install an uploaded pack.
- Requirements:
  - The system SHALL accept `source` (from upload response) and optional `id` (new pack name).
  - The system SHALL return `items` array with installed pack metadata and `count`.

### Pack Resource Requirements
- The system SHALL support pack-scoped resources: pipelines, routes, sources, destinations, lookups, variables, event breakers.
- The system SHALL require unique Pack IDs within a Worker Group.
- The system SHALL support pack versioning with minimum Stream version compatibility.

---

## API: Version Control / Commit & Deploy

### Endpoint: POST /version/commit
- Description: Commit configuration changes.
- Requirements:
  - The system SHALL accept `message` (commit message), optional `group` (worker group name), and optional `files` (array of file paths for selective commit).
  - The system SHALL return commit details: branch, commit hash, summary (changes, insertions, deletions), and modified/created files.

### Endpoint: PATCH /master/groups/{groupName}/deploy
- Description: Deploy committed changes to a worker group.
- Requirements:
  - The system SHALL accept `version` (commit hash from commit response).
  - The system SHALL return deployment details: group description, tags, config version, ID.

### Endpoint: POST /version/sync
- Description: Sync production from Git repository (GitOps).
- Requirements:
  - The system SHALL accept `ref` (branch name) and `deploy` (boolean).
  - The system SHALL pull latest changes from the specified branch and optionally deploy.

### Endpoint: GET /version/diff
- Description: Retrieve configuration diffs.
- Requirements:
  - The system SHALL accept `filename` and `diffLineLimit` query parameters.
  - The system SHALL return diff content or `isTooBig: true` for diffs exceeding 1000 lines.

### Endpoint: GET /version/show
- Description: Display version information with diff data.
- Requirements:
  - The system SHALL accept `diffLineLimit` query parameter.

---

## API: Worker Groups / Fleets

### Endpoint: GET /master/groups (inferred)
- Description: List worker groups.

### Endpoint: POST /master/groups (inferred)
- Description: Create a worker group.

### Endpoint: PATCH /master/groups/{groupName} (inferred)
- Description: Update worker group settings.

### Endpoint: DELETE /master/groups/{groupName} (inferred)
- Description: Delete a worker group.

### Requirements
- The system SHALL support separate version control per worker group.
- The system SHALL support cloning worker groups with all configurations.
- The system SHALL support worker group system settings management.

---

## API: Event Breaker Rulesets

### Endpoint: CRUD on /system/event-breaker-rulesets (inferred from Terraform provider)
- Description: Manage event breaker rulesets.
- Requirements:
  - The system SHALL support CRUD operations on event breaker rulesets.
  - The system SHALL support ordered rule evaluation with filter conditions.
  - The system SHALL support configurable event breaker types, max event bytes, timestamp settings.

---

## API: Functions

### Endpoint: CRUD on /system/functions (inferred)
- Description: Manage pipeline functions.
- Requirements:
  - The system SHALL support all function types: Eval, Rename, Clone, Flatten, Drop, Regex Filter, Suppress, Grok, Parser, Regex Extract, Auto Timestamp, Lookup, GeoIP, DNS Lookup, Mask, Numerify, Serialize, Sampling, Dynamic Sampling, Aggregations, Publish Metrics, OTLP (Logs/Metrics/Traces), Code, Redis, Tee, Event Breaker Function, Comment, and others.

---

## API: Parsers

### Endpoint: CRUD on /system/parsers (inferred)
- Description: Manage parser library entries.

---

## API: Regex Library

### Endpoint: CRUD on /system/regexes (inferred)
- Description: Manage regex library entries.

---

## API: Schemas

### Endpoint: CRUD on /system/schemas (inferred)
- Description: Manage schema definitions.

### Endpoint: CRUD on /system/parquet-schemas (inferred)
- Description: Manage Parquet schema definitions.

---

## API: Global Variables

### Endpoint: CRUD on /system/vars (inferred)
- Description: Manage global variables.
- Requirements:
  - The system SHALL support variable definitions for configuration templatization.

---

## API: Encryption Keys

### Endpoint: CRUD on /system/keys (inferred)
- Description: Manage encryption keys.

---

## API: Secrets

### Endpoint: CRUD on /system/secrets (inferred from Terraform provider)
- Description: Manage secrets.

---

## API: Certificates

### Endpoint: CRUD on /system/certificates (inferred from Terraform provider)
- Description: Manage TLS certificates.

---

## API: Collectors / Jobs

### Endpoint: CRUD on /system/collectors (inferred)
- Description: Manage collector configurations.
- Requirements:
  - The system SHALL support 10 collector types: Azure Blob, Cribl Lake, Database, Filesystem/NFS, GCS, Health Check, REST/API, S3, Script, Splunk Search.
  - The system SHALL support scheduled collection jobs.

---

## API: Notifications

### Endpoint: CRUD on /system/notifications (inferred)
- Description: Manage notification rules.
- Requirements:
  - The system SHALL support notification types: High/Low/No Data Volume (sources), Backpressure/PQ Usage/Unhealthy (destinations), License expiration.
  - The system SHALL support metadata key-value pairs on notifications.

### Endpoint: CRUD on /system/notification-targets (inferred)
- Description: Manage notification delivery targets.
- Requirements:
  - The system SHALL support target types: Email, Webhook, Slack, PagerDuty, AWS SNS.
  - The system SHALL support "only notify on start and resolution" toggle.

---

## API: Mapping Rulesets

### Endpoint: CRUD on /system/mappings (inferred)
- Description: Manage mapping rulesets for Worker assignment.

---

## API: Grok Patterns

### Endpoint: CRUD on /system/grok (inferred from Terraform provider)
- Description: Manage Grok pattern definitions.

---

## API: HMAC Functions

### Endpoint: CRUD on /system/hmac (inferred from Terraform provider)
- Description: Manage HMAC function configurations.

---

## API: Database Connections

### Endpoint: CRUD on /system/database-connections (inferred from Terraform provider)
- Description: Manage database connection configurations.

---

## API: Projects

### Endpoint: CRUD on /system/projects (inferred from Terraform provider)
- Description: Manage data projects.
- Requirements:
  - The system SHALL support project-scoped isolation for team collaboration.
  - The system SHALL support subscription-based data filtering per project.

---

## API: Subscriptions

### Endpoint: CRUD on /system/subscriptions (inferred from Terraform provider)
- Description: Manage data subscriptions within projects.

---

## API: AppScope Configuration

### Endpoint: CRUD on /system/appscope (inferred from Terraform provider)
- Description: Manage AppScope configurations.

---

## API: Cribl Lake

### Endpoint: CRUD on /system/cribl-lake-datasets (inferred from Terraform provider)
- Description: Manage Cribl Lake datasets.

### Endpoint: CRUD on /system/cribl-lake-houses (inferred from Terraform provider)
- Description: Manage Cribl Lake houses.

---

## API: Search

### Endpoint: CRUD on /system/search-dashboards (inferred from Terraform provider)
- Description: Manage search dashboards.

### Endpoint: CRUD on /system/search-dashboard-categories (inferred)
- Description: Manage dashboard categories.

### Endpoint: CRUD on /system/search-datasets (inferred)
- Description: Manage search datasets.

### Endpoint: CRUD on /system/search-dataset-providers (inferred)
- Description: Manage dataset providers.

### Endpoint: CRUD on /system/search-macros (inferred)
- Description: Manage search macros.

### Endpoint: CRUD on /system/search-saved-queries (inferred)
- Description: Manage saved search queries.

### Endpoint: CRUD on /system/search-usage-groups (inferred)
- Description: Manage search usage groups.

---

## API: Workspaces (Cloud)

### Endpoint: CRUD on /workspaces (Management Plane, inferred)
- Description: Manage Cribl.Cloud workspaces.

---

## API: Config Version

### Endpoint: GET /system/config-version (inferred from Terraform data source)
- Description: Retrieve current configuration version information.

---

## API: Instance Settings

### Endpoint: GET /system/instance-settings (inferred from Terraform data source)
- Description: Retrieve instance-level settings.

---

## Webhook / Event Notification Capabilities

- The system SHALL support webhook notification targets for alerting on source/destination/license events.
- The system SHALL support configurable notification targets: Email, Webhook (generic HTTP), Slack, PagerDuty, AWS SNS.
- The system SHALL support trigger conditions: data volume thresholds, backpressure activation, persistent queue usage, unhealthy destinations, license expiration.
- The system SHALL support metadata attachment (key-value pairs) on all notification types.
- The system SHALL support "notify on start and resolution only" mode.
- The system SHALL NOT expose a general-purpose event subscription/streaming API (notifications are configuration-driven, not a pub/sub system).

---

## CLI Tools That Interact with the API

### cribl auth
- `auth login` - Authenticate interactively or via flags (`-H`, `-u`, `-p`, `-f`) or environment variables (`CRIBL_HOST`, `CRIBL_USERNAME`, `CRIBL_PASSWORD`).
- `auth logout` - Terminate CLI session.
- `auth mf` - Manage PIV/MFA authentication (requires TLS).

### cribl git
- `git commit -g {group} -m "{message}"` - Commit configuration changes via API.
- `git commit-deploy -g {group} -m "{message}"` - Commit and deploy in one operation.
- `git deploy -g {group} -v {version}` - Deploy a specific committed version.
- `git list-groups` - List available worker groups/fleets.

### cribl pack
- `pack export` - Export packs (modes: merge_safe, merge, default_only).
- `pack install` - Install pack from URL.
- `pack list` - List installed packs.
- `pack uninstall` - Remove an installed pack.
- `pack upgrade` - Update pack to newer version.

### cribl pipe
- `pipe -p {pipelineName}` - Feed stdin through a pipeline for testing.

### Other CLI Commands
- `cribl decrypt` / `cribl encrypt` - Encrypt/decrypt with secret keys.
- `cribl keys` - Manage encryption keys.
- `cribl diag` - Manage diagnostic bundles.
- `cribl vars` - Manage global variables.
- `cribl mode-master` / `mode-worker` / `mode-single` / `mode-edge` / `mode-managed-edge` / `mode-outpost` - Configure instance deployment mode.
- `cribl start` / `stop` / `restart` / `reload` / `status` / `version` - Instance lifecycle management.
- `cribl parquet` - View Parquet file metadata/schemas.
- `cribl nc` - Listen on port for traffic metrics.
- `cribl boot-start` - Enable/disable auto-start.
- `cribl limits` - Control feature restrictions.
- `cribl pq` - Persistent queue benchmarking.
- `cribl scope` - Scope Linux commands via AppScope.

---

## SDKs and Terraform Provider

### SDKs (Preview)
- The system SHALL provide SDKs in Go, Python, and TypeScript.
- Control Plane SDKs SHALL manage operational resources (sources, destinations, pipelines, routes, etc.).
- Management Plane SDKs SHALL manage administrative tasks (workspaces, organization settings).

### Terraform Provider (Preview)
- The system SHALL expose 47 Terraform resources and 55 data sources covering all API-managed resource types.
- The system SHALL support `criblio_commit` and `criblio_deploy` resources for GitOps-style Terraform workflows.

---

## IAM and Permissions Model

- The system SHALL enforce a hierarchical permissions model: Organization > Workspace > Product > Resource.
- The system SHALL support permission levels: Owner, Admin, IAM Admin, Editor, User, Read Only, Collect, No Access.
- The system SHALL support permission inheritance from higher to lower levels.
- The system SHALL support local authentication, LDAP, Splunk, PIV, and SSO (Okta, Microsoft Entra ID, Ping Identity).
- The system SHALL support service accounts (`admin`, `system`) for automated/background operations.
- The system SHALL log all API access (including service account actions) in `access.log`.

---

## Summary of All API Resource Categories (47 from Terraform provider)

| # | Resource Category | API Path Pattern (inferred) |
|---|---|---|
| 1 | AppScope Config | `/system/appscope` |
| 2 | Certificates | `/system/certificates` |
| 3 | Collectors | `/system/collectors` |
| 4 | Commit | `/version/commit` |
| 5 | Cribl Lake Datasets | `/system/cribl-lake-datasets` |
| 6 | Cribl Lake Houses | `/system/cribl-lake-houses` |
| 7 | Database Connections | `/system/database-connections` |
| 8 | Deploy | `/master/groups/{group}/deploy` |
| 9 | Destinations | `/system/outputs` |
| 10 | Event Breaker Rulesets | `/system/event-breaker-rulesets` |
| 11 | Global Variables | `/system/vars` |
| 12 | Grok Patterns | `/system/grok` |
| 13 | Groups | `/master/groups` |
| 14 | Group System Settings | `/master/groups/{group}/settings` |
| 15 | HMAC Functions | `/system/hmac` |
| 16 | Encryption Keys | `/system/keys` |
| 17 | Lakehouse Dataset Connections | `/system/lakehouse-dataset-connections` |
| 18 | Lookup Files | `/system/lookups` |
| 19 | Mapping Rulesets | `/system/mappings` |
| 20 | Notifications | `/system/notifications` |
| 21 | Notification Targets | `/system/notification-targets` |
| 22 | Packs | `/system/packs` or `/m/{group}/packs` |
| 23 | Pack Breakers | `/system/packs/{pack}/breakers` |
| 24 | Pack Destinations | `/system/packs/{pack}/outputs` |
| 25 | Pack Lookups | `/system/packs/{pack}/lookups` |
| 26 | Pack Pipelines | `/system/packs/{pack}/pipelines` |
| 27 | Pack Routes | `/system/packs/{pack}/routes` |
| 28 | Pack Sources | `/system/packs/{pack}/inputs` |
| 29 | Pack Variables | `/system/packs/{pack}/vars` |
| 30 | Parquet Schemas | `/system/parquet-schemas` |
| 31 | Parser Library | `/system/parsers` |
| 32 | Pipelines | `/system/pipelines` |
| 33 | Projects | `/system/projects` |
| 34 | Regex Library | `/system/regexes` |
| 35 | Routes | `/system/routes` |
| 36 | Schemas | `/system/schemas` |
| 37 | Search Dashboards | `/system/search/dashboards` |
| 38 | Search Dashboard Categories | `/system/search/dashboard-categories` |
| 39 | Search Datasets | `/system/search/datasets` |
| 40 | Search Dataset Providers | `/system/search/dataset-providers` |
| 41 | Search Macros | `/system/search/macros` |
| 42 | Search Saved Queries | `/system/search/saved-queries` |
| 43 | Search Usage Groups | `/system/search/usage-groups` |
| 44 | Secrets | `/system/secrets` |
| 45 | Sources | `/system/inputs` |
| 46 | Subscriptions | `/system/subscriptions` |
| 47 | Workspaces | `/workspaces` (Management Plane) |

---

**Key sources consulted:**
- `https://docs.cribl.io/cribl-as-code/api` (API overview, base URLs, auth, request format)
- `https://docs.cribl.io/cribl-as-code/api-auth` (authentication details, JWT, OAuth2)
- `https://docs.cribl.io/cribl-as-code/workflows` and sub-pages (update-configurations, commit-deploy, create-update-lookups, copy-export-install-packs, view-large-diffs)
- `https://docs.cribl.io/stream/` (sources, destinations, pipelines, routes, functions, packs, notifications, monitoring, CLI reference, GitOps, configuration files)
- `https://github.com/criblio/python-api-wrapper` (Python SDK revealing CRUD patterns)
- `https://github.com/criblio/terraform-provider-criblio` (Terraform provider revealing full 47-resource / 55-data-source API surface)
