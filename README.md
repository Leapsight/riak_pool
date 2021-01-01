# Riak Pool


Yet another Riak Pool? Not really. The idea behind this OTP application is to define a Service Provider Iterface for Riak Pools.

## Configuration

Riak pool app settings can be provided through the application environment or the `sys.config` file as below

```erlang
[
    {riak_pool, [
        {backend_mod, my_riak_pool_implementation},
        {riak_host, "127.0.0.1"}.
        {riak_port, 8087}
    ]}
]
```

## Creating

```erlang
Config = #{
    min_size => 10,
    max_size => 20,
    idle_removal_interval_secs => 30,
    max_idle_secs => 30
},
ok = riak_pool:add_pool(my_pool, Config).
```
