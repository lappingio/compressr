## 1. Pricing Configuration
- [ ] 1.1 Create Ash resource for AWS pricing tables (S3 storage classes, S3 API operations, data transfer, DynamoDB capacity, EC2 instance types)
- [ ] 1.2 Implement default pricing data seeded from current us-east-1 on-demand prices
- [ ] 1.3 Build REST API endpoints for viewing and updating pricing configuration
- [ ] 1.4 Add LiveView admin page for editing pricing tables
- [ ] 1.5 Write tests for pricing CRUD operations

## 2. Usage Metric Collection
- [ ] 2.1 Define usage metric data model (metric type, source/destination/pipeline/route attribution, value, timestamp)
- [ ] 2.2 Instrument S3 destination to emit bytes-written and PUT/GET counts per operation
- [ ] 2.3 Instrument Glacier restore flow to emit restore request counts and bytes restored per tier
- [ ] 2.4 Instrument node-to-node forwarding to track cross-AZ bytes transferred (using node AZ metadata)
- [ ] 2.5 Instrument DynamoDB operations to track consumed RCU/WCU
- [ ] 2.6 Implement compute utilization tracking per source/pipeline with instance type metadata
- [ ] 2.7 Build GenServer for metric aggregation (roll up raw metrics into hourly/daily buckets)
- [ ] 2.8 Write tests for metric collection and aggregation

## 3. Cost Calculation Engine
- [ ] 3.1 Implement cost calculator module that joins usage metrics with pricing tables
- [ ] 3.2 Calculate per-source, per-destination, per-pipeline, and per-route cost breakdowns
- [ ] 3.3 Calculate total monthly cost estimate (current month projection based on rate)
- [ ] 3.4 Generate daily/weekly/monthly cost trend data
- [ ] 3.5 Implement cost optimization suggestion engine (detect suboptimal configurations)
- [ ] 3.6 Write tests for cost calculations and projections

## 4. Pre-Action Cost Estimates
- [ ] 4.1 Implement Glacier replay cost estimator (show Bulk/Standard/Expedited options with cost, time, per-GB rate)
- [ ] 4.2 Integrate cost estimate into Glacier replay confirmation flow
- [ ] 4.3 Implement Athena query cost estimator (estimate bytes scanned from Iceberg table metadata and partition pruning)
- [ ] 4.4 Track actual costs after Glacier restore completes and compare to estimate
- [ ] 4.5 Write tests for pre-action cost estimates

## 5. Cost Dashboard (LiveView)
- [ ] 5.1 Build LiveView page for total monthly cost overview
- [ ] 5.2 Build cost breakdown view by source, destination, pipeline, and route
- [ ] 5.3 Build cost trend charts (daily/weekly/monthly time series)
- [ ] 5.4 Build cost optimization suggestions panel
- [ ] 5.5 Add real-time updates to dashboard via PubSub
- [ ] 5.6 Write LiveView tests for dashboard components

## 6. REST API for Cost Data
- [ ] 6.1 Implement GET /api/v1/costs/summary endpoint (total monthly cost, breakdown)
- [ ] 6.2 Implement GET /api/v1/costs/breakdown endpoint (by source/destination/pipeline/route)
- [ ] 6.3 Implement GET /api/v1/costs/trends endpoint (time series data)
- [ ] 6.4 Implement GET /api/v1/costs/suggestions endpoint (optimization suggestions)
- [ ] 6.5 Write API integration tests

## 7. Cost Alerts
- [ ] 7.1 Create Ash resource for cost alert rules (threshold, scope, notification method)
- [ ] 7.2 Implement alert evaluation GenServer (periodic check of projected costs against thresholds)
- [ ] 7.3 Implement alert notification delivery (initially: in-app notification via LiveView)
- [ ] 7.4 Build LiveView page for managing cost alert rules
- [ ] 7.5 Expose REST API endpoints for cost alert CRUD
- [ ] 7.6 Write tests for alert evaluation and notification
