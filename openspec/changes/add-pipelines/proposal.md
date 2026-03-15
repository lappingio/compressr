# Change: Add processing pipelines and MVP function set

## Why
Compressr needs a processing engine to transform, enrich, and filter events as they flow from sources to destinations. Pipelines with ordered functions are the core abstraction that makes an observability pipeline useful beyond simple routing.

## What Changes
- Define the pipeline abstraction: ordered sequences of functions executed sequentially top-to-bottom
- Define three pipeline attachment points: pre-processing (on sources), processing (on routes), post-processing (on destinations)
- Implement MVP function set: Eval, Drop, Mask, Regex Extract, Rename, Lookup, Comment
- Define the common function interface as an Elixir behaviour with filter expression and Final toggle
- Store pipeline configurations in DynamoDB

## Impact
- Affected specs: `pipelines` (new capability)
- Affected code: New Elixir modules for pipeline execution engine, function behaviours, DynamoDB schema for pipeline configs
- Dependencies: Requires event model (see `add-event-model` change) for the event structure that functions operate on
