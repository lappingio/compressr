# Change: Add data ingestion source layer

## Why
Compressr cannot process any data without sources. This proposal defines the MVP data ingestion layer -- the entry points where logs, metrics, and traces enter the system. Sources are the first component in the pipeline (after the event model and auth) and must exist before routing or processing can be implemented.

## What Changes
- Define a common `Compressr.Source` behaviour that all source types implement
- Add Syslog source (UDP and TCP push-based listeners)
- Add HTTP source with Splunk HEC-compatible endpoint (push-based)
- Add S3 collector source with Glacier tiered-storage rehydration and replay (pull-based; compressr's key differentiator)
- Source configuration CRUD protected by OIDC (control plane auth)
- Per-source data plane authentication (HEC tokens for HTTP/HEC, unauthenticated for Syslog)
- Source configurations stored in DynamoDB
- Sources emit events into the routing layer using the event model from `add-event-model`

## Impact
- Affected specs: `sources` (new capability)
- Affected code: New `Compressr.Source` behaviour, `Compressr.Source.Syslog`, `Compressr.Source.HTTP`, `Compressr.Source.S3` modules, DynamoDB source config table, Phoenix API routes for source CRUD, LiveView source management UI
- Dependencies: `add-event-model` (events emitted by sources), `add-oidc-auth` (control plane auth for source config CRUD)
- Downstream: `add-routes` (sources feed events into routing), `add-pipelines` (pre-processing pipelines on sources)
