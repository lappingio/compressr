## 1. API Foundation
- [ ] 1.1 Add `/api/v1` scope to Phoenix router
- [ ] 1.2 Implement JSON response helpers (`items` array + `count` format)
- [ ] 1.3 Implement standard error response format (400, 401, 403, 404, 500)
- [ ] 1.4 Add `/health` endpoint (unauthenticated, returns system status)

## 2. Authentication
- [ ] 2.1 Create API token Ash resource (id, token_hash, user_id, label, scopes, created_at, last_used_at)
- [ ] 2.2 Implement DynamoDB persistence for API tokens
- [ ] 2.3 Implement opaque token generation (cryptographically random, prefixed `cpr_`)
- [ ] 2.4 Add token hash-based lookup (store only hashed tokens)
- [ ] 2.5 Create authentication plug that accepts both OIDC session cookies and `Authorization: Bearer` API tokens
- [ ] 2.6 Add API token management endpoints: POST /api/v1/auth/tokens, GET /api/v1/auth/tokens, DELETE /api/v1/auth/tokens/:id

## 3. Source Endpoints
- [ ] 3.1 GET /api/v1/system/inputs (list sources)
- [ ] 3.2 GET /api/v1/system/inputs/:id (show source)
- [ ] 3.3 POST /api/v1/system/inputs (create source)
- [ ] 3.4 PATCH /api/v1/system/inputs/:id (update source)
- [ ] 3.5 DELETE /api/v1/system/inputs/:id (delete source)

## 4. Destination Endpoints
- [ ] 4.1 GET /api/v1/system/outputs (list destinations)
- [ ] 4.2 GET /api/v1/system/outputs/:id (show destination)
- [ ] 4.3 POST /api/v1/system/outputs (create destination)
- [ ] 4.4 PATCH /api/v1/system/outputs/:id (update destination)
- [ ] 4.5 DELETE /api/v1/system/outputs/:id (delete destination)

## 5. Pipeline Endpoints
- [ ] 5.1 GET /api/v1/system/pipelines (list pipelines)
- [ ] 5.2 GET /api/v1/system/pipelines/:id (show pipeline)
- [ ] 5.3 POST /api/v1/system/pipelines (create pipeline)
- [ ] 5.4 PATCH /api/v1/system/pipelines/:id (update pipeline)
- [ ] 5.5 DELETE /api/v1/system/pipelines/:id (delete pipeline)

## 6. Route Endpoints
- [ ] 6.1 GET /api/v1/system/routes (list routes)
- [ ] 6.2 GET /api/v1/system/routes/:id (show route)
- [ ] 6.3 POST /api/v1/system/routes (create route)
- [ ] 6.4 PATCH /api/v1/system/routes/:id (update route)
- [ ] 6.5 DELETE /api/v1/system/routes/:id (delete route)

## 7. Testing
- [ ] 7.1 Unit tests for authentication plug (session + token paths)
- [ ] 7.2 Unit tests for API token CRUD and hashing
- [ ] 7.3 Integration tests for health endpoint
- [ ] 7.4 Integration tests for source CRUD endpoints
- [ ] 7.5 Integration tests for destination CRUD endpoints
- [ ] 7.6 Integration tests for pipeline CRUD endpoints
- [ ] 7.7 Integration tests for route CRUD endpoints
- [ ] 7.8 Integration tests for API token management endpoints
