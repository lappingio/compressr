## Authentication

### Requirement: Local Authentication
- The system SHALL support local user authentication with credentials stored in `$CRIBL_HOME/local/cribl/auth/users.json`.
- The system SHALL ship with default credentials of `admin/admin`.
- The system SHALL hash passwords stored in `users.json` and auto-hash any plaintext `password` field within one minute.
- The system SHALL support manual password replacement by substituting the `passwd` key with a plaintext `password` key in the users file.

### Requirement: Splunk Authentication
- The system SHALL support delegating authentication to a Splunk search head via its management port (default 8089).
- The system SHALL support configuring SSL for the Splunk connection (enabled by default).
- The system SHALL support optional certificate validation for Splunk auth connections (disabled by default, but recommended to enable).
- The system SHALL support a fallback-on-fatal-error option to attempt local auth if Splunk auth fails (default: off).
- The system SHALL support a fallback-on-bad-login sub-option to attempt local auth for invalid credentials specifically (default: off).

### Requirement: LDAP Authentication
- The system SHALL support LDAP authentication with configurable server list (`host:port` format).
- The system SHALL support both `ldap://` (insecure) and `ldaps://` (secure) connections, toggled via a `Secure` setting.
- The system SHALL require configuration of: Bind DN, Bind password, User search base, Username field (e.g., `cn`, `uid`, `sAMAccountName`), and optional User search filter.
- The system SHALL support a configurable connection timeout (default: 5000ms).
- The system SHALL support a `Reject unauthorized` option for TLS certificate validation on secure LDAP connections.
- The system SHALL support fallback-on-fatal-error and fallback-on-bad-login options identical to Splunk auth.
- The system SHALL support LDAP group-based role mapping (Enterprise license only) with configurable: Group search base, Group member field, Group membership attribute (`dn`, `cn`, `uid`, or `uidNumber`; default: `dn`), Group search filter, and Group name field.

### Requirement: SSO/OpenID Connect (OIDC) Authentication
- The system SHALL support SSO authentication via OpenID Connect for both on-prem and Cribl.Cloud deployments.
- The system SHALL require configuration of: Provider name, Audience/Relying Party ID (the Cribl Stream Leader base URL without trailing slash), and Client Secret.
- The system SHALL use a callback URL of `https://{hostname}:9000/api/v1/auth/authorization-code/callback`.
- The system SHALL support OIDC integration with identity providers including Okta, Microsoft Entra ID, and Ping Identity.
- The system SHALL support mapping IdP group claims to Cribl roles (Enterprise license, distributed deployments only).
- The system SHALL treat IdP group name matching as case-sensitive.
- The system SHALL support configuring a default role for users not in any mapped groups (recommended: `user`).
- The system SHALL support enabling local authentication fallback when OIDC SSO is configured to prevent lockout.

### Requirement: SSO/SAML Authentication
- The system SHALL support SSO authentication via SAML 2.0 (available in Cribl Stream 4.1.0 and later).
- The system SHALL support SAML integration with identity providers including Okta and Microsoft Entra ID.
- The system SHALL support mapping SAML group memberships to Cribl roles for authorization.

### Requirement: Authentication Session Controls
- The system SHALL support a configurable auth-token TTL (default: 3600 seconds, minimum: 1 second) at Settings > Global > General Settings > API Server Settings > Advanced.
- The system SHALL support a configurable session idle time limit (default: 3600 seconds, minimum: 60 seconds), invalidating sessions after the specified inactivity period.
- The system SHALL automatically renew tokens upon continued UI interaction, resetting the idle timeout.
- The system SHALL support a configurable login rate limit (default: 2/second, configurable as `N/unit` e.g., `50/minute`, `10/hour`).
- The system SHALL support a configurable SSO/SLO callback rate limit.
- The system SHALL support a `Logout on roles change` option (default: enabled, Enterprise license) that auto-logs out users when their assigned roles change.

### Requirement: API Authentication (On-Prem)
- The system SHALL require Bearer token authentication (JWT) for all API requests except `/auth/login` and `/health` endpoints.
- The system SHALL issue Bearer tokens via POST to `/api/v1/auth/login` with username/password credentials.
- The system SHALL return a `token` and `forcePasswordChange` boolean in the login response.
- The system SHALL enforce a configurable token TTL (default: 3600 seconds) for on-prem Bearer tokens.

### Requirement: API Authentication (Cribl.Cloud / Hybrid)
- The system SHALL support API Credential creation (Client ID + Client Secret) via Products > Cribl > Organization > API Credentials.
- The system SHALL issue Bearer tokens via OAuth 2.0 client credentials grant to `https://login.cribl.cloud/oauth/token` with `grant_type=client_credentials`, `client_id`, `client_secret`, and `audience=https://api.cribl.cloud`.
- The system SHALL issue Cribl.Cloud Bearer tokens with a fixed 24-hour (86400 second) expiration.
- The system SHALL return `access_token`, `expires_in`, `token_type`, and `scope` in the token response.

---

## Authorization / RBAC

### Requirement: Legacy Roles and Policies Model
- The system SHALL support a legacy RBAC model (Enterprise license, distributed deployments only) where Roles are logical entities associated with one or more Policies, and Policies are collections of access rights on objects.
- The system SHALL provide the following default roles:
  - `admin`: permission to do anything and everything in the system.
  - `reader_all`: read-only access to all Worker Groups/Fleets.
  - `editor_all`: read/write access to all Worker Groups/Fleets.
  - `owner_all`: read/write access plus Deploy permissions to all Worker Groups/Fleets.
- The system SHALL support creation of custom roles with configurable policy associations.
- The system SHALL support mapping external IdP groups (LDAP, OIDC, SAML) to Cribl roles.
- The system SHALL fall back to granting all external users the `admin` role when only a Standard license is present.

### Requirement: Members and Permissions Model
- The system SHALL support a Members and Permissions model providing finer-grained access control at multiple resource levels (Cribl.Cloud relies exclusively on this model).
- The system SHALL support the following permission levels, from broadest to most restrictive:
  - **Owner**: all Admin rights plus exclusive actions (deleting Organizations and Workspaces).
  - **Admin**: broad access to manage settings and configurations.
  - **IAM Admin**: limited to managing Organization Members and SSO settings only.
  - **User/Member**: basic login access with no automatic permissions at lower levels.
  - **Maintainer**: resource management within specific contexts without administrative member access.
  - **Editor**: create, modify, and delete most resources and configurations.
  - **Collect**: run collection jobs on a Worker Group or Edge Fleet.
  - **Read Only**: viewing access without configuration changes.
  - **No Access**: explicitly blocks all access at the assigned level and all lower levels.
- The system SHALL support assigning permissions at a hierarchy of resource levels: Organization > Workspace > Global > Products (Stream, Edge, Search, Lake) > Worker Groups/Edge Fleets > Resources (projects, datasets, dashboards, notebooks).
- The system SHALL implement permission inheritance where members automatically inherit permissions down the hierarchy.
- The system SHALL allow the `No Access` permission to override inherited permissions, blocking access at the assigned level and below.
- The system SHALL support resource-specific sharing for Stream Projects, Search Datasets, Dashboards, and Notebooks with specific Members and Teams.

### Requirement: License-Gated Access Control
- The system SHALL restrict permission-based access control to distributed deployments (Stream, Edge) with an Enterprise license or Cribl.Cloud plan.
- The system SHALL grant all users full administrative privileges on single-instance deployments or non-Enterprise license tiers.

### Requirement: Service Accounts
- The system SHALL support service accounts for administrative and automated tasks (identified as `admin` and `system` users in internal logs).
- The system SHALL log service account actions for auditing and troubleshooting purposes.

---

## Security

### Requirement: TLS/SSL for API and UI
- The system SHALL support TLS encryption for API and UI access, configured via UI (Settings > Globals > Security > Certificates) or via `cribl.yml` (`api.ssl.privKeyPath`, `api.ssl.certPath`, `api.ssl.caPath`, `api.ssl.passphrase`, `api.ssl.disabled`).
- The system SHALL require certificates and keys in PEM format.
- The system SHALL encrypt TLS certificate private keys in configuration files when added or modified (Cribl Stream 4.1+).
- The system SHALL default to TLS disabled for UI, API, Worker-to-Leader, and data traffic (encryption must be explicitly enabled).
- The system SHALL default to TLS enabled for authentication connections (Splunk, OIDC).

### Requirement: TLS Defaults and System-Wide Settings
- The system SHALL enforce a minimum TLS version of TLS 1.2 by default across all secure connections.
- The system SHALL support configurable minimum TLS version (`tls.minVersion`, default: TLSv1.2) and maximum TLS version (`tls.maxVersion`, default: TLSv1.3).
- The system SHALL support configurable cipher suites (`tls.defaultCipherList`) including ECDHE-RSA, ECDHE-ECDSA with AES-GCM, and DHE-RSA variants, while excluding weak ciphers (aNULL, eNULL, EXPORT, DES, RC4, MD5, PSK, SRP, CAMELLIA).
- The system SHALL support configurable ECDH curve selection (`tls.defaultEcdhCurve`).
- The system SHALL support a global `tls.rejectUnauthorized` setting for server certificate validation.
- The system SHALL support the `NODE_EXTRA_CA_CERTS` environment variable to add trusted root CAs.
- The system SHALL support the `NODE_TLS_REJECT_UNAUTHORIZED=0` environment variable to bypass certificate validation (not recommended for production).

### Requirement: TLS for Leader/Worker Communication
- The system SHALL support TLS for Leader-to-Worker Node communication on port 4200.
- The system SHALL support configuring Leader TLS via UI, `instance.yml`, or environment variable `CRIBL_DIST_LEADER_URL=tls://<authToken>@leader:4200`.
- The system SHALL enable TLS by default for Cribl.Cloud deployments.
- The system SHALL automatically switch bootstrap scripts to `https://` when Leader TLS is enabled.

### Requirement: Mutual TLS (mTLS)
- The system SHALL support mutual TLS (client certificate authentication) for sources and destinations.
- The system SHALL support configuring "Authenticate Client" on sources to require client certificate presentation.
- The system SHALL support CA certificate chain validation for client certificates.
- The system SHALL support mTLS for Cribl.Cloud deployments using trusted CA certificate chains.

### Requirement: TLS for Sources and Destinations
- The system SHALL support per-source and per-destination TLS configuration with certificate selection from the Worker Group certificate store.
- The system SHALL support uploading certificate files, private keys, passphrases, and CA certificate chains per Worker Group.
- The system SHALL require certificates to be stored outside `$CRIBL_HOME` on Worker Nodes, as config bundle deployments remove files within that directory.

### Requirement: Leader Auth Token Security
- The system SHALL automatically generate a secure, random auth token for new installations.
- The system SHALL require auth tokens of at least 14 characters including uppercase letters, lowercase letters, and numbers.
- The system SHALL restrict auth token characters (v4.6.1+) to: `a-z`, `A-Z`, `0-9`, `_`, `!`, `-`, and prohibit angle brackets, quotes, braces, pipes, backslashes, carets, backticks, and whitespace.
- The system SHALL support auth token modification via UI (Settings > Global > System > Distributed Settings > Leader Settings), CLI (`./cribl mode-master -u <token>`), or Docker Compose configuration.
- The system SHALL NOT allow direct manual editing of `instance.yml` for auth token changes; provided tools must be used to ensure proper encryption.
- The system SHALL break Leader-Worker communication if the auth token is changed without updating all Worker Nodes.
- The system SHALL store the auth token in `leader.yml` (taking precedence over `instance.yml`) starting in version 4.7 for HA deployments.

### Requirement: Secrets Management
- The system SHALL provide a centralized secrets store for managing authentication tokens, username/password combinations, and API key/secret key pairs.
- The system SHALL support three secret types:
  - **Text**: a single secret value.
  - **API Key and Secret Key**: separate fields for both components; the only type supported for AWS-based Sources, Collectors, and Destinations.
  - **Username with Password**: separate credential fields enabling Basic Authentication.
- The system SHALL support accessing secrets programmatically via the `C.Secret` function within configurations.
- The system SHALL support CLI-based encryption of sensitive values to prevent them from appearing in UI or version control.
- The system SHALL encrypt secrets using the `cribl.secret` file, which is unique per Worker Group.
- The system SHALL store the `cribl.secret` file at `$CRIBL_HOME/local/cribl/auth/` (single-instance) or `$CRIBL_HOME/groups/<group-name>/local/cribl/auth/` (distributed).

### Requirement: Encryption Key Management
- The system SHALL support creating encryption keys with configurable: Key ID (auto-generated), encryption algorithm (`aes-256-cbc` default, or `aes-256-gcm`), KMS provider, key class, expiration date, and initialization vector (IV) settings.
- The system SHALL support IV size of 12-16 bytes for AES-256-GCM.
- The system SHALL support key classes for granular access control, enabling compartmentalized encryption where users can be granted access to specific key classes.
- The system SHALL store encryption keys in `keys.json`, encrypted using `cribl.secret`.
- The system SHALL monitor `keys.json` every 60 seconds for changes.
- The system SHALL require access to the same keys used for encryption, in the Cribl instance where encryption happened, for decryption operations.

### Requirement: KMS Provider Configuration
- The system SHALL support three KMS providers:
  - **Stream Internal (local)**: built-in KMS storing `cribl.secret` on the filesystem (all license tiers).
  - **HashiCorp Vault** (Enterprise license): stores `cribl.secret` in Vault, removing it from the local filesystem. Supports Token-based, AWS IAM (Auto/Manual), or AWS EC2 authentication. Requires KVv2 secrets engine.
  - **AWS KMS** (Enterprise license): stores `cribl.secret` in AWS KMS, removing it from the local filesystem. Supports Auto (IAM role/environment variables) or Manual (static credentials) authentication. Requires `kms:Encrypt` and `kms:Decrypt` IAM permissions.
- The system SHALL remove the `cribl.secret` file from the filesystem when an external KMS provider is configured.
- The system SHALL require distinct KMS configuration per Leader Node and per Worker Group in distributed deployments.

### Requirement: Data Encryption in Motion
- The system SHALL support real-time field-level and pattern-level encryption within events using the `C.Crypto.encrypt()` expression in a Mask Function.
- The system SHALL support `aes-256-cbc` (default) and `aes-256-gcm` encryption algorithms for data-in-motion encryption.
- The system SHALL support optional initialization vector (IV) seeding for enhanced randomness (auto-enabled for `aes-256-gcm`, optional for `aes-256-cbc`).

### Requirement: Data Encryption at Rest
- The system SHALL NOT provide built-in data-at-rest encryption for event data; filesystem-level or hardware-level encryption (e.g., self-encrypting drives) must be implemented independently.
- The system SHALL encrypt sensitive configuration elements (Source/Destination credentials, API keys, TLS certificates, `secrets.yml` entries) at rest using the `cribl.secret` master key.
- Cribl.Cloud SHALL provide built-in encryption for data at rest within Cribl.Cloud infrastructure.

### Requirement: FIPS Mode
- The system SHALL support FIPS mode enablement via the `fips` toggle in `cribl.yml`.
- The system SHALL require FIPS mode to be enabled before starting Cribl Stream for the first time; it cannot be enabled retroactively.

### Requirement: Network Security and Ports
- The system SHALL use the following default ports:
  - TCP 9000: UI access (Leader and Worker Nodes), configurable via `cribl.yml`.
  - TCP 4200: Leader-Worker heartbeat, metrics, and notifications.
  - TCP 443: Worker bootstrapping and CDN config downloads (Cribl.Cloud/hybrid), Cribl Copilot (`ai.cribl.cloud`), OIDC auth.
  - TCP 389: LDAP auth (non-TLS).
  - TCP 636: LDAP auth (TLS).
- The system SHALL require a SOCKS (Layer 4) proxy for Leader-Worker communication through proxies; HTTP proxies are incompatible with the raw TCP streams on port 4200.
- The system SHALL support disabling API service exposure on Worker Nodes (toggle Listen on port off in API Server Settings).
- The system SHALL support disabling direct browser access to Worker Node UIs in Enterprise Distributed deployments, forcing access through the Leader via tunneling.
- The system SHALL support firewalld integration for hardened OS deployments, requiring TCP ports 4200 and 9000 on Leaders and port 9000 plus Source ports on Workers.

### Requirement: Network Isolation
- Cribl.Cloud SHALL provide dedicated virtual private cloud (VPC) per Workspace for complete data and user isolation.
- The system SHALL support deployment on a dedicated network segment to minimize exposure (on-prem recommendation).

### Requirement: DPI/IPS Exclusions
- The system SHALL recommend excluding Cribl data and control-plane streams from Deep Packet Inspection (DPI) and Intrusion Prevention Systems (IPS) to prevent performance instability on high-volume streams.

### Requirement: Audit Logging
- The system SHALL maintain an `audit.log` file in `$CRIBL_HOME/log/` tracking file operations including create, update, commit, deploy, and delete actions.
- The system SHALL maintain an `access.log` file documenting all API calls.
- The system SHALL maintain a `ui-access.log` file monitoring UI component interactions.
- The system SHALL maintain a `cribl.log` principal log including telemetry and license-validation logs.
- The system SHALL maintain a `notifications.log` recording notification events with timestamps.
- The system SHALL log authentication events including successful logins, failed logins, LDAP searches, and provider errors with fields: `time` (ISO 8601), `message`, `cid`, `channel`, `level`, `user`, `username`, `provider`, `searchBase`, `filter`, `memberOf`, `dn`, and error details.
- The system SHALL expose logs via the UI at Monitoring > Logs.
- The system SHALL implement automatic log rotation at 5 MB per file and retain the five most recent rotated files per log.
- The system SHALL support configurable log verbosity levels per logging channel.
- The system SHALL generate additional logs in distributed deployments: Leader Node logs, service-specific logs (`log/service/`), Worker Group logs (`log/group/GROUPNAME`), and Worker Node logs (`log/worker/N/`).
- The system SHALL log `_raw stats` at 1-minute intervals from Worker processes, including inEvents, outEvents, inBytes, outBytes, CPU, memory, persistent queue statistics, and dropped event counts.

### Requirement: Sensitive Field Filtering
- The system SHALL support `sensitiveFields` configuration in `cribl.yml` to filter credentials from API endpoint responses (`/inputs` and `/outputs`).

### Requirement: Custom HTTP Headers
- The system SHALL support configuring custom HTTP headers sent with every API response (e.g., Content Security Policy headers) at the Worker Group level under API Server Settings > Advanced > HTTP Headers.

### Requirement: PII Detection
- The system SHALL support enabling periodic detection of PII in Worker Groups via the `pii.enablePiiDetection` configuration option.

### Requirement: Exec Source Security
- The system SHALL support the `CRIBL_NOEXEC` environment variable to disable arbitrary command execution via the Exec source, reducing the attack surface.

### Requirement: Hardened OS Support
- The system SHALL support deployment on RHEL 8 STIG-compliant systems with SELinux, firewalld, and fapolicyd integration.
- The system SHALL support fapolicyd trust-file configuration to authorize Cribl Stream binaries on systems with file access policy enforcement.

### Requirement: Git Repository Security
- The system SHALL recommend keeping remote Git repositories used for configuration backup private to prevent unauthorized access to sensitive configuration data.

### Requirement: User Management
- The system SHALL support local user creation and management via Settings > Global > Access Management > Local Users.
- The system SHALL support user properties: `username`, `first`, `last`, `roles`, `disabled`, and hashed `passwd`.
- The system SHALL support disabling user accounts without deletion.
- The system SHALL support managing Worker/Edge node user passwords via the Leader UI under Worker Group > Group Settings > Local Users.
- The system SHALL support changing the default admin password immediately after installation.

### Requirement: Compliance
- Cribl.Cloud SHALL maintain SOC 2 Type II certification.
- Cribl.Cloud SHALL be GDPR-compliant.
- Cribl.Cloud SHALL enforce minimum 12-character passwords with lowercase, uppercase, numbers, and special characters.

---

Sources:
- [Authentication | Cribl Docs](https://docs.cribl.io/stream/4.9/authentication/)
- [Roles and Policies | Cribl Docs](https://docs.cribl.io/iam/roles-policies-model/)
- [Permissions | Cribl Docs](https://docs.cribl.io/iam/permissions/)
- [Roles | Cribl Docs](https://docs.cribl.io/stream/roles/)
- [Access Management | Cribl Docs](https://docs.cribl.io/stream/access-management/)
- [Authenticate with the Cribl API | Cribl Docs](https://docs.cribl.io/cribl-as-code/api-auth/)
- [Configure TLS for API and UI Access | Cribl Docs](https://docs.cribl.io/stream/securing-tls/)
- [TLS Defaults and System-wide Settings | Cribl Docs](https://docs.cribl.io/stream/securing-tls-overview/)
- [Secure Cribl.Cloud with TLS and mTLS | Cribl Docs](https://docs.cribl.io/stream/securing-tls-cloud/)
- [Secure Leader/Nodes Communication | Cribl Docs](https://docs.cribl.io/stream/securing-communications/)
- [Secure the Leader Auth Token | Cribl Docs](https://docs.cribl.io/stream/securing-auth-token/)
- [Secure Sources and Destinations with Certificates | Cribl Docs](https://docs.cribl.io/stream/securing-sources-dest/)
- [Create and Manage Secrets | Cribl Docs](https://docs.cribl.io/stream/4.8/securing-secrets/)
- [Create and Manage Encryption Keys | Cribl Docs](https://docs.cribl.io/stream/securing-encryption-keys/)
- [Configure KMS Providers | Cribl Docs](https://docs.cribl.io/stream/securing-kms-config/)
- [Encryption of Data in Motion | Cribl Docs](https://docs.cribl.io/stream/securing-data-encryption/)
- [Secure your On-Prem/Hybrid Deployment | Cribl Docs](https://docs.cribl.io/stream/securing-onprem/)
- [Secure your Cribl.Cloud Deployment | Cribl Docs](https://docs.cribl.io/stream/4.16/securing-cloud/)
- [Ports | Cribl Docs](https://docs.cribl.io/stream/ports/)
- [Internal Logs | Cribl Docs](https://docs.cribl.io/stream/internal-logs/)
- [Sample Logs for Login Scenarios | Cribl Docs](https://docs.cribl.io/stream/sample-login-logs/)
- [cribl.yml | Cribl Docs](https://docs.cribl.io/stream/4.9/criblyml/)
- [Running Cribl Stream on a Hardened OS | Cribl Docs](https://docs.cribl.io/stream/usecase-rhel8-stig/)
- [Service Accounts | Cribl Docs](https://docs.cribl.io/stream/service-accounts/)
- [SSO on Cribl.Cloud | Cribl Docs](https://docs.cribl.io/stream/sso-cloud/)
- [SSO in On-Prem Deployments | Cribl Docs](https://docs.cribl.io/stream/sso-on-prem/)
- [Manage Secrets and Keys | Cribl Docs](https://docs.cribl.io/stream/manage-secrets-and-keys/)
- [Firewalls and Network Security | Cribl Docs](https://docs.cribl.io/reference-architectures/cva-network-firewall/)
