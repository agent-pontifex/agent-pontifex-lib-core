-record(config, {
    base_url :: binary(),
    internal :: gleam@option:option({binary(), binary()}),
    api_key :: gleam@option:option(binary()),
    allow_cleartext_internal :: boolean(),
    generate_holder :: fun(() -> binary())
}).
