## Packs

### Requirement: Pack Definition and Purpose
- The system SHALL provide Packs as portable configuration bundles that consolidate pipelines, sources, destinations, routes, knowledge objects, and sample data into a single shareable unit.
- The system SHALL enable Packs to be developed, tested, version-controlled, and distributed across multiple Worker Groups or organizations.

### Requirement: Pack Contents
- The system SHALL allow Packs to contain: Routes (with filters and pipelines), Pipelines (pre-processing and post-processing), Knowledge objects (variables, regexes, schemas, lookups), Sample data files, Sources, Destinations, Scripts, and TLS certificate references (by name only).
- The system SHALL NOT allow the following source types to be packaged: Cribl Internal, K8s Metrics, K8s Logs, and K8s Events.
- The system SHALL NOT include TLS certificate file contents in Pack exports; only certificate names (references) SHALL be stored for security purposes.

### Requirement: Pack Identification
- The system SHALL require each Pack to have a unique Pack ID within a Worker Group.
- The system SHALL require a Version field on every Pack.
- The system SHALL support an optional Minimum Stream Version field specifying the lowest compatible Cribl Stream version.
- The system SHALL support optional metadata fields: Display Name, Description, Author, Tags, and Logo (PNG or JPG/JPEG, max 2 MB, recommended 280x50 px with transparency).
- The system SHALL allow multiple Packs to share the same Display Name (only Pack ID must be unique).

### Requirement: Pack Creation
- The system SHALL allow creating Packs via Processing > Packs > Add Pack > Create Pack.
- The system SHALL persist changes automatically to the Pack as they are saved.

### Requirement: Pack Import Methods
- The system SHALL support importing Packs from four sources: Dispensary (pre-built community packs), File (local `.crbl` files), URL (public or internal URLs), and Git Repository (branches or tags from public/private repos).
- The system SHALL support private Git repositories using the format `https://<username>:<token>@<repo-address>`.
- The system SHALL allow writeback capability for Git branch imports but NOT for tag imports.
- The system SHALL require the Leader Node to have internet access for importing from public URLs; Workers SHALL be deployable without internet access after the Leader imports the Pack.

### Requirement: Pack Conflict Resolution
- The system SHALL detect duplicate Pack IDs during import and present two options: Assign New Pack ID (import as a separate Pack) or Enable Overwrite (replace existing Pack completely).
- The system SHALL irreversibly delete existing Pack configuration when overwrite is selected.

### Requirement: Pack Export
- The system SHALL support three export modes: Merge (force-merge local modifications, removes encrypted fields), Default Only (export original configuration without local modifications), and Merge Safe (deprecated; conservatively attempts safe merging, blocks on conflicts).
- The system SHALL default the Export ID to the current Pack ID plus version number; it SHALL be modifiable during export.
- The system SHALL remove all encrypted fields during merge-mode export, requiring re-entry upon import.

### Requirement: Pack Variables and Templatization
- The system SHALL support variable binding within Packs to make configurations portable across environments.
- The system SHALL present a "Configure Variables" prompt post-import if the Pack contains variable bindings.
- The system SHALL allow variables to replace fixed values with dynamic references that adapt to local Worker Group context.

### Requirement: Pack Deployment Scoping
- In single-instance deployments, the system SHALL store Packs globally at `$CRIBL_HOME/default/`.
- In distributed deployments, the system SHALL associate Packs with specific Worker Groups and store them at `$CRIBL_HOME/groups/<groupName>/default/`.
- The system SHALL display a PACK badge in the UI for Pack-originated configuration items.
- The system SHALL provide dedicated Packs throughput tracking on the Monitoring page.

### Requirement: Pack Sharing in Distributed Deployments
- The system SHALL support copying Packs between Worker Groups via the Packs page or the Cribl API.
- The system SHALL support single or batch copy operations with optional overwrite toggling.

### Requirement: Pack Upgrade
- The system SHALL support upgrading existing Packs via Pack Options > Upgrade.
- The system SHALL prevent overwriting Packs that contain user modifications to avoid data loss.
- The system SHALL require Commit and Deploy after Pack changes.

### Requirement: Pack Version Compatibility
- The system SHALL reject Packs created in Cribl Stream 4.0.x or later when imported into older versions, displaying a "should NOT have additional properties" error.

### Requirement: Pack Settings Management
- The system SHALL provide a README tab supporting markdown documentation with View/Edit toggle.
- The system SHALL provide a Settings tab for updating version, description, and author metadata.

### Requirement: Pack Publication Standards (Dispensary)
- The system SHALL require Pack IDs to start with `cc-` (community-contributed) or `cribl-` (Cribl-contributed); Packs not meeting this requirement SHALL be rejected.
- The system SHALL require Pack IDs to follow the format `<source>-<productArea>-<dataVendor>-<dataType>` using lowercase with hyphens.
- The system SHALL require a minimum initial publication version of `0.1.0` using Semantic Versioning.
- The system SHALL require each published Pack to include at least one Route beyond the default, at least one custom Pipeline, at least one sample data file per Pipeline (with 20+ events minimum, 100+ recommended), and a README with sections: About, Deployment, Release Notes, Contributing, and License.
- The system SHALL require that sample data files never include PII, customer data, or customer hostnames.
- The system SHALL require every Pipeline to begin with a Comment Function providing an operation overview.
- The system SHALL require every Function to have a Description explaining its action.

### Requirement: Pack Dispensary Ownership
- The system SHALL support ownership transfer of Dispensary Packs via Configure > Change Owner.
- The system SHALL give the recipient 24 hours to accept the transfer.
- The system SHALL notify both parties of the transfer.

---

## Knowledge Objects

### Requirement: Knowledge Library Overview
- The system SHALL provide a centralized Knowledge Library accessible via Processing > Knowledge containing: Lookups, Event Breakers, Parsers, Global Variables, Sample Files, Regexes, Grok Patterns, JSON Schemas, Parquet Schemas, Database Connections, HMAC Functions, and AppScope Configs (deprecated).
- The system SHALL support a single-point-of-change architecture where modifying a Knowledge object propagates to all references.
- The system SHALL support hierarchical organization at Worker Group and Pack levels.

### Requirement: Knowledge Object Scoping
- The system SHALL scope Knowledge objects to their defining Worker Group or Pack.
- The system SHALL restrict usage of a Knowledge object to within its scope (the Worker Group or Pack where it was defined).
- The system SHALL support Pack-level Knowledge objects that override Worker Group-level objects sharing identical names.

---

## Lookups

### Requirement: Lookup File Types
- The system SHALL support CSV files (`.csv`), compressed CSV files (`.csv.gz` via gzip), and binary IP database files (MaxMind `.mmdb`, IPinfo) for lookups.
- The system SHALL allow uploading `.mmdb` binary files but SHALL NOT allow editing them through the UI.

### Requirement: Lookup Storage Modes
- The system SHALL support two storage modes: In-Memory (stores the entire file in memory, packaged with deployment) and Disk-Based (streams the file to the Worker separately, accessed from disk at runtime).
- The system SHALL NOT allow reverting a disk-based lookup back to in-memory once converted.
- Cribl Edge SHALL support only in-memory lookups, not disk-based.

### Requirement: In-Memory Lookup Capabilities
- The system SHALL support exact match, regex match, and CIDR match modes for in-memory lookups.
- The system SHALL support in-place editing of in-memory lookups via the UI.
- The system SHALL support configurable reload periods for in-memory lookups.
- The system SHALL automatically index the left-most column of in-memory lookup files.

### Requirement: Disk-Based Lookup Capabilities
- The system SHALL support exact match only for disk-based lookups (no regex or CIDR).
- The system SHALL NOT support in-place editing of disk-based lookups (requires download, delete, re-upload).
- The system SHALL NOT support reload periods for disk-based lookups.
- The system SHALL allocate a 16 MB cache per Worker Process for each lookup function referencing a disk-based file.
- The system SHALL support a maximum of 4 indexes per disk-based file.
- The system SHALL require all fields referenced in the Lookup Function to be indexed for disk-based lookups, or lookups SHALL fail.

### Requirement: Lookup Size Limits
- The system SHALL enforce a maximum of 500 MB per individual lookup file.
- The system SHALL enforce a total storage limit of 2 GB across all lookup files.

### Requirement: Lookup Indexing
- The system SHALL automatically index the left-most column of each lookup file.
- The system SHALL support up to 4 indexes per file.
- The system SHALL support case-sensitive and case-insensitive matching per index.

### Requirement: Lookup File Management
- The system SHALL allow uploading lookup files via Processing > Knowledge > Lookups > Add Lookup File.
- The system SHALL allow creating lookup files via text editor in the UI.
- The system SHALL support optional metadata: Filename, Description, Tags, and Mode (In-Memory or Disk-Based).
- The system SHALL require Commit and Deploy to distribute lookup changes to Workers.
- The system SHALL support updating lookups via the API for automated/frequent updates.
- The system SHALL support deletion of lookup files with a confirmation prompt requiring the user to type "DELETE".

### Requirement: Pack-Scoped Lookups
- The system SHALL support uploading lookups within a Pack scope using paths like `$CRIBL_HOME/data/lookups/packs/<pack-name>/<file-name.csv>`.

### Requirement: Lookup Function Configuration
- The system SHALL provide a Lookup Function for enriching events in pipelines.
- The system SHALL support specifying lookup file path or selecting from uploaded files via Knowledge > Lookups.
- The system SHALL support environment variable references in file paths (e.g., `$CRIBL_HOME/file.csv`).
- The system SHALL support three match modes: Exact (default, with optional case-insensitive toggle), Regex (pattern matching, requires no empty rows in lookup file), and CIDR (IP range matching).
- The system SHALL support three match type refinements for CIDR/Regex: First match (most performant), Most specific (scans all entries), and All (returns all matches as arrays).
- The system SHALL default to returning all fields from the lookup if no output fields are specified.
- The system SHALL support custom output field naming with nested addressing.
- The system SHALL support optional default values when a lookup entry is not found.
- The system SHALL support an "Add to raw event" option that appends matched values to `_raw` as key=value pairs.
- The system SHALL use only the value in the key's final instance when duplicate keys exist in the lookup file.
- The system SHALL support a filter expression (JavaScript) to select which events are processed (defaults to `true`).
- The system SHALL support a Final toggle to stop downstream function execution.
- The system SHALL be case-sensitive by default for lookups; an "Ignore case" toggle SHALL be available for Exact mode only.
- The system SHALL support a Reload Period accepting positive integers (seconds) or -1 (disabled/default).

### Requirement: C.Lookup() Expression
- The system SHALL provide `C.Lookup()` for exact matching, `C.LookupCIDR()` for CIDR range matching, `C.LookupIgnoreCase()` for case-insensitive matching, and `C.LookupRegex()` for pattern matching.
- The system SHALL accept parameters: `file` (string, CSV filename), `primaryKey` (string, column name), `otherFields` (string array, columns to include; empty array returns all), and `ignoreCase` (boolean, C.Lookup only).
- The system SHALL support the `.match()` method returning: a boolean (when no field specified), a single value (when one field specified), or an object (when multiple fields or empty array specified).
- The system SHALL limit `C.Lookup` to loading lookup files of up to 10 MB.
- The system SHALL require all match inputs to be strings; numeric fields must be converted using `String()`.
- The system SHALL require `C.LookupRegex` lookup files to contain no empty lines.

### Requirement: Regex Matching in Lookups
- The system SHALL support embedding regular expressions directly within lookup table CSV files for pattern-based matching.
- The system SHALL evaluate regex patterns from the first column of the lookup file against event field values.
- The system SHALL return all columns from the matching row when no output fields are explicitly specified.

---

## Regex Library

### Requirement: Regex Library Structure
- The system SHALL provide a searchable Regex Library accessible via Processing > Knowledge > Regexes.
- The system SHALL ship with 25 pre-built common regex patterns (tagged as "Cribl").
- The system SHALL support user-created custom patterns (tagged as "Custom").
- The system SHALL give custom patterns priority over built-in patterns when naming conflicts occur.
- The system SHALL convert any edited built-in regex to a custom pattern.

### Requirement: Regex Creation and Configuration
- The system SHALL require an ID, regex pattern (JavaScript/ECMAScript flavor), and optional sample data, description, and tags when creating a regex.
- The system SHALL provide a visual match indicator when testing patterns against sample data.
- The system SHALL support a "Save to Library" action for patterns built inline in functions.

### Requirement: Regex Scoping
- The system SHALL scope regexes to their defining Worker Group or Pack; regexes SHALL only be usable within their scope.

### Requirement: Regex Usage in Functions
- The system SHALL integrate regex library patterns with functions including Regex Filter, Regex Extract, and Mask.
- The system SHALL display library regexes as typeahead options in function configuration fields.

### Requirement: Regex Storage
- The system SHALL persist regex patterns in a `regexes.yml` configuration file.

### Requirement: Pre-built Regex Patterns
- The system SHALL include pre-built patterns for common use cases including PII identification (SSNs, international ID numbers), IP addresses, and credit card detection.

---

## Global Variables

### Requirement: Variable Types
- The system SHALL support the following variable types: Number (integers/decimals), String (text sequences), Boolean (true/false), Array (ordered lists), Object (key-value pair structures), Expression (JavaScript code snippets accepting arguments), Encrypted String (sensitive text encrypted on disk, decrypted at runtime), and Any (flexible container accepting any data type).

### Requirement: Variable Access
- The system SHALL make global variables accessible via `C.vars.variableName` in any field supporting JavaScript expressions.
- The system SHALL support dot notation for Object type access: `C.vars.configName.keyName`.
- The system SHALL support indexing for Array type access: `C.vars.arrayName[0]` and method calls: `C.vars.list.includes(value)`.
- The system SHALL support Expression type invocation with arguments: `C.vars.functionName(arg1, arg2)`.

### Requirement: Variable Scope Resolution
- The system SHALL use hierarchical scope resolution where local scopes override broader ones.
- The system SHALL give Pack-level variables precedence over Worker Group variables sharing identical names.
- The system SHALL support three scope levels: Worker Group, Pack, and Single-Instance.

### Requirement: Variable Configuration
- The system SHALL require unique naming for each variable.
- The system SHALL support optional descriptions and tags for documentation and filtering.
- The system SHALL validate values against the selected type.

### Requirement: Encrypted Strings
- The system SHALL store Encrypted String variables encrypted on disk.
- The system SHALL decrypt Encrypted String values at runtime, maintaining plaintext behavior post-decryption.
- The system SHALL designate Encrypted String type as suitable for API keys, passwords, and credentials.

---

## Schema Management

### Requirement: JSON Schemas
- The system SHALL provide a JSON Schema library accessible via Processing > Knowledge > Schemas.
- The system SHALL support JSON Schema standard Drafts 0 through 7.
- The system SHALL support adding schemas with an ID, optional description, and schema content.
- The system SHALL support adding schemas directly to Worker Groups or within Packs.
- The system SHALL propagate changes to a schema to all places where it is referenced.

### Requirement: JSON Schema Validation
- The system SHALL provide the expression `C.Schema('<schema_name>').validate(<object_field>)` for validating objects against defined schemas.
- The system SHALL support using schema validation for routing decisions, event acceptance/rejection, and filtering.

### Requirement: Parquet Schemas
- The system SHALL provide Parquet schemas as a distinct type from JSON schemas; the two types SHALL NOT be interchangeable.
- The system SHALL support automatic schema generation (toggled via Parquet Settings > Automatic schema) that dynamically generates schemas from each file's events.
- The system SHALL support manual/predefined schemas for better performance and control.
- The system SHALL provide sample schemas available for cloning and customization.
- The system SHALL express Parquet schemas in JSON format.

### Requirement: Parquet Schema Data Types
- The system SHALL support all Parquet primitive types, all logical types, and all converted types (legacy format).
- The system SHALL support complex types: Lists (`"type": "LIST"`), Maps (`"type": "MAP"`), and nested list structures.
- The system SHALL support repetition modifiers: `optional: true` (field may be absent), `repeated: true` (field is an array), and required (default, must be present).
- The system SHALL NOT allow both `optional` and `repeated` to be set to true simultaneously.

### Requirement: Parquet Schema Behaviors
- The system SHALL drop rows with mismatched field properties (schema violations).
- The system SHALL omit extra fields (not in schema) from output but write them to parent rows.
- The system SHALL require JSON data to be stringified or drop the row.
- The system SHALL support only `DICTIONARY` encoding (not `PLAIN_DICTIONARY` or `RLE_DICTIONARY`).
- The system SHALL restrict `BYTE_STREAM_SPLIT` encoding to `DOUBLE`/`FLOAT` types only.
- The system SHALL support file extensions: `.parquet`, `.parq`, `.pqt`.
- The system SHALL NOT support Parquet Modular Encryption, Bloom Filters, separated metadata/column data across multiple files, or the deprecated `INT96` data type.

### Requirement: Parquet Schema Management
- The system SHALL allow adding schemas via Worker Groups > Processing > Knowledge > Parquet Schemas.
- The system SHALL support cloning existing schemas for modification.
- The system SHALL allow a single schema to be referenced across multiple destinations.
- The system SHALL NOT automatically update clones when the source schema is modified; users must re-select modified schemas in destination configurations.

---

## Parser Libraries

### Requirement: Parsers Library
- The system SHALL provide a searchable Parsers Library accessible via Processing > Knowledge > Parsers.
- The system SHALL support tagging parsers for organization.

### Requirement: Supported Parser Types
- The system SHALL support eight parser formats: CSV, Extended Log File Format (W3C), Common Log Format, Key=Value Pairs, JSON Object, Delimited Values, Regular Expression, and Grok.

### Requirement: Parser Creation
- The system SHALL require an ID (unique identifier), Type (one of eight supported formats), and Field List (expected extraction fields in order) when creating a parser.
- The system SHALL support optional Description and Tags.
- The system SHALL provide a "Maximize" feature for testing parsers against sample data during development.

### Requirement: Parser Function
- The system SHALL provide a Parser Function with three operation modes: Extract (create new fields from parsed data), Reserialize (extract, filter fields, and rewrite events in original format), and Serialize (convert extracted fields into a new format).
- The system SHALL preserve original event formats during reserialization (e.g., comma-delimited fields maintain positions as nulls rather than being removed).
- The system SHALL NOT allow the Parser Function to remove fields it did not create.

### Requirement: Parser Function Configuration
- The system SHALL support configuration of: Filter (JavaScript expression, defaults to `true`), Operation Mode, Type, Source Field, Destination Field, List of Fields, Fields to Keep (whitelist with wildcard support), Fields to Remove (blacklist with wildcard support), and Fields Filter Expression.
- The system SHALL evaluate field filters in the order: Fields to Keep > Fields to Remove > Fields Filter Expression.
- The system SHALL give Fields to Keep precedence over Fields to Remove when a field appears in both lists.
- The system SHALL support negated terms for order-sensitive logic (e.g., `!foobar, foo*` excludes foobar from foo* matches).
- The system SHALL support nested addressing with wildcards (e.g., `_raw*` references parent and children).

### Requirement: Parser Special Character Handling
- The system SHALL require Key=Value field values containing `=` to be surrounded by quotes.
- The system SHALL require CSV values with quotes or commas to be escaped using doubled quotes.
- The system SHALL support a "Clean Fields" option that replaces non-alphanumeric characters with underscores in K=V parsing.

---

## Grok Patterns

### Requirement: Grok Patterns Library
- The system SHALL provide a Grok Patterns Library accessible via Processing > Knowledge > Grok Patterns.
- The system SHALL ship with pre-built common Grok pattern files for basic scenarios.
- The system SHALL store pattern files at `$CRIBL_HOME/(default|local)/cribl/grok-patterns/`.

### Requirement: Grok Pattern Management
- The system SHALL support creating new pattern files via Add Grok Pattern File with a unique filename and pattern content.
- The system SHALL support editing existing pattern files via the Actions column Edit button.
- The system SHALL allow patterns from any configured file to be used in the Grok Function.

### Requirement: Grok Function Configuration
- The system SHALL support the pattern syntax `%{PATTERN_NAME:FIELD_NAME}` for extracting structured fields from unstructured log data.
- The system SHALL support chaining multiple Grok patterns together.
- The system SHALL support configuration of: Filter (JavaScript expression, defaults to `true`), Pattern(s), Source field (defaults to `_raw`), Description (optional), and Final toggle.
- The system SHALL require patterns to be manually typed or pasted into the Pattern field(s) in the Grok Function (not automatically applied from library).

---

## Sample Data and Data Preview

### Requirement: Sample Data Management
- The system SHALL store sample file metadata in `samples.yml` with fields: `id` (required, unique), `sampleName` (required, display name), `packId`, `lib`, `tags`, `created`, `modified`, `ttl` (time-to-live; empty = never expire), `size`, `numEvents`, `description`, `isTemplate`, and `isPackOnly`.
- The system SHALL physically store sample files in `$CRIBL_HOME/data/samples`.
- The system SHALL silently remove sample files that reach their TTL expiration without being used; each use SHALL reset the TTL.
- The system SHALL enforce a default sample size limit of 256 KB on distributed Worker Groups, adjustable up to a maximum of 3 MB (configurable at Group Settings > General Settings > Limits > Storage > Sample size limit).

### Requirement: Data Preview Tool
- The system SHALL provide a Data Preview tool that processes sample events through a Pipeline and displays inbound (IN tab) and outbound (OUT tab) results.
- The system SHALL update preview output instantly when Functions are modified, added, or removed.
- The system SHALL cap Simple Preview at 10 MB to prevent system instability, with automatic truncation for larger datasets.

### Requirement: Data Preview Display Modes
- The system SHALL support Event View (JSON format for field-level inspection), Table View (tabular format for scanning/comparison), and Metrics View (automatically activates for metric-heavy datasets with cardinality analysis and time-series visualization).

### Requirement: Data Preview Depth
- The system SHALL support Simple Preview (IN/OUT for a single pipeline) and Full Preview (exit-point selection enabling visibility into processing or post-processing pipelines separately).

### Requirement: Pipeline Diagnostics
- The system SHALL provide a Status Tab (graphs events in/out/dropped with throughput statistics), Statistics Tab (pipeline impact on field lengths and event counts), Pipeline Profile Tab (individual function contributions to processing time and data volume), and Advanced CPU Profile (function-level stack analysis).

### Requirement: Data Preview Advanced Settings
- The system SHALL support toggles for: dropped event visibility, internal field display, diff highlighting (amber=modified, green=added, red=deleted), whitespace rendering, metric expression evaluation, processing timeout adjustment, and sample data export (JSON/NDJSON formats).

### Requirement: Sample Data Acquisition
- The system SHALL support Import Data options (content broken into events using Event Breakers) and Capture Data options (working with events directly).
- The system SHALL support downloading captured data as JSON or NDJSON.

---

## Event Breakers

### Requirement: Event Breaker Rules
- The system SHALL provide Event Breaker rule management via Processing > Knowledge > Event Breaker Rules.
- The system SHALL organize Event Breakers as ordered rulesets (collections of rules) associated with Sources; rules within a ruleset SHALL be evaluated top-down.
- The system SHALL apply the first matching rule for a given Source stream.

### Requirement: Event Breaker Types
- The system SHALL support five Event Breaker types: CSV (for CSV-standard data), File Header (for logs with standard file header structure like Bro, IIS, Apache), JSON Array (for large JSON objects containing nested arrays of records), Regex (for any log data not fitting structured formats, including multi-line logs), and Timestamp (for logs with non-standard or varied timestamp formats).

### Requirement: Event Breaker Function
- The system SHALL provide an Event Breaker Function for splitting large data blobs into discrete events within pipelines.
- The system SHALL operate only on data in `_raw`.
- The system SHALL enforce a maximum of approximately 128 MB per event; oversized events SHALL be split but remain unbroken with `__isBroken: false`.
- The system SHALL support adding a `cribl_breaker` metadata field; when a source-level Event Breaker is also present, the field SHALL convert to an array.

---

## Database Connections

### Requirement: Database Connection Support
- The system SHALL support reusable Database Connection objects for MySQL, Oracle, Postgres, and SQL Server.
- The system SHALL allow multiple Database Collectors to reference the same connection.
- The system SHALL provide a Test Connection feature (validated per node; Leader Node testing does not confirm Worker Node connectivity).

### Requirement: Database Connection Configuration
- The system SHALL require: ID (unique identifier), Database type, and Authentication method (Connection String, Connection String Secret, Config for SQL Server, or Stored Credentials for Oracle).
- The system SHALL support configurable Connection timeout (default 10,000ms for MySQL, 15,000ms for SQL Server; range 1,000-60,000ms) and Request timeout (SQL Server only, default 15,000ms, minimum 1,000ms).
- The system SHALL require URL encoding for special characters in connection strings (`@`, `:`, `/`, `?`, `#`, `%`).

---

## HMAC Functions

### Requirement: HMAC Function Support
- The system SHALL provide HMAC Functions for generating hash-based signatures for REST Collector request authentication, accessible via Processing > Knowledge > HMAC Functions.
- The system SHALL support signature string variables: `method` (HTTP verb in uppercase), `urlObj` (JavaScript URL object), `headers` (alphabetically ordered request headers), and `body` (HTTP request body).
- The system SHALL ignore expressions that return undefined or null (not adding them to the final signature string).
- The system SHALL support a configurable Signature String Delimiter (JavaScript expression; blank for direct concatenation).
- The system SHALL support Authorization Header configuration with a Header Name (defaults to `signature`) and Header Expression using `C.Crypto.createHmac()` with SHA256 algorithm and hexadecimal encoding.

---

Sources:
- [Packs](https://docs.cribl.io/stream/packs/)
- [Share Packs](https://docs.cribl.io/stream/packs-share-config/)
- [Pack-Based Configuration Management](https://docs.cribl.io/stream/pack-config-management-intro/)
- [Packs Publication Standards](https://docs.cribl.io/stream/packs-standards/)
- [Knowledge Libraries](https://docs.cribl.io/stream/knowledge-library/)
- [About Lookups](https://docs.cribl.io/stream/lookups-about/)
- [Lookup Function](https://docs.cribl.io/stream/lookup-function/)
- [Configure Lookups](https://docs.cribl.io/stream/lookups-configure/)
- [C.Lookup Expression](https://docs.cribl.io/stream/expressions-lookup/)
- [Lookups and Regex](https://docs.cribl.io/stream/usecase-lookups-regex/)
- [Regexes Library](https://docs.cribl.io/stream/regex-library/)
- [Global Variables Library](https://docs.cribl.io/stream/global-variables-library/)
- [JSON Schemas](https://docs.cribl.io/stream/schema-library/)
- [Parquet Schemas](https://docs.cribl.io/stream/parquet-schemas/)
- [Parsers Library](https://docs.cribl.io/stream/4.9/parsers-library/)
- [Parser Function](https://docs.cribl.io/stream/parser-function/)
- [Grok Function](https://docs.cribl.io/stream/grok-function/)
- [Grok Patterns Library](https://docs.cribl.io/stream/4.1/grok-patterns-library/)
- [Data Preview](https://docs.cribl.io/stream/data-preview/)
- [samples.yml](https://docs.cribl.io/stream/samplesyml/)
- [Database Connections](https://docs.cribl.io/stream/database-connections/)
- [HMAC Functions](https://docs.cribl.io/stream/hmac-functions/)
- [Event Breaker Function](https://docs.cribl.io/stream/event-breaker-function/)
