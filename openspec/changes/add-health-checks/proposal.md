# Change: Add Health and Readiness Endpoints

## Why
Load balancers (ALB/NLB) and container orchestrators (ECS) need lightweight, unauthenticated endpoints to determine whether a compressr node is alive and ready to accept traffic. Without these, operators must rely on TCP port checks, which cannot distinguish between a node that is booted but not yet ready and one that is fully operational.

## What Changes
- Add a `/health` endpoint that returns node liveness status, basic node info, and lightweight metrics (uptime, memory usage, connected peers)
- Add a `/ready` endpoint that returns whether the node is accepting traffic (all critical subsystems initialized)
- Both endpoints are unauthenticated and return JSON responses
- In a peer cluster, each node exposes its own independent health and readiness endpoints
- Designed for compatibility with AWS ALB/NLB health checks and ECS container health checks

## Impact
- Affected specs: `health-checks` (new capability)
- Affected code: Phoenix router, new health check controller/plug, OTP application supervision tree for readiness tracking
