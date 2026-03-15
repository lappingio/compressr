## 1. Health Check Infrastructure
- [ ] 1.1 Create a `Compressr.Health` module that gathers node health data (uptime, memory, connected peers)
- [ ] 1.2 Create a `Compressr.Health.ReadinessTracker` GenServer that tracks subsystem readiness state
- [ ] 1.3 Define a readiness registration API so subsystems can report their ready/not-ready status

## 2. HTTP Endpoints
- [ ] 2.1 Add `/health` route to the Phoenix router (unauthenticated, no auth pipeline)
- [ ] 2.2 Add `/ready` route to the Phoenix router (unauthenticated, no auth pipeline)
- [ ] 2.3 Implement `ComprssrWeb.HealthController.health/2` returning JSON with status, node info, and basic metrics
- [ ] 2.4 Implement `ComprssrWeb.HealthController.ready/2` returning JSON with readiness status and subsystem states
- [ ] 2.5 Return HTTP 200 for healthy/ready, HTTP 503 for unhealthy/not-ready

## 3. AWS Compatibility
- [ ] 3.1 Verify ALB health check compatibility (HTTP 200 response within configurable timeout)
- [ ] 3.2 Verify NLB health check compatibility (TCP + HTTP modes)
- [ ] 3.3 Verify ECS container health check compatibility (exit code or HTTP status)
- [ ] 3.4 Document recommended ALB/NLB/ECS health check configuration in deployment guides

## 4. Testing
- [ ] 4.1 Unit tests for `Compressr.Health` module (uptime, memory, peer count gathering)
- [ ] 4.2 Unit tests for `Compressr.Health.ReadinessTracker` (registration, state transitions)
- [ ] 4.3 Integration tests for `/health` endpoint (HTTP 200 with expected JSON shape)
- [ ] 4.4 Integration tests for `/ready` endpoint (HTTP 200 when ready, HTTP 503 when not ready)
- [ ] 4.5 Test that endpoints are accessible without authentication
