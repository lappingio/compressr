## ADDED Requirements

### Requirement: Health Endpoint
The system SHALL expose an unauthenticated `/health` HTTP endpoint on each node that returns the node's liveness status, node identity, and basic operational metrics.

The response body SHALL be JSON with the following fields:
- `status` — `"healthy"` or `"unhealthy"`
- `node` — the Erlang node name
- `uptime_seconds` — integer seconds since the BEAM VM started
- `memory_mb` — current BEAM memory usage in megabytes
- `connected_peers` — integer count of connected cluster peers

The endpoint SHALL return HTTP 200 with `status: "healthy"` when the BEAM VM is running and the Phoenix endpoint is accepting connections.

The endpoint SHALL return HTTP 503 with `status: "unhealthy"` when critical runtime conditions are detected (e.g., memory exhaustion).

#### Scenario: Healthy node responds to health check
- **WHEN** a GET request is sent to `/health` on a running node
- **THEN** the response status is HTTP 200
- **THEN** the response body is JSON containing `status: "healthy"`, the node name, uptime in seconds, memory usage in megabytes, and connected peer count

#### Scenario: Health endpoint requires no authentication
- **WHEN** a GET request is sent to `/health` without any authentication headers or session
- **THEN** the response is returned normally without a 401 or 403 status

#### Scenario: Health endpoint in a peer cluster
- **WHEN** multiple compressr nodes form a cluster
- **THEN** each node SHALL expose its own `/health` endpoint reflecting that node's individual health status and peer count

### Requirement: Readiness Endpoint
The system SHALL expose an unauthenticated `/ready` HTTP endpoint on each node that indicates whether the node is fully initialized and accepting traffic.

The response body SHALL be JSON with the following fields:
- `status` — `"ready"` or `"not_ready"`
- `node` — the Erlang node name
- `subsystems` — a map of subsystem names to their readiness state (`"ready"` or `"not_ready"`)

The endpoint SHALL return HTTP 200 with `status: "ready"` only when all registered subsystems report ready.

The endpoint SHALL return HTTP 503 with `status: "not_ready"` when any registered subsystem has not yet reported ready, including during application startup.

#### Scenario: Fully initialized node reports ready
- **WHEN** a GET request is sent to `/ready` after all subsystems have reported ready
- **THEN** the response status is HTTP 200
- **THEN** the response body is JSON containing `status: "ready"` and all subsystems listed as `"ready"`

#### Scenario: Node still initializing reports not ready
- **WHEN** a GET request is sent to `/ready` before all subsystems have completed initialization
- **THEN** the response status is HTTP 503
- **THEN** the response body is JSON containing `status: "not_ready"` and at least one subsystem listed as `"not_ready"`

#### Scenario: Readiness endpoint requires no authentication
- **WHEN** a GET request is sent to `/ready` without any authentication headers or session
- **THEN** the response is returned normally without a 401 or 403 status

### Requirement: AWS Health Check Compatibility
The `/health` and `/ready` endpoints SHALL be compatible with AWS ALB health checks, AWS NLB health checks, and AWS ECS container health checks.

The endpoints SHALL respond within 5 seconds under normal operating conditions to satisfy default AWS health check timeout configurations.

The endpoints SHALL use only standard HTTP status codes (200 for success, 503 for failure) that AWS health check mechanisms recognize.

#### Scenario: ALB health check succeeds for healthy node
- **WHEN** an AWS ALB sends an HTTP health check request to `/health`
- **THEN** the response is HTTP 200 with a JSON body
- **THEN** the ALB marks the target as healthy

#### Scenario: ALB health check fails for not-ready node
- **WHEN** an AWS ALB sends an HTTP health check request to `/ready` during node startup
- **THEN** the response is HTTP 503
- **THEN** the ALB marks the target as unhealthy and does not route traffic to it

#### Scenario: ECS health check integration
- **WHEN** an ECS task definition configures a health check against `/health`
- **THEN** the container health status reflects the HTTP response code (200 = healthy, 503 = unhealthy)
