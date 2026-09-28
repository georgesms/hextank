import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :hextank, HextankWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "mCFJ3MDUPaqC4e39ZGWx6NhnFTjrkBFQwvs+ffMuMr9uYrdZdOeqrtP20VEULtjs",
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

# Tests never touch the dev data folder. Storage tests use their own @tag :tmp_dir.
config :hextank, :data_dir, Path.expand("../tmp/test_data", __DIR__)

# Tables go to sleep quickly in tests, to exercise waking them up again.
config :hextank, :table_idle_timeout, 200
