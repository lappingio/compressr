## ADDED Requirements

### Requirement: Iceberg Destination
The system SHALL provide an Apache Iceberg destination that writes events as columnar Parquet data files to S3, registered in AWS Glue Catalog as Iceberg tables. The Iceberg destination SHALL implement the `Compressr.Destination` behaviour. The Iceberg destination SHALL support configurable date-based partitioning (daily by default, hourly as an option), configurable Parquet compression (snappy by default, with zstd and gzip alternatives), configurable row group size and page size, configurable S3 storage class (Intelligent-Tiering by default, with Standard and Glacier options), and configurable S3 bucket and key prefix. The Iceberg destination SHALL enforce a minimum file size (configurable, default 50 MB) to avoid S3 small-file performance problems. The Iceberg destination SHALL close and upload files at a configurable time interval (default 5 minutes) regardless of file size.

#### Scenario: Iceberg destination writes Parquet to S3
- **WHEN** events are flushed to an Iceberg destination
- **THEN** the events SHALL be written as a Parquet data file to the configured S3 bucket and prefix
- **THEN** the Parquet file SHALL use the configured compression algorithm (snappy by default)

#### Scenario: Iceberg destination registers table in Glue Catalog
- **WHEN** an Iceberg destination is initialized
- **THEN** the destination SHALL register or verify the Iceberg table in AWS Glue Catalog under the configured database and table name
- **THEN** the table SHALL be queryable via Athena, Spark, Trino, or DuckDB using the Glue Catalog

#### Scenario: Iceberg destination partitions by date
- **WHEN** events are written to an Iceberg destination with default partition configuration
- **THEN** data files SHALL be partitioned by date using daily granularity
- **WHEN** events are written to an Iceberg destination configured with hourly partitioning
- **THEN** data files SHALL be partitioned by date using hourly granularity

#### Scenario: Iceberg destination enforces minimum file size
- **WHEN** events are buffered in an Iceberg destination and the buffer has not reached the configured minimum file size
- **THEN** the destination SHALL continue buffering events without uploading
- **WHEN** the buffer reaches or exceeds the configured minimum file size
- **THEN** the destination SHALL close the Parquet file and upload it to S3

#### Scenario: Iceberg destination time-based file close
- **WHEN** the configured flush interval elapses with buffered events that have not reached the minimum file size
- **THEN** the destination SHALL close and upload the Parquet file regardless of size
- **THEN** the Iceberg metadata SHALL be updated with the new data file

#### Scenario: Iceberg destination S3 storage class
- **WHEN** an Iceberg destination is configured with a specific S3 storage class
- **THEN** uploaded Parquet files SHALL use the configured storage class
- **WHEN** no storage class is explicitly configured
- **THEN** uploaded Parquet files SHALL use S3 Intelligent-Tiering

### Requirement: Iceberg Schema Management
The system SHALL support automatic schema detection from event fields for the Iceberg destination, inferring column types (string, integer, float, boolean, timestamp) from event data. The system SHALL also support optional explicit schema definition in the destination configuration. When events contain fields not present in the current Iceberg table schema, the system SHALL evolve the schema by adding new columns without breaking existing data. Schema changes SHALL be committed as Iceberg schema evolution operations and synchronized to AWS Glue Catalog.

#### Scenario: Schema auto-detection from events
- **WHEN** events are written to an Iceberg destination with no explicit schema defined
- **THEN** the system SHALL infer column names and types from event fields
- **THEN** the inferred schema SHALL be used for the Parquet file and Iceberg table

#### Scenario: Explicit schema definition
- **WHEN** an Iceberg destination is configured with an explicit schema definition
- **THEN** the system SHALL use the defined schema for Parquet writing
- **THEN** event fields not in the schema SHALL be dropped or stored in a catch-all JSON column (configurable)

#### Scenario: Schema evolution on new fields
- **WHEN** an event contains fields not present in the current Iceberg table schema
- **THEN** the system SHALL add the new fields as columns to the Iceberg table schema
- **THEN** the schema evolution SHALL be committed as an Iceberg schema evolution operation
- **THEN** the updated schema SHALL be synchronized to AWS Glue Catalog

### Requirement: Iceberg Metadata and Snapshot Management
The system SHALL manage Iceberg table metadata including manifests, manifest lists, and snapshots. Each flush of a Parquet data file to S3 SHALL result in a new Iceberg snapshot that atomically adds the data file to the table. The system SHALL use `ex_iceberg` (an Elixir library wrapping iceberg-rust via NIF) for all Iceberg metadata operations. Iceberg metadata files SHALL be stored in S3 alongside the data files.

#### Scenario: Snapshot creation on file upload
- **WHEN** a Parquet data file is uploaded to S3 by the Iceberg destination
- **THEN** the system SHALL create a new Iceberg snapshot that includes the uploaded data file
- **THEN** the snapshot SHALL be committed atomically so concurrent readers see a consistent view

#### Scenario: Metadata stored in S3
- **WHEN** Iceberg metadata operations are performed
- **THEN** manifest files, manifest lists, and metadata JSON files SHALL be written to S3 in the configured table location

#### Scenario: Concurrent snapshot safety
- **WHEN** multiple flush operations occur concurrently (e.g., across cluster nodes)
- **THEN** the system SHALL use Iceberg's optimistic concurrency to handle snapshot conflicts
- **THEN** conflicting commits SHALL be retried with the updated metadata

### Requirement: Parquet Writing via Rust NIF
The system SHALL use a Rust NIF (built with Rustler) wrapping the Arrow and Parquet Rust crates to write Parquet files. The NIF SHALL accept event data and schema from Elixir, write columnar Parquet data with the configured compression and layout settings, and return the resulting Parquet file bytes to Elixir for upload to S3. The NIF SHALL support configurable row group size (default 128 MB) and page size (default 1 MB).

#### Scenario: Parquet file creation via NIF
- **WHEN** the Iceberg destination flushes buffered events
- **THEN** the Rust NIF SHALL convert event data to columnar Arrow format
- **THEN** the NIF SHALL write a Parquet file with the configured compression, row group size, and page size
- **THEN** the NIF SHALL return the Parquet file bytes to the Elixir caller

#### Scenario: Parquet compression configuration
- **WHEN** the Iceberg destination is configured with snappy compression
- **THEN** the Parquet file SHALL use snappy compression
- **WHEN** the Iceberg destination is configured with zstd compression
- **THEN** the Parquet file SHALL use zstd compression
- **WHEN** the Iceberg destination is configured with gzip compression
- **THEN** the Parquet file SHALL use gzip compression
