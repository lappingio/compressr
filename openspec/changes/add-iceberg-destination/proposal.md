# Change: Add Apache Iceberg Table Format Destination

## Why
The existing S3 destination writes raw/NDJSON files suitable for archival, but these files are not directly queryable without ETL. By adding an Iceberg destination that writes Parquet data files registered in AWS Glue Catalog, archived logs become immediately queryable via Athena, Spark, Trino, or DuckDB — enabling the value proposition: "your logs are already in S3, now you can search them with Athena for $5/TB scanned."

## What Changes
- Add a new `iceberg` destination type that writes columnar Parquet files to S3
- Integrate Apache Iceberg table format for schema evolution, time travel, and partition evolution
- Use AWS Glue Catalog for table registration (required for Athena compatibility)
- Introduce `ex_iceberg` (Elixir library wrapping iceberg-rust via NIF) for Iceberg metadata management
- Introduce a Rust NIF for Parquet writing using Arrow/Parquet Rust crates
- Support configurable partitioning (daily default, hourly option) for efficient time-range queries
- Enforce minimum file sizes (50-100 MB) to avoid S3 small-file performance problems
- Support configurable Parquet compression (snappy, zstd, gzip), row group size, and page size
- Support schema auto-detection from event fields with optional explicit schema definition
- Support configurable S3 storage class (Intelligent-Tiering default, Standard, Glacier)
- This is a NEW destination type alongside the existing S3 destination — the existing S3 destination remains unchanged

## Impact
- Affected specs: `destinations` (adds new destination type)
- Affected code: New `Compressr.Destination.Iceberg` module implementing the `Compressr.Destination` behaviour, new Rust NIFs for Parquet writing and Iceberg metadata, new Ash resource attributes for Iceberg-specific configuration
- New dependencies: `ex_iceberg` (Elixir/Rust NIF), Arrow/Parquet Rust crates (via Rustler NIF), `ex_aws_glue` for Glue Catalog API
- No breaking changes to existing destinations or APIs
