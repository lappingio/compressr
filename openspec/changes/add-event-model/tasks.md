## 1. Core Event Module
- [ ] 1.1 Create `Compressr.Event` module with struct/map definition containing `_raw` and `_time` standard fields
- [ ] 1.2 Implement `new/0` and `new/1` constructors that set `_time` to current Unix epoch when not provided
- [ ] 1.3 Implement `put_field/3` and `get_field/2` for standard field access
- [ ] 1.4 Implement guard/validation that prevents writing to internal (`__`) fields via public API

## 2. Field Classification
- [ ] 2.1 Implement `internal_field?/1` to detect `__` prefixed fields
- [ ] 2.2 Implement `system_field?/1` to detect `compressr_` prefixed fields
- [ ] 2.3 Implement `put_internal/3` for setting internal fields (used by sources and pipeline internals only)
- [ ] 2.4 Implement `put_system/3` for setting system fields (used by post-processing only)

## 3. Serialization
- [ ] 3.1 Implement `to_external_map/1` that strips all `__` prefixed fields from the event
- [ ] 3.2 Implement `to_json/1` that serializes the external representation
- [ ] 3.3 Implement `from_raw/1` that creates an event from a raw string (sets `_raw` and `_time`)

## 4. Tests
- [ ] 4.1 Unit tests for event creation with and without explicit `_time`
- [ ] 4.2 Unit tests for field classification helpers
- [ ] 4.3 Unit tests for internal field read-only enforcement
- [ ] 4.4 Unit tests for serialization (external map strips internal fields, preserves system fields)
- [ ] 4.5 Property-based tests for round-trip serialization of arbitrary field maps
