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

riak_pool:execute(my_pool, fun(_) -> ok end, #{}).
```

## Telemetry Events

`riak_pool` uses the `telemetry` library for instrumentation.

A Telemetry event is made up of the following:

* `name` - A list of atoms that uniquely identifies the event.

* `measurements` - A map of atom keys (e.g. duration) and numeric values.

* `metadata` - A map of key-value pairs that can be used for tagging metrics.

All events time measurements represent time as native units, so to convert the from native units to another unit e.g. `millisecond` you can use:

```erlang
erlang:convert_time_unit(Value, native, millisecond)
```

### [riak_pool, execute, start]
The prefix `[riak_pool, execute]` can be overriden by the user by passing
`#{telemetry => #{event_name => MyName}}` in the `riak_pool:exec_opts()`.

##### Measurements
```erlang
#{
    monotonic_time => -576460737043530333,
    system_time => 1685448802402222902
}
```

##### Metadata
```erlang
#{
    poolname => my_pool,
    telemetry_span_context => #Ref<0.988094963.3517972485.126482>
}
```

### [riak_pool, execute, stop]

##### Measurements
```erlang
#{
    duration => 90788,
    monotonic_time => -576460737042991006
}
```

##### Metadata
```erlang
#{
    poolname => my_pool,
    telemetry_span_context => #Ref<0.988094963.3517972485.126482>
}
```

### [riak_pool, execute, exception]

##### Measurements
```erlang
#{
    ...user provided metadata in riak_pool:exec_opts()
    poolname => my_pool,
    telemetry_span_context => #Ref<0.988094963.3517972485.126482>
}
```

##### Metadata
```erlang
#{
    poolname => my_pool
}
```

### [riak_pool, pool, busy]
This event is triggered every time a worker is checked-out or checked-in and provides the number of pool workers that are in use.

##### Measurements
```erlang
#{
    count => 1
}
```

##### Metadata
```erlang
#{
    poolname => my_pool
}
```

### [riak_pool, pool, idle]
This event is triggered every time a worker is checked-out or checked-in and provides the number of pool workers that are in available.

##### Measurements
```erlang
#{
    count => 1
}
```

##### Metadata
```erlang
#{
    poolname => my_pool
}
```

### [riak_pool, pool, no_members]

##### Measurements
```erlang
#{
    count => 1
}
```

##### Metadata
```erlang
#{
    poolname => my_pool
}
```

