## ADDED Requirements

### Requirement: API Versioning and Base Path
The system SHALL expose all REST API endpoints under the `/api/v1` path prefix. The system SHALL use `application/json` as the content type for all requests and responses.

#### Scenario: API version prefix
- **WHEN** a client sends a request to `/api/v1/system/inputs`
- **THEN** the system routes the request to the sources controller

#### Scenario: Request without version prefix
- **WHEN** a client sends a request to `/system/inputs` (without `/api/v1` prefix)
- **THEN** the system returns a 404 response

### Requirement: List Response Format
The system SHALL return JSON responses with an `items` array containing the resource objects and a `count` integer indicating the total number of items for all list endpoints.

#### Scenario: List response structure
- **WHEN** a client sends GET to a list endpoint and three resources exist
- **THEN** the response body contains `{"items": [...], "count": 3}` with all three resources in the `items` array

#### Scenario: Empty list response
- **WHEN** a client sends GET to a list endpoint and no resources exist
- **THEN** the response body contains `{"items": [], "count": 0}`

### Requirement: Single Resource Response Format
The system SHALL return JSON responses with an `items` array containing a single resource object and `count` of 1 for show, create, and update endpoints.

#### Scenario: Show response structure
- **WHEN** a client sends GET to a resource endpoint with a valid ID
- **THEN** the response body contains `{"items": [<resource>], "count": 1}`

### Requirement: Error Response Format
The system SHALL return JSON error responses with an `error` string and an appropriate HTTP status code. The system SHALL return 400 for malformed requests, 401 for missing or invalid authentication, 403 for insufficient permissions, 404 for non-existent resources, and 500 for server errors.

#### Scenario: Resource not found
- **WHEN** a client sends GET to `/api/v1/system/inputs/nonexistent`
- **THEN** the system returns HTTP 404 with `{"error": "not_found"}`

#### Scenario: Malformed request body
- **WHEN** a client sends POST with invalid JSON to a create endpoint
- **THEN** the system returns HTTP 400 with an `error` field describing the issue

### Requirement: Health Endpoint
The system SHALL expose a GET `/health` endpoint that returns system health status. The health endpoint SHALL NOT require authentication. The health endpoint SHALL return HTTP 200 when the system is healthy.

#### Scenario: Health check succeeds
- **WHEN** a client sends GET to `/health`
- **THEN** the system returns HTTP 200 with a JSON body indicating healthy status

#### Scenario: Health check without authentication
- **WHEN** an unauthenticated client sends GET to `/health`
- **THEN** the system returns HTTP 200 (no authentication required)

### Requirement: OIDC Session Authentication
The system SHALL accept OIDC session cookies as authentication for API requests. Browser-based clients that have completed OIDC login SHALL be able to call API endpoints using their existing session.

#### Scenario: Authenticated browser session
- **WHEN** a client sends an API request with a valid OIDC session cookie
- **THEN** the system authenticates the request and processes it normally

#### Scenario: Expired session cookie
- **WHEN** a client sends an API request with an expired OIDC session cookie
- **THEN** the system returns HTTP 401

### Requirement: API Token Authentication
The system SHALL accept opaque API tokens via the `Authorization: Bearer <token>` header for programmatic access. API tokens SHALL be cryptographically random, prefixed with `cpr_`, and stored as hashed values in DynamoDB. Each token SHALL be scoped to the user who created it.

#### Scenario: Valid API token
- **WHEN** a client sends a request with `Authorization: Bearer cpr_<valid_token>`
- **THEN** the system authenticates the request as the token's associated user

#### Scenario: Invalid API token
- **WHEN** a client sends a request with `Authorization: Bearer cpr_<invalid_token>`
- **THEN** the system returns HTTP 401

#### Scenario: Token storage security
- **WHEN** an API token is created
- **THEN** the system stores only the cryptographic hash of the token in DynamoDB, never the plaintext

### Requirement: API Token Management
The system SHALL provide endpoints to create, list, and revoke API tokens. Creating a token SHALL return the plaintext token exactly once in the response. Listing tokens SHALL return token metadata (id, label, created_at, last_used_at) but SHALL NOT return the token value. Revoking a token SHALL immediately invalidate it.

#### Scenario: Create API token
- **WHEN** an authenticated user sends POST to `/api/v1/auth/tokens` with a label
- **THEN** the system returns the plaintext token value, token ID, and label
- **THEN** the plaintext token is never retrievable again after this response

#### Scenario: List API tokens
- **WHEN** an authenticated user sends GET to `/api/v1/auth/tokens`
- **THEN** the system returns token metadata for all tokens owned by the user
- **THEN** the response does not include any token values

#### Scenario: Revoke API token
- **WHEN** an authenticated user sends DELETE to `/api/v1/auth/tokens/:id`
- **THEN** the token is immediately invalidated
- **THEN** subsequent requests using that token return HTTP 401

### Requirement: Authentication Required for API Endpoints
The system SHALL require authentication for all API endpoints except `/health`. Unauthenticated requests to protected endpoints SHALL receive HTTP 401.

#### Scenario: Unauthenticated request to protected endpoint
- **WHEN** an unauthenticated client sends GET to `/api/v1/system/inputs`
- **THEN** the system returns HTTP 401

### Requirement: Source CRUD Endpoints
The system SHALL provide RESTful CRUD endpoints for sources at `/api/v1/system/inputs`. GET SHALL list all sources or retrieve a single source by ID. POST SHALL create a new source. PATCH SHALL update an existing source. DELETE SHALL remove a source by ID.

#### Scenario: List sources
- **WHEN** a client sends GET to `/api/v1/system/inputs`
- **THEN** the system returns all configured sources in `items` with a `count`

#### Scenario: Get source by ID
- **WHEN** a client sends GET to `/api/v1/system/inputs/:id` with a valid source ID
- **THEN** the system returns the source configuration in `items`

#### Scenario: Create source
- **WHEN** a client sends POST to `/api/v1/system/inputs` with a valid source configuration
- **THEN** the system creates the source and returns it in `items` with HTTP 201

#### Scenario: Update source
- **WHEN** a client sends PATCH to `/api/v1/system/inputs/:id` with updated fields
- **THEN** the system updates the source and returns the updated configuration in `items`

#### Scenario: Delete source
- **WHEN** a client sends DELETE to `/api/v1/system/inputs/:id` with a valid source ID
- **THEN** the system deletes the source and returns HTTP 200

### Requirement: Destination CRUD Endpoints
The system SHALL provide RESTful CRUD endpoints for destinations at `/api/v1/system/outputs`. GET SHALL list all destinations or retrieve a single destination by ID. POST SHALL create a new destination. PATCH SHALL update an existing destination. DELETE SHALL remove a destination by ID.

#### Scenario: List destinations
- **WHEN** a client sends GET to `/api/v1/system/outputs`
- **THEN** the system returns all configured destinations in `items` with a `count`

#### Scenario: Get destination by ID
- **WHEN** a client sends GET to `/api/v1/system/outputs/:id` with a valid destination ID
- **THEN** the system returns the destination configuration in `items`

#### Scenario: Create destination
- **WHEN** a client sends POST to `/api/v1/system/outputs` with a valid destination configuration
- **THEN** the system creates the destination and returns it in `items` with HTTP 201

#### Scenario: Update destination
- **WHEN** a client sends PATCH to `/api/v1/system/outputs/:id` with updated fields
- **THEN** the system updates the destination and returns the updated configuration in `items`

#### Scenario: Delete destination
- **WHEN** a client sends DELETE to `/api/v1/system/outputs/:id` with a valid destination ID
- **THEN** the system deletes the destination and returns HTTP 200

### Requirement: Pipeline CRUD Endpoints
The system SHALL provide RESTful CRUD endpoints for pipelines at `/api/v1/system/pipelines`. GET SHALL list all pipelines or retrieve a single pipeline by ID. POST SHALL create a new pipeline. PATCH SHALL update an existing pipeline. DELETE SHALL remove a pipeline by ID.

#### Scenario: List pipelines
- **WHEN** a client sends GET to `/api/v1/system/pipelines`
- **THEN** the system returns all configured pipelines in `items` with a `count`

#### Scenario: Get pipeline by ID
- **WHEN** a client sends GET to `/api/v1/system/pipelines/:id` with a valid pipeline ID
- **THEN** the system returns the pipeline configuration in `items`

#### Scenario: Create pipeline
- **WHEN** a client sends POST to `/api/v1/system/pipelines` with a valid pipeline configuration
- **THEN** the system creates the pipeline and returns it in `items` with HTTP 201

#### Scenario: Update pipeline
- **WHEN** a client sends PATCH to `/api/v1/system/pipelines/:id` with updated fields
- **THEN** the system updates the pipeline and returns the updated configuration in `items`

#### Scenario: Delete pipeline
- **WHEN** a client sends DELETE to `/api/v1/system/pipelines/:id` with a valid pipeline ID
- **THEN** the system deletes the pipeline and returns HTTP 200

### Requirement: Route CRUD Endpoints
The system SHALL provide RESTful CRUD endpoints for routes at `/api/v1/system/routes`. GET SHALL list all routes in evaluation order or retrieve a single route by ID. POST SHALL create a new route. PATCH SHALL update an existing route. DELETE SHALL remove a route by ID.

#### Scenario: List routes
- **WHEN** a client sends GET to `/api/v1/system/routes`
- **THEN** the system returns all configured routes in evaluation order in `items` with a `count`

#### Scenario: Get route by ID
- **WHEN** a client sends GET to `/api/v1/system/routes/:id` with a valid route ID
- **THEN** the system returns the route configuration in `items`

#### Scenario: Create route
- **WHEN** a client sends POST to `/api/v1/system/routes` with a valid route configuration
- **THEN** the system creates the route and returns it in `items` with HTTP 201

#### Scenario: Update route
- **WHEN** a client sends PATCH to `/api/v1/system/routes/:id` with updated fields
- **THEN** the system updates the route and returns the updated configuration in `items`

#### Scenario: Delete route
- **WHEN** a client sends DELETE to `/api/v1/system/routes/:id` with a valid route ID
- **THEN** the system deletes the route and returns HTTP 200
