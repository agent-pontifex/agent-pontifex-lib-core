-record(acquire_options, {
    ttl_ms :: integer(),
    wait_timeout_ms :: integer(),
    retry_interval_ms :: integer(),
    holder :: gleam@option:option(binary())
}).
