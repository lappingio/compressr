---

## Compressr Security Review

**Reviewer**: Security engineering perspective (data pipeline security)
**Date**: 2026-03-14
**Scope**: Architecture proposals, spec documents, Cribl research, and current codebase state

---

### 1. Gaps in the Current Proposals

**No RBAC model exists.** The OIDC spec authenticates users but never authorizes them. Every authenticated user has identical permissions -- they can create/delete sources, destinations, pipelines, and routes. There is no concept of roles, permissions, or scoping. Cribl has a full RBAC model with roles like admin, editor, reader, and owner. Compressr treats authentication as the finish line when it is only the starting gate.

**No audit logging is specified anywhere.** None of the specs -- authentication, REST API, sources, destinations, pipelines -- mention logging who did what and when. For a system that handles sensitive log data, this is a critical omission. You need immutable audit records of every configuration change (who created/modified/deleted a source, destination, pipeline, route), every authentication event (login, logout, failed login, token creation/revocation), and every administrative action.

**No rate limiting on any endpoint.** The REST API spec defines CRUD for sources, destinations, pipelines, and routes but says nothing about rate limiting. The auth endpoints (token creation, login) are wide open to brute force. Cribl explicitly supports configurable login rate limits and SSO callback rate limits.

**No input validation depth for API payloads.** The REST API spec mentions 422 for invalid configs but does not specify payload size limits, field length limits, or depth limits on nested JSON. An attacker could submit a multi-megabyte pipeline configuration or deeply nested JSON to exhaust memory.

**The health endpoint exposes an unauthenticated information surface.** The spec says `/health` requires no auth and returns health status. What exactly does it return? If it includes version numbers, node counts, DynamoDB connectivity status, or internal hostnames, it becomes a reconnaissance tool. The health endpoint should return only a boolean liveness signal.

**No secret rotation mechanism.** OIDC client secrets, HEC tokens, Elasticsearch API keys, S3 credentials -- all are stored in DynamoDB configs. There is no spec for rotating these secrets without downtime, no mechanism to detect stale secrets, and no integration with external secret managers (Vault, AWS Secrets Manager, AWS KMS).

**No local authentication fallback.** The OIDC spec makes OIDC the only auth mechanism. If the OIDC provider is down, every user is locked out. There is no emergency access path -- no break-glass local admin account, no recovery token. Cribl explicitly supports local auth fallback for exactly this reason.

---

### 2. Data-in-Transit Security

**Erlang distribution is unencrypted by default.** This is the most critical gap. The project relies on Erlang distributed clustering for inter-node communication. By default, Erlang distribution uses plain TCP with no encryption. Any node that can reach port 4369 (EPMD) and the distribution port can join the cluster and execute arbitrary code on every node. This is not theoretical -- it is the single fastest way to fully compromise a compressr deployment.

Mitigations required before production:
- Enable TLS for Erlang distribution via `inet_tls_dist` (available since OTP 20). This must be configured in `vm.args` or `env.sh` with proper certificates.
- Set a strong Erlang cookie (not the default). The cookie is a shared secret and must be treated as a credential.
- Restrict EPMD and distribution ports via firewall rules or disable EPMD entirely and use fixed distribution ports.

**Phoenix endpoint has no TLS configured.** The `runtime.exs` has TLS commented out. The endpoint listens on plain HTTP. The `force_ssl` option is commented out. For a system where OIDC tokens, API tokens, session cookies, HEC tokens, and configuration payloads (containing destination credentials) traverse the wire, this must be TLS-only in production.

**Source listeners lack TLS enforcement.** The syslog source spec says TLS is "optional" on TCP. The HEC source spec says TLS is "optional." For sources ingesting sensitive data (security logs, application logs with PII), TLS should be the default, not the exception. At minimum, the spec should require that TLS is configurable per-source and document that running without TLS means data is in cleartext on the network.

**Destination connections have no TLS spec.** The Elasticsearch destination mentions authentication (basic, API key) but says nothing about whether the connection uses TLS. The Splunk HEC destination mentions nothing about TLS. The S3 destination inherits TLS from the AWS SDK, but this is implicit, not specified. Every destination that sends data over a network must have explicit TLS configuration with certificate validation enabled by default.

**No mTLS support is specified.** For high-security environments (healthcare, financial), mutual TLS is required to ensure that only authorized clients can send data to sources and that destinations verify the identity of the compressr node. The source and destination specs should include mTLS as a configurable option.

---

### 3. Data-at-Rest Security

**Disk buffers will contain sensitive data in plaintext.** The architecture specifies that source nodes buffer post-pipeline events to local disk when destinations are unavailable. These buffers will contain the actual event data -- potentially including credentials, PII, healthcare records, or security telemetry. Neither RocksDB nor SQLite encrypt data at rest by default. If a node's disk is compromised (stolen, decommissioned without wiping, accessible via another process), all buffered data is exposed.

Recommendation: Use RocksDB with encryption at rest (via `rocksdb::EncryptionProvider`) or SQLite with SQLCipher. Alternatively, rely on filesystem-level encryption (LUKS, dm-crypt, EBS encryption) and document this as a deployment requirement. This is what Cribl does -- they explicitly state they do not provide built-in data-at-rest encryption and require filesystem/hardware-level encryption.

**DynamoDB stores credentials in configuration records.** Source configurations contain HEC tokens. Destination configurations contain Elasticsearch passwords, API keys, S3 credentials, and Splunk HEC tokens. These are stored in DynamoDB. The specs do not mention encrypting these sensitive fields before storage. DynamoDB supports encryption at rest via AWS-managed keys, but that only protects against AWS infrastructure compromise -- it does not protect against anyone with DynamoDB read access (an overly broad IAM policy, a compromised application credential).

Recommendation: Encrypt sensitive configuration fields (passwords, tokens, API keys) at the application level before storing in DynamoDB. Use a master encryption key that is itself stored in AWS KMS, not in DynamoDB. Cribl does exactly this with their `cribl.secret` file and KMS provider integration.

**OIDC client secrets are stored in DynamoDB.** The OIDC provider configuration includes client secrets. These must not be stored in plaintext. They should be encrypted with a key managed by AWS KMS.

**Session data in DynamoDB may contain tokens.** The authentication spec says sessions are stored in DynamoDB with "token refresh" support. If refresh tokens are stored in DynamoDB, they must be encrypted. A compromised refresh token allows an attacker to mint new access tokens indefinitely.

---

### 4. Access Control

**OIDC is necessary but insufficient.** OIDC answers "who is this user?" It does not answer "what is this user allowed to do?" The system needs an authorization model layered on top of authentication.

**Missing: Role-Based Access Control (RBAC).** At minimum, before production:
- Define roles: `admin` (full access), `editor` (create/modify sources, destinations, pipelines), `viewer` (read-only)
- Map OIDC claims (groups, roles) to compressr roles
- Enforce authorization on every API endpoint and LiveView action
- Ash Framework has built-in authorization policies -- use them

**Missing: API token scoping.** The REST API spec says tokens are "scoped to the user who created it" but does not define what operations the token can perform. If a user creates an API token for a CI/CD pipeline that only needs to read source status, that token should not be able to delete destinations. Token scoping (read-only, specific resource types, specific operations) is required for least-privilege access.

**Missing: Service accounts.** The API token spec ties tokens to human users. Automated systems (CI/CD, Terraform, monitoring) need service accounts that are not tied to a human identity. When a human leaves the organization, their tokens should be revocable without breaking automation.

**Session cookie security is weak.** The endpoint uses cookie-based sessions with `signing_salt: "711OKOjo"` -- a hardcoded, low-entropy salt. The comment says "Set :encryption_salt if you would also like to encrypt it" but encryption is not enabled. Session cookies should be signed AND encrypted, with salts derived from `SECRET_KEY_BASE`, and the `secure: true` flag must be set to prevent transmission over HTTP. The `same_site: "Lax"` setting is acceptable but `"Strict"` would be better for admin-only interfaces.

---

### 5. Pipeline Security

**The expression language is the largest attack surface in the system.** The project spec describes a "VRL-inspired expression language compiled to BEAM bytecode." This is where the most sophisticated attacks will occur.

**Code execution risk via BEAM bytecode compilation.** If expressions compile to actual BEAM bytecode or pattern match functions, a carefully crafted expression could potentially escape the sandbox. The spec says "no loops, no side effects, no filesystem/network access" but the implementation must enforce this at the compiler level, not just by convention. The expression language parser must reject any construct that could access `:erlang`, `:os`, `:file`, `:gen_tcp`, or any other module that provides system-level access. This needs a formal allow-list of permitted operations, not a deny-list.

**Data exfiltration via pipelines.** A malicious or compromised user could create a pipeline that copies sensitive fields from events and routes them to an attacker-controlled destination. For example: create an Eval function that copies `credit_card` into a field that gets forwarded to an S3 bucket the attacker owns. Without RBAC and audit logging, there is no way to detect or prevent this.

**Regex denial of service.** The Mask and Regex Extract functions accept user-provided regular expressions. Catastrophic backtracking on crafted regexes can cause exponential CPU consumption. Elixir's `:re` module (PCRE-based) is susceptible to ReDoS. Mitigation: set a timeout on regex execution, or use RE2 (via a NIF like `re2`) which guarantees linear time complexity.

**Lookup function file access.** The Lookup function spec says it supports CSV files. Where are these files stored? Who can upload them? If lookup files are uploaded via the API, this is a file-write primitive. If lookup file paths are user-specified, this is a path traversal risk. The spec must constrain lookup files to a specific directory and validate filenames.

---

### 6. Multi-Tenancy Concerns

**The architecture has no tenancy model.** All sources, destinations, pipelines, and routes exist in a flat namespace. If multiple teams share one compressr cluster, every user can see and modify every configuration. There is no workspace, namespace, or team isolation.

**Event data crosses team boundaries.** Without tenant-scoped routing, events from one team's sources could be visible in another team's pipelines. This is a confidentiality violation in regulated industries.

**Resource exhaustion attacks.** Without per-tenant resource limits, one team could create hundreds of sources or pipelines, configure massive batch sizes, or trigger S3 Glacier restores that consume all available disk I/O and network bandwidth. The buffer QoS system is destination-scoped, not tenant-scoped.

**Recommendation for MVP:** If multi-tenancy is not a priority for the SMB market, document explicitly that compressr is single-tenant. Add a tenancy model (workspaces or namespaces) before targeting multi-team deployments. This is hard to retrofit.

---

### 7. Supply Chain and Dependency Security

**NIF risks are real.** The architecture mentions potential Rust NIFs for expression evaluation performance and RocksDB via the Rox NIF. NIFs run in the BEAM VM's OS process -- a crash in a NIF takes down the entire VM, and a memory safety bug in a NIF is exploitable. This is not a reason to avoid NIFs, but it means:
- NIF dependencies (rox, any Rust NIF) must be audited for memory safety
- NIF inputs must be validated in Elixir before crossing the NIF boundary
- Consider using dirty schedulers for NIF calls to avoid blocking the VM scheduler

**Dependency hygiene.** The project uses Hex packages. There is no mention of:
- `mix audit` for checking known vulnerabilities in dependencies
- Lockfile verification (`mix.lock` should be committed and checked in CI)
- Dependency pinning strategy (exact versions vs. semver ranges)
- A process for evaluating new dependencies before adoption

**ex_aws credentials.** The S3 source and destination use `ex_aws`. The project must ensure that AWS credentials are loaded via IAM roles (instance profiles, IRSA for EKS) rather than hardcoded access keys. The `ex_aws` library supports this, but the configuration must make IAM roles the default and static credentials the exception.

---

### 8. Compliance Considerations

**HIPAA (healthcare data in the pipeline):**
- ePHI flowing through compressr requires encryption in transit (TLS) and at rest (buffer encryption or filesystem-level encryption)
- Audit logging of all access to ePHI data is mandatory -- the lack of audit logs is a HIPAA blocker
- Business Associate Agreements (BAAs) would be needed with any cloud service storing ePHI
- The Mask function should be documented as a tool for PHI de-identification, but note it does not satisfy Safe Harbor de-identification unless all 18 identifier categories are addressed

**SOC 2:**
- Access control (missing RBAC) is a foundational SOC 2 requirement
- Audit logging (completely absent) is required for the monitoring trust service principle
- Change management logging (who changed what configuration, when) is required
- Encryption of sensitive data in transit and at rest is expected

**GDPR:**
- If compressr processes personal data of EU residents, the Mask function becomes a data minimization tool
- Right to erasure: if personal data is buffered to disk or stored in S3 destinations, there must be a mechanism to identify and delete specific records
- Data Processing Agreements with downstream destination operators may be required
- The S3 Glacier replay feature could re-surface personal data that was supposed to be deleted

**PCI DSS:**
- Credit card data flowing through pipelines must be masked before storage (the Mask function serves this purpose)
- Audit trails of all access to cardholder data are required
- Network segmentation between cardholder data environment and other systems

---

### 9. Prioritized Recommendations

#### Must-have before any production use (Critical):

1. **Encrypt Erlang distribution.** Enable `inet_tls_dist` with proper certificates. Without this, any node on the network can join the cluster and execute arbitrary code. This is a full-compromise vulnerability.

2. **Enforce TLS on the Phoenix endpoint.** Enable HTTPS, set `force_ssl: [hsts: true]`, and fix the session cookie to use `secure: true` and `encryption_salt`. The current hardcoded signing salt must be replaced.

3. **Implement RBAC.** Define roles (admin, editor, viewer at minimum), map OIDC groups/claims to roles, enforce authorization on every API endpoint and LiveView action using Ash policies.

4. **Add audit logging.** Log every authentication event and every configuration change (source/destination/pipeline/route CRUD) with timestamp, user identity, action, resource ID, and source IP. Store audit logs separately from application logs and make them append-only.

5. **Encrypt sensitive config fields in DynamoDB.** OIDC client secrets, HEC tokens, Elasticsearch passwords, S3 credentials, and API key hashes must be encrypted at the application level using a key stored in AWS KMS. Do not rely solely on DynamoDB encryption at rest.

6. **Sandbox the expression language.** Implement a strict allow-list of permitted operations. The compiler must reject any attempt to access system modules (`:erlang`, `:os`, `:file`, `:gen_tcp`, `:code`, `:io`). Add a test suite that specifically tries to escape the sandbox.

7. **Add rate limiting.** Rate limit authentication endpoints (login, token creation), API endpoints (per-user, per-IP), and OIDC callback endpoints.

8. **Add a local emergency access account.** Provide a break-glass mechanism (environment variable or config file) for a local admin account when OIDC is unavailable. Document the security implications.

#### Should-have before general availability (High):

9. **TLS for all source listeners by default.** Syslog TCP and HEC should default to TLS enabled, not disabled. Provide clear documentation for opting out.

10. **TLS configuration for all destination types.** Every destination that communicates over a network must have explicit TLS configuration with `verify_peer` enabled by default.

11. **API token scoping.** Allow tokens to be created with specific permission scopes (read-only, specific resource types).

12. **ReDoS protection.** Either set timeouts on regex execution in Mask and Regex Extract functions, or use RE2 instead of PCRE.

13. **Lookup file sandboxing.** Constrain lookup CSV files to a designated directory. Validate filenames for path traversal. Size-limit uploads.

14. **Payload size and depth limits.** Set maximum request body size on the Phoenix endpoint. Limit JSON nesting depth in API payloads.

15. **Dependency auditing.** Add `mix_audit` to the project and run it in CI. Pin dependency versions.

#### Nice-to-have for mature deployments (Medium):

16. **mTLS support for sources and destinations.** Allow operators to require client certificates on source listeners and present client certificates to destinations.

17. **Secret rotation workflow.** Support rotating HEC tokens, OIDC client secrets, and destination credentials without downtime (dual-read during rotation window).

18. **Service accounts.** Create non-human identities for automation that are independent of user lifecycle.

19. **Health endpoint minimization.** Ensure `/health` returns only `{"status": "ok"}` and no system internals.

20. **Multi-tenancy foundation.** Add namespace/workspace isolation if multi-team use is anticipated. This is much harder to add later.

21. **PII detection pipeline function.** Add a built-in function that detects and flags common PII patterns (SSN, credit cards, email addresses) to help operators comply with data handling policies.

22. **FIPS mode support.** If targeting government or healthcare, the Erlang runtime and any NIFs must use FIPS-validated cryptographic modules.

---

### Summary

The compressr project has the right instincts -- OIDC from day one, hashed API tokens, HEC token validation on sources. But the proposals have significant gaps between authentication (proving identity) and authorization (controlling access). The most dangerous issue is the unencrypted Erlang distribution, which allows trivial cluster takeover. The second most dangerous is the lack of encryption for sensitive configuration data stored in DynamoDB. The third is the expression language, which compiles to BEAM bytecode and must be rigorously sandboxed to prevent code execution and data exfiltration.

The project should address items 1-8 before any production deployment. Items 9-15 should be completed before general availability. Items 16-22 can be addressed as the project matures and the user base expands.
