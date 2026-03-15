import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :compressr, CompressrWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "SolUQazbnpqBg+Yb7WOOPnDK3INEAF+FquEK8EyV2hoBorsHb/ZTD9LVpoWctYM9",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Point ex_aws at LocalStack for testing
config :ex_aws,
  access_key_id: "test",
  secret_access_key: "test",
  region: "us-east-1"

config :ex_aws, :s3,
  scheme: "http://",
  host: "localhost",
  port: 4566

config :ex_aws, :dynamodb,
  scheme: "http://",
  host: "localhost",
  port: 4566

config :ex_aws, :sqs,
  scheme: "http://",
  host: "localhost",
  port: 4566

# Compressr test-specific config
config :compressr,
  dynamodb_table_prefix: "compressr_test_",
  s3_bucket: "compressr-test-events"
