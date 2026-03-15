# Change: Add data output layer (destinations)

## Why
Compressr needs a destination abstraction to deliver processed events to external systems. Without destinations, the pipeline has no output. This proposal defines the MVP destination types and the common behaviour interface that all destinations implement.

## What Changes
- Introduce a `Compressr.Destination` Elixir behaviour defining the common interface for all destination types
- Add MVP destination implementations: S3 (with tiered storage awareness), Elasticsearch, Splunk HEC, DevNull
- Define destination configuration as an Ash resource stored in DynamoDB
- Add per-destination backpressure configuration (block, drop, queue) with persistent queuing deferred as a dependency
- Add per-destination batching and output format configuration
- Add optional post-processing pipeline reference per destination
- Add enabled/disabled toggle per destination

## Impact
- Affected specs: `destinations` (new capability)
- Affected code: `lib/compressr/destinations/`, Ash resources for destination config, DynamoDB schema
- Dependencies: `add-pipelines` (post-processing pipeline reference), `add-event-model` (event structure flowing to destinations), object storage behaviour from project.md (S3 destination)
- Deferred: persistent queue implementation (noted as future work; MVP supports block and drop only, queue mode accepted in config but requires separate proposal to implement the backing store)
