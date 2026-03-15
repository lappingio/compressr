## ADDED Requirements

### Requirement: OIDC Provider Authentication
The system SHALL authenticate users via OpenID Connect. Any OIDC-compliant identity provider SHALL be supported by configuring its issuer URL, client ID, and client secret. The system SHALL perform OIDC discovery, authorization code flow, and ID token validation per the OpenID Connect Core specification.

#### Scenario: User logs in via configured OIDC provider
- **WHEN** a user navigates to the login page and selects a configured OIDC provider
- **THEN** the system redirects to the provider's authorization endpoint with appropriate scopes
- **WHEN** the provider redirects back with an authorization code
- **THEN** the system exchanges the code for tokens, validates the ID token, and creates a session

#### Scenario: OIDC discovery succeeds
- **WHEN** an OIDC provider is configured with a valid issuer URL
- **THEN** the system fetches the provider's `.well-known/openid-configuration` and caches the endpoints

#### Scenario: OIDC discovery fails
- **WHEN** an OIDC provider is configured with an unreachable or invalid issuer URL
- **THEN** the system rejects the configuration and returns a descriptive error

### Requirement: Google OAuth Fallback
The system SHALL include Google as a pre-configured OIDC provider. Administrators SHALL only need to supply a Google client ID and client secret to enable Google authentication.

#### Scenario: Google login with minimal configuration
- **WHEN** an administrator configures only a Google client_id and client_secret
- **THEN** Google login is available on the login page without additional configuration

### Requirement: User Record Management
The system SHALL create or update a user record upon successful OIDC authentication. User records SHALL store the OIDC subject identifier (sub), email, display name, and provider reference.

#### Scenario: First-time login creates user
- **WHEN** a user authenticates via OIDC for the first time
- **THEN** a new user record is created with their sub, email, display name, and provider

#### Scenario: Returning user updates profile
- **WHEN** an existing user authenticates and their email or display name has changed at the provider
- **THEN** the user record is updated with the current values

### Requirement: Session Management
The system SHALL create a session upon successful authentication and store session state in DynamoDB. Sessions SHALL expire after a configurable duration and support token refresh.

#### Scenario: Session expires
- **WHEN** a session exceeds its configured TTL
- **THEN** the user is redirected to the login page on their next request

#### Scenario: Token refresh extends session
- **WHEN** a session's access token is near expiry and a valid refresh token exists
- **THEN** the system refreshes the token transparently without interrupting the user

### Requirement: Route Protection
All LiveView routes and API endpoints SHALL require authentication unless explicitly marked as public. Unauthenticated requests SHALL be redirected to the login page (LiveView) or receive a 401 response (API).

#### Scenario: Unauthenticated LiveView access
- **WHEN** an unauthenticated user navigates to a protected LiveView route
- **THEN** they are redirected to the login page with a return-to parameter

#### Scenario: Unauthenticated API access
- **WHEN** an unauthenticated request is made to a protected API endpoint
- **THEN** the system responds with HTTP 401

### Requirement: OIDC Provider Configuration
Administrators SHALL be able to manage OIDC provider configurations via API and UI. Each provider configuration SHALL include issuer URL, client ID, client secret, scopes, and a display name. The system SHALL validate the provider's discovery endpoint before saving.

#### Scenario: Add a new OIDC provider via API
- **WHEN** an administrator submits a valid provider configuration via the API
- **THEN** the system validates the discovery endpoint and saves the configuration

#### Scenario: Invalid provider is rejected
- **WHEN** an administrator submits a provider configuration with an unreachable issuer URL
- **THEN** the system rejects the configuration with a validation error

#### Scenario: Manage providers via UI
- **WHEN** an administrator navigates to the provider management page
- **THEN** they can view, add, edit, and delete OIDC provider configurations

### Requirement: Logout
The system SHALL support logout by clearing the local session. If the OIDC provider supports end_session, the system SHALL redirect to the provider's end_session endpoint.

#### Scenario: Logout clears session
- **WHEN** a user logs out
- **THEN** their session is removed from DynamoDB and they are redirected to the login page

#### Scenario: Logout with provider end_session
- **WHEN** a user logs out and their OIDC provider supports end_session
- **THEN** the system redirects to the provider's end_session endpoint after clearing the local session
