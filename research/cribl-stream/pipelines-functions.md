## Pipelines Overview

### General Architecture
- Data flows through a 13-stage linear sequence: Source -> Custom Command -> Event Breakers -> Time Filters -> Fields/Metadata -> Source-side PQ -> Internal Field Assignment -> Pre-processing Pipeline -> Routes -> Processing Pipeline -> Post-processing Pipeline -> Destination-side PQ -> Destination.
- A Pipeline contains an ordered sequence of Functions. Functions execute top-down in the order they appear.
- Requirements:
  - The system SHALL execute functions in a pipeline sequentially, top to bottom.
  - The system SHALL support three pipeline attachment points: pre-processing (on Sources), processing (on Routes), and post-processing (on Destinations).
  - The system SHALL allow pipelines to be chained together via the Chain function.
  - The system SHALL prevent circular pipeline references (detected at configuration time in v4.3+).

### Pipeline Configuration Options
- **Async function timeout (ms)**: Prevents functions from causing delays.
- **Tags**: For filtering and grouping pipelines.
- **Advanced/JSON mode**: Direct JSON editor for importing/exporting pipeline definitions.
- Requirements:
  - The system SHALL provide a configurable async function timeout per pipeline.
  - The system SHALL support JSON import/export of pipeline configurations.

### Function-Level Controls (Common to All Functions)
- **Filter**: A JavaScript expression determining which events the function processes. Defaults to `true` (all events). Uses ECMAScript 2015 syntax.
- **Description**: Optional documentation text.
- **Final**: Toggle. When ON, the function consumes results and prevents downstream functions from receiving data.
- Requirements:
  - The system SHALL support a JavaScript filter expression on every function, defaulting to `true`.
  - The system SHALL support a Final toggle on every function that, when enabled, stops event flow to downstream functions.

### Routes (Conditional Pipeline Selection)
- Routes evaluate filter expressions on incoming events to direct them to the appropriate Pipeline+Destination pair.
- Routes are evaluated in display order (top to bottom). A default catch-all route at the bottom handles unmatched events.
- Each route associates with exactly one Pipeline or Pack.
- The **Final** flag on routes (default: ON) controls whether matched events stop evaluation or continue to subsequent routes.
- When Final is OFF, matched events are cloned to the route's pipeline while originals continue evaluating remaining routes.
- Routes support destination expressions using JavaScript template literals for dynamic destination selection.
- Route Groups allow organizing consecutive routes for collective movement (UI organizational tool).
- Requirements:
  - The system SHALL evaluate routes in sequential display order.
  - The system SHALL support a Final flag per route controlling whether matched events stop or continue evaluation.
  - The system SHALL clone events when a route's Final flag is disabled, sending clones to the pipeline while originals continue.
  - The system SHALL support JavaScript filter expressions on routes.
  - The system SHALL support dynamic destination expressions using JavaScript.
  - The system SHALL warn about unreachable routes (orange triangle indicator).
  - The system SHALL provide a default route as catch-all.

### Pre-processing Pipelines
- Attached to Sources, normalize events before routing.
- Fields extracted here become available to Routes.
- Apply operations to all events from that source.
- Requirements:
  - The system SHALL support attaching a pre-processing pipeline to any Source.
  - The system SHALL make fields extracted in pre-processing available to Route filter expressions.

### Post-processing Pipelines
- Attached to Destinations, normalize events before delivery.
- Apply functions across all events exiting to that destination.
- Can add system fields like `cribl_input`.
- Requirements:
  - The system SHALL support attaching a post-processing pipeline to any Destination.
  - The system SHALL add system fields (cribl_*) during post-processing.

---

## Event Model

### Core Event Structure
Events are collections of key-value pairs. Internal representation:
```
{
  "_raw": "body of non-JSON-parseable events",
  "_time": "Unix epoch timestamp",
  "__inputId": "source identifier",
  // additional fields
}
```

### Standard Fields
- **`_raw`**: Contains the complete body of events that cannot be JSON-parsed. Assigned automatically on arrival.
- **`_time`**: Unix epoch timestamp. Assigned current processing time if no timestamp extraction is configured.
- Requirements:
  - The system SHALL assign all non-JSON-parseable content to `_raw`.
  - The system SHALL assign current time to `_time` when no timestamp extraction is configured.

### Internal Fields (Double-Underscore Prefix `__`)
- Added before Pipeline processing.
- Serialize only to Cribl internal destinations.
- Read-only; modification risks unintended consequences.
- Examples: `__inputId` (source ID), `__srcIpPort` (syslog source IP:port), `__isBroken`, `__timestampExtracted`, `__criblMetrics`, `__json`.
- Requirements:
  - The system SHALL prefix internal fields with `__`.
  - The system SHALL serialize internal fields only to Cribl internal destinations.
  - The system SHALL treat internal fields as read-only.

### System Fields (Cribl_ Prefix)
- Added automatically during post-processing. Read-only.
- `cribl_pipe`: Pipeline that processed the event (added by default).
- `cribl_host`: Processing Node.
- `cribl_input`: Source identifier.
- `cribl_output`: Destination identifier.
- `cribl_route`: Route/QuickConnect identifier.
- `cribl_wp`: Worker Process identifier.
- `cribl_breaker`: Event breaker ruleset name.
- Requirements:
  - The system SHALL automatically add `cribl_pipe` to all processed events.
  - The system SHALL treat all `cribl_*` fields as read-only.
  - The system SHALL add system fields after pipeline execution (removing them in pipelines is ineffective).

---

## Expression Language / Eval Syntax

### JavaScript Foundation
- Expressions use ECMAScript 2015 (ES6) syntax.
- Every expression resolves to a value.
- The special variable `__e` represents the current event object.
- Field access: `fieldName` for simple names, `__e['field-name']` for fields with special characters.
- Ternary operator supported: `(condition) ? valueIfTrue : valueIfFalse`.
- `==` for equality, `===` for strict equality (value and type).
- Requirements:
  - The system SHALL support ECMAScript 2015 expressions in all filter and value fields.
  - The system SHALL provide `__e` as the event context variable.
  - The system SHALL support bracket notation for fields with special characters.

### C.* Native Methods

#### C.Crypto
- `C.Crypto.encrypt(value, keyclass, keyId?, defaultVal?)` - Encrypt a value.
- `C.Crypto.decrypt(value, escape?, escapeSeq?)` - Decrypt cipher instances.
- `C.Crypto.createHmac(value, secret, algorithm?, outputFormat?)` - Generate HMAC.

#### C.Encode
- `C.Encode.base64(val, trimTrailEq?, encoding?)` - Base64 encode.
- `C.Encode.deflate(value, encoding?, toRaw?)` - Deflate compress.
- `C.Encode.gzip(value, encoding?)` - Gzip compress.
- `C.Encode.hex(val)` - Convert to hex.
- `C.Encode.mime(val, encoding?, maxLineLength?, charset?)` - MIME encode.
- `C.Encode.uri(val)` - URI encode.

#### C.Decode
- `C.Decode.base64(val, resultEnc?)` - Base64 decode.
- `C.Decode.gzip(value, encoding?)` - Gunzip.
- `C.Decode.hex(val)` - Hex to number.
- `C.Decode.inflate(value, encoding?, isRaw?)` - Inflate decompress.
- `C.Decode.mime(val)` - MIME decode.
- `C.Decode.uri(val)` - URI decode.

#### C.Mask
- `C.Mask.md5(value, len?, encoding?)` - MD5 hash. Max output: 32 chars. Unavailable in FIPS mode.
- `C.Mask.sha1(value, len?, encoding?)` - SHA1 hash. Max: 40 chars.
- `C.Mask.sha256(value, len?, encoding?)` - SHA256 hash. Max: 64 chars.
- `C.Mask.sha512(value, len?, encoding?)` - SHA512 hash.
- `C.Mask.sha3_256(value, len?, encoding?)` - SHA3-256 hash.
- `C.Mask.sha3_512(value, len?, encoding?)` - SHA3-512 hash.
- `C.Mask.crc32(value)` - CRC32 hash.
- `C.Mask.random(len?)` - Random alphanumeric string.
- `C.Mask.repeat(len?, char?)` - Repeating character pattern. Default char: 'X'.
- `C.Mask.CC(value, unmasked?, maskChar?)` - Validate and mask credit card numbers.
- `C.Mask.IMEI(value, unmasked?, maskChar?)` - Validate and mask IMEI numbers.
- `C.Mask.isCC(value)` - Validate credit card via Luhn.
- `C.Mask.isIMEI(value)` - Validate IMEI via Luhn.
- `C.Mask.luhn(value, unmasked?, maskChar?)` - Mask if Luhn checksum passes.
- `C.Mask.luhnChecksum(value, mod?)` - Generate Luhn checksum.
- `C.Mask.REDACTED` - String literal "REDACTED".

#### C.Net
- `C.Net.cidrMatch(cidrIpRange, ipAddress)` - Check IP in CIDR range.
- `C.Net.communityIDv1(srcIP, destIP, srcPort, destPort, proto, seed?)` - Generate Community ID flow identifier.
- `C.Net.isIp(value)` - Validate IPv4 or IPv6.
- `C.Net.isIpV4(value)` - Validate IPv4.
- `C.Net.isIpV6(value)` - Validate IPv6.
- `C.Net.isIPV4Cidr(value)` - Validate IPv4 CIDR.
- `C.Net.isIPV6Cidr(value)` - Validate IPv6 CIDR.
- `C.Net.isIpV4AllInterfaces(value)` - Check if 0.0.0.0.
- `C.Net.isIpV6AllInterfaces(value)` - Check if :: equivalent.
- `C.Net.ipv6Normalize(address)` - Normalize IPv6 per RFC.
- `C.Net.isPrivate(address)` - Check RFC1918 private address.
- `C.Net.parseAddressOrRangeString(source, mask?)` - Parse IP or range.
- `C.Net.IPv4_CIDR_REGEX` - RegExp for matching IPv4 CIDR.

#### C.Text
- `C.Text.entropy(bytes)` - Shannon entropy calculation.
- `C.Text.hashCode(val)` - djb2 hash code.
- `C.Text.isASCII(bytes)` - Check ASCII printable range.
- `C.Text.isUTF8(bytes)` - Validate UTF-8.
- `C.Text.parseWinEvent(xml, nonValues?)` - Windows event XML to JSON.
- `C.Text.parseXml(xml, keepAttr?, keepMetadata?, nonValues?)` - XML to JSON.
- `C.Text.relativeEntropy(bytes, modelName?)` - Relative entropy against statistical model.

#### C.Time
- `C.Time.adjustTZ(epochTime, tzTo, tzFrom?)` - Convert between timezones.
- `C.Time.clamp(date, earliest, latest, defaultDate?)` - Constrain timestamp within bounds.
- `C.Time.strftime(date, format, utc?)` - Format date to string.
- `C.Time.strptime(str, format, utc?, strict?)` - Parse string to Date.
- `C.Time.timestampFinder(utc?).find(str)` - Auto-extract timestamp from text.
- `C.Time.timePartition(date, level)` - Generate date path prefix (YYYY/MM/DD or YYYY/MM/DD/HH).
- `C.Time.s3TimePartition(date, level)` - S3-compatible date path prefix.

#### C.Lookup
- `C.Lookup(file, primaryKey?, otherFields?, ignoreCase?)` - Exact match lookup.
- `C.LookupCIDR(file, primaryKey?, otherFields?)` - CIDR range lookup.
- `C.LookupIgnoreCase(file, primaryKey?, otherFields?)` - Case-insensitive lookup.
- `C.LookupRegex(file, primaryKey?, otherFields?)` - Regex-based lookup.
- `InlineLookup.match(value, fieldToReturn?)` - Execute lookup match.

#### C.Schema
- `C.Schema(id).validate(object)` - Validate object against named schema.

#### C.Secret
- `C.Secret(id, type?)` - Retrieve secret by ID. Types: 'text', 'keypair', 'credentials'.

#### C.Misc
- `C.Misc.zip(keys[], values[], dest?)` - Combine arrays into object.
- `C.Misc.uuidv4()` - Generate random UUID.
- `C.Misc.uuidv5(name, namespace)` - Generate namespaced UUID.
- `C.Misc.validateUUID(string)` - Validate UUID format.
- `C.Misc.getUUIDVersion(uuid)` - Return UUID version.

#### Other
- `C.env` - Object containing environment variables.
- `C.os.hostname()` - System hostname.
- `C.vars` - Global variables library.
- `C.version` - Current Cribl Stream version.
- `C.confVersion` - Current config commit hash.
- `C.WorkerGroupId` - Current Worker Group name.

- Requirements:
  - The system SHALL provide all C.* methods for use in any expression-enabled field.
  - The system SHALL support C.Crypto for encryption/decryption within expressions.
  - The system SHALL support C.Mask for hashing, masking, and validation within expressions.
  - The system SHALL support C.Net for IP validation and CIDR matching within expressions.
  - The system SHALL support C.Lookup for inline lookups within expressions.
  - The system SHALL support C.Secret for accessing stored secrets within expressions.

---

## Functions

### Function: Eval
- Description: Adds, modifies, or removes event fields through JavaScript expressions. The most fundamental transformation function.
- Requirements:
  - The system SHALL support adding fields via name/value expression pairs where the value is a JavaScript expression.
  - The system SHALL support removing fields via a Remove Fields list with wildcard support.
  - The system SHALL support retaining only specified fields via a Keep Fields list with wildcard support.
  - The system SHALL give Keep Fields precedence over Remove Fields when both are specified.
  - The system SHALL support negated terms in Keep/Remove lists (e.g., `!foobar, foo*`).
  - The system SHALL support enabling/disabling individual field expressions without deleting them.
  - The system SHALL prohibit reserved words (`constructor`, `prototype`, `__proto__`), JavaScript setters, nested scopes (loops, conditionals, array methods), and variable/function declarations in value expressions.

### Function: Regex Extract
- Description: Extracts fields from event data using regex named capture groups.
- Requirements:
  - The system SHALL support named capture groups syntax `(?<fieldname>pattern)`.
  - The system SHALL support dual extraction groups `(?<_NAME_N>...)=(?<_VALUE_N>...)` for extracting both field names and values.
  - The system SHALL support configurable source field (default: `_raw`).
  - The system SHALL support an overwrite toggle controlling whether extracted values replace or array-combine with existing fields.
  - The system SHALL support a max exec limit for global flag or dual-extraction patterns (default: 100).
  - The system SHALL support a field name format expression for customizing extracted field names.

### Function: Parser
- Description: Extracts fields from events or reserializes them with a subset of fields while preserving original format.
- Requirements:
  - The system SHALL support two operation modes: Extract and Reserialize.
  - The system SHALL support parser types: CSV, Extended Log File Format, Common Log Format, Key=Value Pairs, JSON Object, Delimited Values, Regular Expression, and Grok.
  - The system SHALL support field lists (order-dependent for positional formats).
  - The system SHALL support Fields to Keep, Fields to Remove, and Fields Filter Expression with precedence: Keep -> Remove -> Filter.
  - The system SHALL support configurable delimiters, quote characters, escape characters, and null value representations for delimited formats.
  - The system SHALL support a "clean fields" option for K=V that replaces non-alphanumeric characters with underscores.

### Function: Rename
- Description: Modifies field names or reformats them (e.g., to camelCase).
- Requirements:
  - The system SHALL support explicit rename via key-value pairs (old name -> new name).
  - The system SHALL support dynamic rename via JavaScript expression using `name` and `value` global variables.
  - The system SHALL execute Rename Fields before Rename Expression when both are specified.
  - The system SHALL support parent fields with wildcards to scope rename operations to nested children.
  - The system SHALL support configurable parent field wildcard depth (default: 5).
  - The system SHALL NOT operate on internal fields starting with `__`.

### Function: Lookup
- Description: Enriches events by matching against external lookup table files and appending corresponding values.
- Requirements:
  - The system SHALL support CSV, CSV.gz, and MMDB lookup file formats.
  - The system SHALL support match modes: Exact, Regex, CIDR.
  - The system SHALL support match types: First match, Most specific, All.
  - The system SHALL support case-insensitive matching for Exact mode.
  - The system SHALL support disk-based lookups for large files.
  - The system SHALL support configurable reload periods for lookup files (-1 to disable).
  - The system SHALL support default values when matches fail.
  - The system SHALL support an "Add to raw event" option that appends matched values to `_raw`.
  - The system SHALL support output field mapping from lookup table columns to event fields.

### Function: GeoIP
- Description: Enriches events with geographic data based on IP addresses using MaxMind/IPinfo MMDB databases.
- Requirements:
  - The system SHALL accept `.mmdb` binary database files.
  - The system SHALL support configurable IP field (default: `ip`) and result field (default: `geoip`).
  - The system SHALL return geographic data including city, country, postal code, latitude, and longitude.

### Function: Mask
- Description: Replaces patterns in events for redacting PII and sensitive data.
- Requirements:
  - The system SHALL support masking rules with Match Regex and Replace Expression pairs.
  - The system SHALL support the `/g` flag for global matching.
  - The system SHALL support capture group references (g1, g2, etc.) in replace expressions.
  - The system SHALL support multiple masking rules per function instance, each individually toggleable.
  - The system SHALL support configurable "Apply to" fields with wildcards and negation.
  - The system SHALL support hash-based masking via `C.Mask.*` methods in replace expressions.
  - The system SHALL support configurable traversal depth into nested properties (default: 5).
  - The system SHALL support optional evaluate fields that add metadata when rules match.

### Function: Numerify
- Description: Converts event fields containing numeric data to the `number` data type.
- Requirements:
  - The system SHALL support configurable search depth into nested events (default: 5, max: 10).
  - The system SHALL support ignore fields list with wildcards (takes precedence over inclusion).
  - The system SHALL support an include expression using `name` and `value` variables.
  - The system SHALL support format options: None, Floor, Ceil, Round (0-20 decimal places).

### Function: Flatten
- Description: Promotes nested key-value pairs to a higher level in the object hierarchy.
- Requirements:
  - The system SHALL support configurable fields to flatten (default: all).
  - The system SHALL support configurable prefix for promoted field names.
  - The system SHALL support configurable depth (default: 5).
  - The system SHALL support configurable delimiter for concatenated keys (default: underscore).
  - The system SHALL create fully qualified names for promoted fields.

### Function: Fold Keys
- Description: Transforms flat field names with common separators into nested hierarchical structures.
- Requirements:
  - The system SHALL support configurable separator string (default: `.`).
  - The system SHALL support an optional selection regex to process only matching field names.
  - The system SHALL support a "delete original" toggle (default: ON) to remove flat fields after nesting.
  - The system SHALL create nested objects from separator-delimited field names.

### Function: Drop
- Description: Removes events matching specified criteria, preventing them from reaching downstream functions.
- Requirements:
  - The system SHALL drop events matching the filter expression.
  - The system SHALL support JavaScript filter expressions for drop conditions.

### Function: Regex Filter
- Description: Filters events based on regex pattern matches.
- Requirements:
  - The system SHALL support one or more regex patterns for filtering.
  - The system SHALL support configurable target field (default: `_raw`).
  - The system SHALL support predefined regex patterns from the regex library.
  - The system SHALL support chaining multiple regex conditions.

### Function: Sampling
- Description: Reduces event volume by keeping 1 out of every N events based on matching criteria.
- Requirements:
  - The system SHALL support multiple sampling rules, each with a filter expression and sampling rate.
  - The system SHALL keep 1 out of every N events where N is the sampling rate.
  - The system SHALL execute independently on each Worker Process.

### Function: Dynamic Sampling
- Description: Automatically adjusts sampling rates based on event volume, using mathematical formulas.
- Requirements:
  - The system SHALL support two sampling modes: Logarithmic (`Math.ceil(Math.log(volume))`) and Square Root (`Math.ceil(Math.sqrt(volume))`).
  - The system SHALL support a sample group key expression for grouping events (default: `` `${host}` ``).
  - The system SHALL support configurable sample period (default: 30s).
  - The system SHALL support minimum events threshold before sampling activates (default: 30).
  - The system SHALL support a sampling rate limit cap.
  - The system SHALL initially pass all events (1:1) for new groups during the first sample period.
  - The system SHALL execute independently on each Worker Process.

### Function: Suppress
- Description: Drops or tags duplicate/repeated events over a specified time period based on a key expression.
- Requirements:
  - The system SHALL support a key expression for identifying events to suppress.
  - The system SHALL support configurable "number to allow" per time period (default: 1).
  - The system SHALL support configurable suppression period in seconds (default: 30).
  - The system SHALL support a toggle to either drop or tag suppressed events (default: drop).
  - The system SHALL add `suppressCount: N` to the next allowed event when dropping is enabled.
  - The system SHALL add `suppress=1` tag when dropping is disabled.
  - The system SHALL support configurable cache size limit (default: 50,000).
  - The system SHALL execute independently on each Worker Process.

### Function: Event Breaker
- Description: Divides large data blobs or event streams into separate events within a Pipeline.
- Requirements:
  - The system SHALL operate only on data in `_raw`.
  - The system SHALL support a maximum breakable event size of approximately 128 MB.
  - The system SHALL support using existing rulesets or creating new ones.
  - The system SHALL support an "Add to cribl_breaker" toggle for tracking breaker identity.
  - The system SHALL truncate timestamps to millisecond precision.

### Function: JSON Unroll
- Description: Expands JSON arrays within `_raw` into individual events, preserving top-level fields.
- Requirements:
  - The system SHALL parse JSON into an internal `__json` field.
  - The system SHALL create separate events for each array element at the specified path.
  - The system SHALL preserve parent-level fields across all generated events.
  - The system SHALL support configurable array path (e.g., `allCars`, `foo.0.bar`).
  - The system SHALL support an optional new name for exploded elements.

### Function: XML Unroll
- Description: Transforms a single XML event containing multiple elements into separate individual events.
- Requirements:
  - The system SHALL support an "unroll elements regex" to identify elements to separate.
  - The system SHALL support a "copy elements regex" to duplicate specified elements across all generated events.
  - The system SHALL support an unroll index field (default: `unroll_idx`, 0-based).
  - The system SHALL support a pretty print toggle for formatted output.

### Function: Auto Timestamp
- Description: Extracts timestamps from event fields and populates a destination field.
- Requirements:
  - The system SHALL support configurable source field (default: `_raw`) and destination field (default: `_time`).
  - The system SHALL support default timezone assignment for timestamps lacking timezone info.
  - The system SHALL support additional custom timestamps via regex + strptime format pairs.
  - The system SHALL support configurable earliest/latest timestamp bounds (defaults: `-420weeks` / `+1week`).
  - The system SHALL support configurable scan offset and max scan depth (default: 150 chars).
  - The system SHALL support a time expression for custom formatting.
  - The system SHALL support a default time when no timestamp is found (default: current time).

### Function: Grok
- Description: Extracts structured fields from unstructured log data using modular regex patterns.
- Requirements:
  - The system SHALL support Grok pattern syntax `%{PATTERN_NAME:FIELD_NAME}`.
  - The system SHALL support chaining multiple patterns.
  - The system SHALL support configurable source field (default: `_raw`).
  - The system SHALL support pattern files stored in `$CRIBL_HOME/(default|local)/cribl/grok-patterns/`.
  - The system SHALL provide pre-built patterns for common logging scenarios.

### Function: Code
- Description: Executes custom JavaScript logic for transformations that built-in functions cannot accomplish.
- Requirements:
  - The system SHALL support ECMAScript 2015 (ES6) JavaScript.
  - The system SHALL provide event access via `__e` variable.
  - The system SHALL support loops, array methods, standard operators, control flow, error handling, functions, closures, regex, Date/number operations, and object manipulation.
  - The system SHALL prohibit features forbidden in JavaScript strict mode: console, eval, Function constructor, Promises, timers, global objects.
  - The system SHALL support configurable iteration limit (default: 5000, max: 10000).
  - The system SHALL support configurable error log sample rate (default: 1).
  - The system SHALL support optional unique log channel routing.

### Function: Serialize
- Description: Transforms event content into predefined output formats.
- Requirements:
  - The system SHALL support output formats: CSV, Extended Log File Format, Common Log Format, Key=Value Pairs, JSON Object, Delimited Values.
  - The system SHALL support configurable fields to serialize (explicit list; JSON and K=V support wildcards).
  - The system SHALL support configurable source field and destination field (default: `_raw`).
  - The system SHALL support format-specific settings: K=V (clean fields, pair delimiter), Delimited (delimiter, quote char, escape char, null value).

### Function: CEF Serializer
- Description: Transforms events into Common Event Format (CEF) standard with header and extension fields.
- Requirements:
  - The system SHALL produce output in format: `CEF:Version|Vendor|Product|Version|EventClassID|Name|Severity|[Extension]`.
  - The system SHALL support 7 configurable header fields with JavaScript expressions or constants.
  - The system SHALL support variable key-value extension fields.
  - The system SHALL support configurable output field (default: `_raw`).

### Function: SNMP Trap Serialize
- Description: Converts compliant events into SNMP traps for forwarding to SNMP Trap Destinations.
- Requirements:
  - The system SHALL require the source SNMP Trap to have "Include varbind types" enabled.
  - The system SHALL support "Enforce required fields" toggle for v2c/v3 trap compliance.
  - The system SHALL support "Drop failed events" toggle with `snmpSerializeErrors` field for debugging.
  - The system SHALL support SNMPv3 security settings: username, auth protocol (None/MD5/SHA1/SHA224/SHA256/SHA384/SHA512), auth key, privacy protocol (None/AES128/AES256b/AES256r), privacy key.
  - The system SHALL use varbind values over top-level values for v2c sysUpTime and snmpTrapOID.

### Function: Aggregations
- Description: Calculates summary statistics from event data using tumbling time windows.
- Requirements:
  - The system SHALL support 28+ aggregation functions: count(), dc(), distinct_count(), avg(), median(), stdev(), variance(), mode(), min(), max(), perc(), sum(), sumsq(), rate(), per_second(), first(), last(), earliest(), latest(), list(), values(), top(), histogram(), summary().
  - The system SHALL support configurable time window (e.g., `10s`, `5m`).
  - The system SHALL support Group By fields with wildcard support.
  - The system SHALL support lag tolerance for late events.
  - The system SHALL support idle bucket time limit for flushing inactive buckets.
  - The system SHALL support cumulative aggregations toggle (retain values across flushes vs. reset).
  - The system SHALL support passthrough mode (include originals alongside aggregations).
  - The system SHALL support metrics mode output.
  - The system SHALL support sufficient stats mode.
  - The system SHALL support configurable aggregation event limit and memory limit.
  - The system SHALL execute independently on each Worker Process.

### Function: Aggregate Metrics
- Description: Computes statistics specifically for metric events (events with `__criblMetrics` field).
- Requirements:
  - The system SHALL process only events containing the `__criblMetrics` internal field.
  - The system SHALL pass non-metric data through unchanged.
  - The system SHALL support metric types: Automatic, Counter, Distribution, Gauge, Histogram, Summary, Timer.
  - The system SHALL support configurable time window, group-by dimensions, and aggregation functions.
  - The system SHALL support passthrough mode, sufficient stats mode, cumulative aggregations.
  - The system SHALL support configurable memory and event limits.
  - The system SHALL support "Treat dots as literals" for StatsD/OpenTelemetry metric names.
  - The system SHALL support flush on stream close toggle.

### Function: Publish Metrics
- Description: Extracts, formats, and outputs metrics from events for metrics aggregation platforms.
- Requirements:
  - The system SHALL support metric types: Gauge, Counter, Timer, Distribution, Summary, Histogram.
  - The system SHALL support metric name expressions (JavaScript).
  - The system SHALL support adding/removing dimensions with wildcards and negation.
  - The system SHALL support overwrite or append to existing metric specifications.
  - The system SHALL output in format: `metric_name:value|type#dimension_key:value`.

### Function: Rollup Metrics
- Description: Aggregates frequently-generated incoming metrics into larger time windows.
- Requirements:
  - The system SHALL support configurable time window.
  - The system SHALL support configurable dimensions to preserve (default: `*` for all).
  - The system SHALL support gauge update modes: Last (default), Maximum, Minimum, Average.
  - The system SHALL execute independently on each Worker Process.

### Function: Drop Dimensions
- Description: Reduces unique dimension combinations in metrics data to address high cardinality.
- Requirements:
  - The system SHALL process in order: Filter -> Drop -> Aggregate -> Output.
  - The system SHALL support an aggregation time window.
  - The system SHALL support a dimensions-to-drop list using lightweight syntax with wildcards (`*`, `!*`, `'string*'`, `!dimensionName`).
  - The system SHALL support flush on stream close toggle (default: enabled).
  - The system SHALL NOT support aggregation of histogram, summary, or distribution metric types.
  - The system SHALL split mixed-metric events into single-metric events before processing.

### Function: OTLP Metrics
- Description: Converts dimensional metrics events into OpenTelemetry Protocol (OTLP) format.
- Requirements:
  - The system SHALL process events containing the `__criblMetrics` internal field.
  - The system SHALL support OTLP versions 0.10.0 (default) and 1.3.1.
  - The system SHALL support conversion from OTLP 0.10.0 to 1.3.1 (not reverse).
  - The system SHALL support configurable resource attribute prefixes.
  - The system SHALL support batching with configurable batch size, timeout, size limit, metadata keys, and cardinality limit.
  - The system SHALL support a "Drop non-metric events" toggle.
  - The system SHALL remove the `__criblMetrics` field from output.

### Function: OTLP Logs
- Description: Processes logs from OTel Source, normalizes and optionally batches them for OTel Destination.
- Requirements:
  - The system SHALL support two modes: Extract logs OFF (clean and forward) and Extract logs ON (flatten and batch).
  - The system SHALL support batching by shared resource attributes.
  - The system SHALL support configurable batch size, timeout, size limit, metadata keys, and cardinality limit.
  - The system SHALL support a "Drop non-log events" toggle.
  - The system SHALL be placed last in pipelines for best results.

### Function: OTLP Traces
- Description: Processes trace data from OTel Source, normalizes and optionally batches for downstream destinations.
- Requirements:
  - The system SHALL support OTLP versions 0.10.0 and 1.3.1.
  - The system SHALL support batching by shared resource attributes.
  - The system SHALL support configurable batch size, timeout (default: 200ms), size limit, metadata keys, and cardinality limit.
  - The system SHALL support a "Drop non-trace events" toggle.
  - The system SHALL be placed last in pipelines for best results.

### Function: DNS Lookup
- Description: Performs forward and reverse DNS lookups with configurable caching.
- Requirements:
  - The system SHALL support forward DNS lookups (domain to IP) for multiple record types.
  - The system SHALL support reverse DNS lookups (IP to hostname).
  - The system SHALL support a DNS cache with configurable TTL (default: 30 minutes) and size limit (default: 5,000, max: 100,000).
  - The system SHALL support fallback resolution via `/etc/resolv.conf`, custom fallback domains, and `DNS.lookup()`.
  - The system SHALL support custom DNS server configuration (IPv4/IPv6).
  - The system SHALL support configurable log level for failed lookups.

### Function: Redis
- Description: Interacts with Redis stores for key-value and key-hash operations, enabling large lookup tables.
- Requirements:
  - The system SHALL support deployment types: Standalone, Cluster, Sentinel.
  - The system SHALL support any Redis command from redis.io/commands.
  - The system SHALL support authentication: None, Basic, User Secret, Admin Secret.
  - The system SHALL support TLS (Redis 6+) via `rediss://` URL prefix with configurable cert validation, SNI, mutual auth, and TLS version.
  - The system SHALL support reusable connections with configurable limits per worker group.
  - The system SHALL support client-side caching with configurable TTL, max keys, and size limits.
  - The system SHALL support server-assisted caching modes: Default and Broadcast.
  - The system SHALL support configurable blocking time limit (default: 60s).

### Function: Chain
- Description: Links data processing from one Pipeline or Pack to another.
- Requirements:
  - The system SHALL return control to the parent pipeline after the chained pipeline completes.
  - The system SHALL detect circular references at configuration time and prevent saving.
  - The system SHALL support a processor dropdown for selecting the target Pipeline or Pack.
  - The system SHALL restrict Packs to chaining only within the same Pack.
  - The system SHALL acknowledge a slight performance cost versus consolidating into one pipeline.

### Function: Clone
- Description: Duplicates events within a Pipeline with optional custom fields added to copies.
- Requirements:
  - The system SHALL send cloned events to the same Destination as originals (same pipeline).
  - The system SHALL support adding custom fields (key-value pairs) to cloned events.
  - The system SHALL support multiple clone definitions per function instance.
  - The system SHALL support using clones with Output Router destinations for routing copies to different endpoints.

### Function: Tee
- Description: Directs events to an external command via stdin, formatted as JSON per line.
- Requirements:
  - The system SHALL pipe events as JSON to the specified command's stdin.
  - The system SHALL send metadata (format, conf) as the first line.
  - The system SHALL support configurable command and arguments.
  - The system SHALL support a "restart on exit" toggle (default: enabled).
  - The system SHALL support custom environment variables.
  - The system SHALL be restricted to customer-managed hybrid Worker Nodes in Cribl.Cloud.

### Function: Guard
- Description: Dynamically scans incoming data for sensitive information (PII) and obfuscates events using rulesets.
- Requirements:
  - The system SHALL process in order: Filter -> Scan -> Mitigate.
  - The system SHALL support multiple scanning rulesets per function instance.
  - The system SHALL support configurable mitigation expressions (JavaScript or literals) with capture group support.
  - The system SHALL support "Apply to fields" and "Fields to ignore" for scoping.
  - The system SHALL add `_sensitive` field to mitigated events by default.
  - The system SHALL support optional `__detected` field showing matched ruleset IDs.
  - The system SHALL support `__potential_sensitive` and `__potential_sensitive_data` fields.
  - The system SHALL be recommended for post-processing pipeline placement.

### Function: Comment
- Description: Adds a text annotation in a Pipeline. Makes no changes to event data.
- Requirements:
  - The system SHALL NOT modify event data.
  - The system SHALL display comments only in the Pipeline UI.
  - The system SHALL have a minimum non-zero processing time.

---

## Conditional Processing Summary

- **Route-level**: JavaScript filter expressions determine which pipeline processes an event. Final flag controls pass-through vs. clone behavior.
- **Function-level**: Every function has a Filter field (JavaScript expression, default `true`) that determines which events that function processes.
- **Drop function**: Explicitly removes events matching criteria.
- **Regex Filter**: Filters events based on regex pattern matches.
- **Sampling/Dynamic Sampling/Suppress**: Conditionally reduce event volume.
- **Final toggle**: On any function, stops downstream processing for matched events.
- Requirements:
  - The system SHALL support conditional processing at both route and function levels.
  - The system SHALL evaluate route filters sequentially and function filters per-event.
  - The system SHALL support the Final toggle on every function as a flow control mechanism.
