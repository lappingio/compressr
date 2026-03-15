# Change: Add AWS Cost Awareness

## Why
Compressr targets cost-sensitive SMBs, but operators currently have no visibility into what their compressr deployment actually costs. Without cost awareness built into the product, operators discover AWS bill surprises (cross-AZ transfer, S3 PUTs from small files, Glacier restore fees) only after the damage is done. Self-reported cost tracking builds trust with the CFO and turns compressr into its own FinOps tool for the observability pipeline layer.

## What Changes
- Track resource consumption per source, destination, pipeline, and route
- Calculate estimated AWS costs from usage metrics using configurable pricing tables (no AWS Billing API required)
- Track cost drivers: S3 storage, S3 API calls, Glacier restore costs, cross-AZ data transfer, DynamoDB consumed capacity, and compute apportionment
- Provide pre-action cost estimates for expensive operations (Glacier replay, Athena query scans)
- Surface cost data in a LiveView dashboard with breakdowns, trends, and optimization suggestions
- Expose REST API endpoints for cost data (FinOps tool integration)
- Support configurable cost alerts (threshold-based monthly cost warnings)

## Impact
- Affected specs: `cost-awareness` (new capability)
- Affected code:
  - New Ash resources for cost metrics, pricing configuration, and cost alerts
  - New GenServer(s) for metric aggregation and cost calculation
  - New LiveView pages for cost dashboard
  - New Phoenix controllers for REST API cost endpoints
  - Integration points in existing source, destination, pipeline, and route modules to emit usage metrics
  - Integration with Glacier replay flow for pre-action cost estimates
