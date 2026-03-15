## 1. Project Scaffold
- [ ] 1.1 Create Phoenix project with LiveView
- [ ] 1.2 Add Ash Framework and configure
- [ ] 1.3 Add ex_aws and ex_aws_dynamo dependencies
- [ ] 1.4 Set up basic DynamoDB table configuration (users, sessions)

## 2. OIDC Core
- [ ] 2.1 Add openid_connect dependency
- [ ] 2.2 Define OIDC provider behaviour and configuration schema
- [ ] 2.3 Implement OIDC discovery (fetch .well-known/openid-configuration)
- [ ] 2.4 Implement authorization redirect flow
- [ ] 2.5 Implement callback handler (code exchange, token validation, ID token parsing)
- [ ] 2.6 Implement token refresh flow

## 3. Google Fallback Provider
- [ ] 3.1 Pre-configure Google as a built-in OIDC provider
- [ ] 3.2 Ensure Google works out of the box with just client_id and client_secret

## 4. User and Session Management
- [ ] 4.1 Create Ash resource for User (sub, email, display_name, provider, timestamps)
- [ ] 4.2 Create or update user record on successful OIDC callback
- [ ] 4.3 Implement session creation and storage in DynamoDB
- [ ] 4.4 Implement session expiry and cleanup

## 5. Route Protection
- [ ] 5.1 Add authentication plug for API endpoints
- [ ] 5.2 Add LiveView on_mount hook for authenticated routes
- [ ] 5.3 Implement login page with provider selection
- [ ] 5.4 Implement logout (session clear + OIDC end_session if supported)

## 6. Provider Configuration API
- [ ] 6.1 Create Ash resource for OIDC provider config (issuer, client_id, client_secret, scopes, display_name)
- [ ] 6.2 API endpoints for CRUD on provider configurations
- [ ] 6.3 Validate provider config on save (test discovery endpoint)

## 7. Provider Configuration UI
- [ ] 7.1 LiveView page for managing OIDC providers
- [ ] 7.2 Add/edit/delete provider form with validation feedback

## 8. Testing
- [ ] 8.1 Unit tests for token validation and ID token parsing
- [ ] 8.2 Integration tests for auth flow (using mock OIDC provider)
- [ ] 8.3 Test session expiry and refresh
- [ ] 8.4 Test route protection (unauthenticated access redirects)
