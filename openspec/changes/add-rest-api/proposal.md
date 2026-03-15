# Change: Add REST API

## Why
The programmatic interface is a first-class citizen in compressr. Users and automation tools need a stable, well-documented REST API to manage pipeline resources without the web UI. Mirroring Cribl Stream's API path structure where practical lowers the migration barrier for teams moving from Cribl.

## What Changes
- Add `/api/v1/system/inputs` endpoints for source CRUD
- Add `/api/v1/system/outputs` endpoints for destination CRUD
- Add `/api/v1/system/pipelines` endpoints for pipeline CRUD
- Add `/api/v1/system/routes` endpoints for route CRUD
- Add `/health` endpoint (unauthenticated)
- Add API token system: opaque tokens stored in DynamoDB, scoped to a user
- Add dual authentication: OIDC session cookies (browser) and API tokens (programmatic)
- JSON request/response format with `items` array and `count` for list operations
- Standard CRUD verbs: GET (list/show), POST (create), PATCH (update), DELETE

## Impact
- Affected specs: `rest-api` (new capability)
- Affected code: Phoenix router, new API controllers, Ash resource API extensions, DynamoDB token storage, authentication plugs
- Depends on: `add-oidc-auth` (OIDC session auth), `add-pipelines` (pipeline resources), `add-routes` (route resources)
