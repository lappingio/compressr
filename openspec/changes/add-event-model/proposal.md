# Change: Define core event data model

## Why
Every component in compressr (sources, pipelines, functions, destinations) operates on events. Without a well-defined event structure, downstream work on pipelines, routing, and processing cannot proceed. This proposal establishes the foundational data model that all events follow as they flow through the system.

## What Changes
- Define the core event structure as an Elixir map with standard, internal, and system field conventions
- Establish `_raw` and `_time` as standard fields present on every event
- Establish `__` prefix convention for internal (read-only, non-serialized) fields
- Establish `compressr_` prefix convention for system fields (replacing Cribl's `cribl_` prefix)
- Define event creation, field access, and serialization behaviors
- New capability: `event-model`

## Impact
- Affected specs: `event-model` (new capability)
- Affected code: No existing code yet; this is a greenfield definition that all future modules will depend on
- Dependencies: None (this is the foundational layer)
- Downstream: Pipelines, functions, sources, destinations, and routes will all consume this model
