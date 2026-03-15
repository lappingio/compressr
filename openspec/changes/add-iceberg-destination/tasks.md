## 1. Rust NIF for Parquet Writing
- [ ] 1.1 Create Rustler NIF project for Parquet writing using Arrow/Parquet Rust crates
- [ ] 1.2 Implement Parquet writer NIF with configurable compression (snappy, zstd, gzip)
- [ ] 1.3 Implement configurable row group size and page size parameters
- [ ] 1.4 Implement schema mapping from Elixir terms to Arrow schema
- [ ] 1.5 Implement buffered writing with flush-to-bytes output (returns Parquet file bytes to Elixir)
- [ ] 1.6 Write ExUnit tests for Parquet NIF (round-trip write/read, compression variants, schema types)

## 2. Iceberg Metadata Management
- [ ] 2.1 Add `ex_iceberg` dependency (Elixir wrapper around iceberg-rust via NIF)
- [ ] 2.2 Implement Iceberg table creation with partition spec (date-based daily/hourly)
- [ ] 2.3 Implement Iceberg manifest and snapshot management for data file commits
- [ ] 2.4 Implement schema evolution support (adding new fields from events)
- [ ] 2.5 Write ExUnit tests for Iceberg metadata operations (create table, add files, evolve schema)

## 3. AWS Glue Catalog Integration
- [ ] 3.1 Add `ex_aws_glue` dependency or implement Glue Catalog API calls via `ex_aws`
- [ ] 3.2 Implement Glue database and table registration for Iceberg tables
- [ ] 3.3 Implement Glue table schema synchronization on schema evolution
- [ ] 3.4 Write ExUnit tests for Glue Catalog integration (mocked API calls)

## 4. Iceberg Destination Module
- [ ] 4.1 Create `Compressr.Destination.Iceberg` implementing `Compressr.Destination` behaviour
- [ ] 4.2 Implement `init/1` with Iceberg table initialization and Glue registration
- [ ] 4.3 Implement `write/2` with event buffering, schema detection, and Parquet file building
- [ ] 4.4 Implement minimum file size enforcement (configurable 50-100 MB threshold)
- [ ] 4.5 Implement time-based file close (configurable interval, default 5 minutes)
- [ ] 4.6 Implement `flush/1` to close current Parquet file, upload to S3, and commit to Iceberg metadata
- [ ] 4.7 Implement `stop/1` for graceful shutdown (flush pending data, finalize metadata)
- [ ] 4.8 Implement `healthy?/1` with Glue connectivity and S3 write checks
- [ ] 4.9 Write ExUnit tests for destination lifecycle (init, write, flush, stop)

## 5. Schema Management
- [ ] 5.1 Implement schema auto-detection from event fields (type inference for string, integer, float, boolean, timestamp)
- [ ] 5.2 Implement optional explicit schema definition via destination configuration
- [ ] 5.3 Implement schema merge logic for handling events with different field sets
- [ ] 5.4 Write ExUnit tests for schema detection and evolution

## 6. Configuration and Ash Resource
- [ ] 6.1 Add `iceberg` to the destination type enum in the Destination Ash resource
- [ ] 6.2 Add Iceberg-specific configuration attributes (S3 bucket/prefix, Glue database/table, partition granularity, Parquet settings, storage class, schema definition)
- [ ] 6.3 Implement configuration validation for Iceberg destination settings
- [ ] 6.4 Write ExUnit tests for configuration validation

## 7. S3 Upload Integration
- [ ] 7.1 Implement S3 multipart upload for Parquet files using `ex_aws_s3`
- [ ] 7.2 Implement configurable S3 storage class (Intelligent-Tiering default, Standard, Glacier)
- [ ] 7.3 Implement S3 path generation with Iceberg-compatible partition layout
- [ ] 7.4 Write ExUnit tests for S3 upload (mocked)

## 8. Integration Testing
- [ ] 8.1 Write integration test: end-to-end event flow through Iceberg destination to local S3 (LocalStack)
- [ ] 8.2 Write integration test: schema evolution across multiple batches
- [ ] 8.3 Write integration test: file size enforcement and time-based close
- [ ] 8.4 Write integration test: Athena-compatible table structure verification
