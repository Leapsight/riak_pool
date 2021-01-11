# Riak Pool


Yet another Riak connection pool? Not really.

The idea behind this OTP application is to define a behaviour (a.k.a Service Provider Interface) for Riak connection pools, a shim, to enable a stable API that wraps interchangeable backend pool implementations.


## Configuration

Riak pool app settings can be provided through the application environment or the Erlang `sys.config` file as shown below

```erlang
[
    {riak_pool, [
        {backend_mod, my_riak_pool_implementation},
        {riak_host, "127.0.0.1"}.
        {riak_port, 8087}
    ]}
]
```

### Configuration options

| Key | Description | Acceptable Values | Default |
|---|---|---|---|
|`backend_mod` | The default module implementing the `riak_pool` behaviour. <br>This enables to choose the backend pool used by `riak_pool`. <br>It can be overriden during pool creation.| Module name  (see [Available backends](#available-backends) section)| `riak_pool_pooler`|
|`riak_host`| The default Riak KV server IP address or hostname. <br>It can be overriden during pool creation. | string|  "127.0.0.1"|
|`riak_port`| The default Riak KV server port. <br>It can be overriden during pool creation. | integer|  8087|

?> Make sure you add the `riak_pool` application to you `.app.src` file and your `relx` configuration too.

### Available backends

| Module name | Backend |
|---|---|
|`riak_pool_pooler`| [Pooler](https://github.com/seth/pooler) |


### Defining your own backend

You can define your own backend by implementing the `riak_pool` behaviour callbacks.

```erlang
-callback start() -> ok.

-callback stop() -> ok.

-callback add_pool(Poolname :: atom(), Config :: config()) ->
    ok | {error, any()}.

-callback remove_pool(Poolname :: atom()) -> ok | {error, any()}.

-callback checkout(Poolname :: atom(), Opts :: opts()) ->
    {ok, pid()}
    | {error, busy | any()}
    | no_return().

-callback checkin(
    Poolname :: atom(), Pid :: pid(), Status :: atom()) -> ok.

```

## Creating a Pool

You create a pool using the `riak_pool:add_pool/2` function which takes a poolname and a configuration map with the following options:

| Key | Description | Acceptable Values | Default |
|---|---|---|---|
|`backend_mod` | The module implementing the `riak_pool` behaviour. <br>This enables to choose the backend pool used by the pool | Module name | `riak_pool` apps's option with the same name|
|`riak_host`| The Riak KV server IP address or hostname | string|  `riak_pool` apps's option with the same name|
|`min_size`| The minimum number of connections in the pool. | integer|  |
|`max_size`| The maximum number of connections in the pool. | integer|  |
|`idle_removal_interval_secs`| The number of seconds the pool will. | integer|  |
|`max_idle_secs`| The number of seconds the pool will. | integer|  |

Example:

```erlang
Config = #{
    min_size => 10,
    max_size => 20,
    idle_removal_interval_secs => 30,
    max_idle_secs => 30
},
ok = riak_pool:add_pool(my_pool, Config).

```

# Using a pool

Following on the previous example:

## Using function objects

```erlang
riak_pool:execute(
    my_pool,
    fun(Conn) ->
        riakc_pb_socket:get(Conn, BucketType, Key, Opts)
    end,
    #{}
).
```