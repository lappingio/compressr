<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# Development Environment

## Prerequisites
- Elixir 1.19+ / OTP 28+
- Docker (for LocalStack)

## Running locally
```bash
docker compose up -d          # Start LocalStack (S3, DynamoDB, SQS, EventBridge)
mix deps.get                  # Install dependencies
mix test                      # Run all tests against LocalStack
mix phx.server                # Start the web server
```

## Test infrastructure
- All AWS services are mocked via LocalStack at `localhost:4566`
- Test helper (`test/support/localstack.ex`) bootstraps DynamoDB tables and S3 buckets
- Tests require LocalStack running — `mix test` will error with instructions if it's down
- Config in `config/test.exs` points ex_aws at LocalStack

## Key dependencies
- `ex_aws` + `ex_aws_s3` + `ex_aws_dynamo` + `ex_aws_sqs` — AWS SDK
- `phoenix` + `phoenix_live_view` — Web framework and real-time UI
- `jason` — JSON encoding/decoding
- `hackney` — HTTP client for ex_aws

## Architecture reference
- Read `openspec/project.md` for architecture decisions
- Read `research/reviews/` for security, ops, and cost analysis
- Read `research/cribl-stream/` for Cribl Stream requirements research