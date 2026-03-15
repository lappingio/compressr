## ADDED Requirements

### Requirement: AWS Pricing Configuration
The system SHALL store AWS pricing data as operator-editable configuration rather than hardcoded values. Pricing tables SHALL cover S3 storage class rates, S3 API operation rates, data transfer rates, DynamoDB capacity unit rates, and EC2 instance type rates. The system SHALL ship with default pricing based on current us-east-1 on-demand prices.

#### Scenario: Operator views default pricing
- **WHEN** the system is deployed with no custom pricing configuration
- **THEN** the system uses default us-east-1 on-demand prices for all cost calculations

#### Scenario: Operator updates pricing
- **WHEN** an operator updates an S3 storage class rate via the REST API or LiveView admin page
- **THEN** subsequent cost calculations use the updated rate
- **THEN** historical cost data retains the rate that was active at the time of calculation

### Requirement: Usage Metric Collection
The system SHALL track its own resource consumption and attribute usage to individual sources, destinations, pipelines, and routes. Tracked metrics SHALL include S3 bytes written per storage class, S3 PUT and GET counts per destination, Glacier restore request counts and bytes restored per tier, cross-AZ data transfer bytes (derived from node AZ metadata), DynamoDB consumed read and write capacity units, and compute utilization apportioned by source and pipeline activity.

#### Scenario: S3 destination usage tracking
- **WHEN** a pipeline writes events to an S3 destination
- **THEN** the system records the number of bytes written and the number of PUT operations, attributed to the destination, the pipeline that produced the data, and the route that directed it

#### Scenario: Cross-AZ transfer tracking
- **WHEN** events are forwarded from a node in one AZ to a destination-owning node in a different AZ
- **THEN** the system records the bytes transferred as cross-AZ data transfer, attributed to the destination

#### Scenario: DynamoDB capacity tracking
- **WHEN** the system performs DynamoDB read or write operations
- **THEN** the system records the consumed RCU and WCU

#### Scenario: Compute utilization tracking
- **WHEN** sources and pipelines consume CPU time on a node with a known instance type
- **THEN** the system apportions compute cost to each source and pipeline based on their relative CPU utilization

### Requirement: Cost Calculation
The system SHALL calculate estimated AWS costs by joining usage metrics with the configured pricing tables. The system SHALL produce cost breakdowns per source, per destination, per pipeline, and per route. The system SHALL project a total monthly cost estimate based on the current rate of resource consumption. The system SHALL NOT require access to the AWS Billing API.

#### Scenario: Monthly cost projection
- **WHEN** an operator views the cost dashboard mid-month
- **THEN** the system displays the actual cost incurred so far and a projected total for the full month based on the current consumption rate

#### Scenario: Per-destination cost breakdown
- **WHEN** an operator requests a cost breakdown by destination
- **THEN** the system displays each destination with its estimated cost broken down by S3 storage, S3 API calls, and data transfer

### Requirement: Cost Trends
The system SHALL maintain cost trend data at daily, weekly, and monthly granularity. The system SHALL retain trend data for at least 90 days.

#### Scenario: Daily cost trend
- **WHEN** an operator views cost trends for the past 30 days
- **THEN** the system displays a daily time series of total estimated cost and per-cost-driver breakdown

### Requirement: Pre-Action Glacier Replay Cost Estimate
Before initiating a Glacier replay, the system SHALL display a cost estimate showing all available retrieval tiers (Bulk, Standard, Expedited where applicable) with the estimated cost, estimated retrieval time, and per-GB rate for each tier. The system SHALL require operator confirmation before proceeding. After the restore completes, the system SHALL track the actual cost and make it available alongside the original estimate.

#### Scenario: Operator initiates Glacier replay
- **WHEN** an operator requests a replay of data stored in Glacier Flexible Retrieval
- **THEN** the system displays a table with Bulk, Standard, and Expedited options showing estimated cost, estimated time to availability, and per-GB rate
- **THEN** the system waits for the operator to select a tier and confirm before initiating the restore

#### Scenario: Actual cost tracked after restore
- **WHEN** a Glacier restore completes
- **THEN** the system records the actual bytes restored and calculates the actual cost
- **THEN** the actual cost is available alongside the original estimate in the cost dashboard

### Requirement: Pre-Action Athena Query Cost Estimate
Before executing an Athena query against Iceberg tables, the system SHALL estimate the bytes that will be scanned based on Iceberg table metadata and partition pruning, and display the estimated query cost. The system SHALL require operator confirmation before executing the query.

#### Scenario: Operator initiates Athena query
- **WHEN** an operator submits a query against an Iceberg table
- **THEN** the system estimates the bytes to be scanned using Iceberg metadata and partition information
- **THEN** the system displays the estimated scan size and cost before execution
- **THEN** the system waits for operator confirmation before running the query

### Requirement: Cost Dashboard
The system SHALL provide a LiveView dashboard displaying total monthly cost estimate, cost breakdown by source, destination, pipeline, and route, cost trends over time (daily, weekly, monthly), and cost optimization suggestions. The dashboard SHALL update in real time as new usage metrics arrive.

#### Scenario: Dashboard displays cost overview
- **WHEN** an operator navigates to the cost dashboard
- **THEN** the system displays the current month total cost estimate, top cost drivers, and a cost trend chart

#### Scenario: Dashboard shows optimization suggestions
- **WHEN** the system detects a suboptimal configuration (e.g., S3 file close interval producing files smaller than 50 MB, or cross-AZ transfer that could be avoided with single-AZ deployment)
- **THEN** the dashboard displays an actionable suggestion with the estimated monthly savings

### Requirement: Cost REST API
The system SHALL expose REST API endpoints for retrieving cost data to enable integration with external FinOps tools. Endpoints SHALL include cost summary, cost breakdown by source/destination/pipeline/route, cost trends, and cost optimization suggestions.

#### Scenario: External tool queries cost summary
- **WHEN** an external tool sends GET /api/v1/costs/summary
- **THEN** the system returns the current month total cost estimate, cost breakdown by cost driver, and projection for the full month

#### Scenario: External tool queries cost breakdown
- **WHEN** an external tool sends GET /api/v1/costs/breakdown with a group_by parameter of "destination"
- **THEN** the system returns per-destination cost data with cost driver details

### Requirement: Cost Alerts
The system SHALL support configurable cost alert rules that trigger when the projected monthly cost exceeds an operator-defined threshold. Alert rules SHALL be scoped to total cost or to a specific source, destination, pipeline, or route. The system SHALL evaluate alert conditions periodically and deliver notifications via in-app LiveView notifications.

#### Scenario: Total cost alert triggers
- **WHEN** an operator configures an alert with threshold $500/month for total cost
- **THEN** the system evaluates projected monthly cost periodically
- **THEN** the system delivers an in-app notification when the projection exceeds $500

#### Scenario: Per-destination cost alert
- **WHEN** an operator configures an alert with threshold $100/month scoped to a specific S3 destination
- **THEN** the system evaluates the projected monthly cost for that destination
- **THEN** the system delivers an in-app notification when the projection exceeds $100

### Requirement: Cost Optimization Suggestions
The system SHALL analyze usage patterns and configuration to generate actionable cost optimization suggestions. Suggestions SHALL include estimated savings amounts. Suggestion categories SHALL include at minimum: S3 file size optimization (increase file close interval to reduce PUT costs), deployment topology optimization (single-AZ vs multi-AZ trade-offs), and storage class optimization (Intelligent-Tiering vs fixed storage class).

#### Scenario: Small file size detection
- **WHEN** the system detects that an S3 destination is producing files with an average size below 50 MB
- **THEN** the system generates a suggestion to increase the file close interval, with the estimated monthly savings from reduced PUT costs

#### Scenario: Cross-AZ cost optimization
- **WHEN** the system detects significant cross-AZ data transfer costs in a multi-node deployment
- **THEN** the system generates a suggestion showing the estimated monthly savings from switching to a single-AZ deployment or enabling AZ-affinity routing
