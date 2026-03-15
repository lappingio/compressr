# Change: Add OpenID Connect Authentication

## Why
Compressr needs authentication from day one. Rather than building a local user/password system and migrating later, we start with OIDC as the primary auth mechanism. This lets any organization plug in their existing identity provider immediately. Google OAuth is included as a built-in fallback since most orgs have Google accounts.

## What Changes
- Add OIDC authentication as the primary login mechanism
- Support any OIDC-compliant provider (Okta, Auth0, AWS Cognito, Azure AD, Keycloak, etc.)
- Include Google OAuth as a pre-configured fallback provider
- Protect all LiveView routes and API endpoints behind authentication
- Store minimal user/session data in DynamoDB (sub, email, display name, provider)
- Provide a provider configuration interface (API and UI) for admins to register OIDC providers

## Impact
- Affected specs: `authentication` (new capability)
- Affected code: Phoenix router, LiveView session management, DynamoDB user/session tables, provider configuration
