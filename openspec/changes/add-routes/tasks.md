## 1. Data Model and Persistence
- [ ] 1.1 Create Route Ash resource with fields: id, name, description, filter, pipeline_id, destination_id, final (boolean, default true), enabled (boolean, default true), position (integer)
- [ ] 1.2 Create DynamoDB schema and migration for routes table
- [ ] 1.3 Create DevNull destination placeholder (built-in, no configuration required)
- [ ] 1.4 Create default catch-all route seed (filter: `true`, final: ON, position: last)

## 2. Route Evaluation Engine
- [ ] 2.1 Implement sequential route evaluation (ordered by position, top to bottom)
- [ ] 2.2 Implement filter expression evaluation against event fields
- [ ] 2.3 Implement final-flag logic: stop on match when final is ON
- [ ] 2.4 Implement event cloning when final is OFF (clone to pipeline, original continues)
- [ ] 2.5 Implement skip logic for disabled routes
- [ ] 2.6 Implement default route fallback for unmatched events

## 3. REST API
- [ ] 3.1 Implement CRUD endpoints for routes (list, get, create, update, delete)
- [ ] 3.2 Implement route reordering endpoint (update position values)
- [ ] 3.3 Implement route enable/disable toggle endpoint
- [ ] 3.4 Add input validation (unique names, valid filter expressions, valid pipeline/destination references)

## 4. LiveView UI
- [ ] 4.1 Create routes table view with columns: enabled toggle, name, filter, pipeline, destination, final toggle
- [ ] 4.2 Implement drag-and-drop reordering of routes
- [ ] 4.3 Implement inline enable/disable toggle
- [ ] 4.4 Implement route create/edit form (name, description, filter, pipeline, destination, final)
- [ ] 4.5 Implement route delete with confirmation
- [ ] 4.6 Display default catch-all route at bottom of table

## 5. Testing
- [ ] 5.1 Unit tests for route evaluation engine (filter matching, ordering, final flag, cloning)
- [ ] 5.2 Unit tests for Route Ash resource validations
- [ ] 5.3 Integration tests for REST API endpoints
- [ ] 5.4 LiveView tests for routes table interactions
