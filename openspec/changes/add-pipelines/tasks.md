## 1. Pipeline Engine Core
- [ ] 1.1 Define `Compressr.Pipeline.Function` behaviour (common interface: filter, final, execute)
- [ ] 1.2 Implement pipeline executor (sequential top-to-bottom function execution)
- [ ] 1.3 Implement filter expression evaluation on each function
- [ ] 1.4 Implement Final toggle logic (stop downstream processing for matched events)
- [ ] 1.5 Define DynamoDB schema for pipeline configurations
- [ ] 1.6 Implement pipeline CRUD via Ash resources

## 2. MVP Functions
- [ ] 2.1 Implement Eval function (add, modify, remove fields via expressions)
- [ ] 2.2 Implement Drop function (remove events matching filter)
- [ ] 2.3 Implement Mask function (regex-based pattern replacement for PII redaction)
- [ ] 2.4 Implement Regex Extract function (named capture group field extraction)
- [ ] 2.5 Implement Rename function (modify field names via explicit pairs or expression)
- [ ] 2.6 Implement Lookup function (enrich events from external lookup tables)
- [ ] 2.7 Implement Comment function (no-op annotation for pipeline readability)

## 3. Pipeline Attachment Points
- [ ] 3.1 Implement pre-processing pipeline attachment on sources
- [ ] 3.2 Implement processing pipeline attachment on routes
- [ ] 3.3 Implement post-processing pipeline attachment on destinations

## 4. Expression Language
- [ ] 4.1 Research and decide on expression language (see open question in spec)
- [ ] 4.2 Implement expression parser and evaluator
- [ ] 4.3 Integrate expression evaluator into function filter and value fields

## 5. Testing
- [ ] 5.1 Unit tests for each MVP function
- [ ] 5.2 Unit tests for pipeline executor (ordering, filter, Final toggle)
- [ ] 5.3 Integration tests for pipeline attachment points
- [ ] 5.4 Property-based tests for expression evaluation edge cases
