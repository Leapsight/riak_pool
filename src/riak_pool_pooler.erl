-module(riak_pool_pooler).
-behaviour(riak_pool).

-define(DEFAULT_TIMEOUT, 60000).

%% BEHAVIOUR CALLBACKS
-export([add_pool/2]).
-export([checkin/3]).
-export([checkout/2]).
-export([remove_pool/1]).
-export([start/0]).
-export([stop/0]).

%% PRiVATE
-export([new_connection/3]).



%% =============================================================================
%% CALLBACKS
%% =============================================================================


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec start() -> ok.

start() ->
    %% ok = pooler:start(),
    case application:ensure_all_started(pooler) of
        {ok, _} -> ok;
        {error, _} = Error -> Error
    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec stop() -> ok.

stop() ->
    pooler:stop().


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec add_pool(Poolname :: atom(), Config :: riak_pool:config()) ->
    ok | {error, any()}.

add_pool(Poolname, Config) ->
    InitCount = maps:get(min_size, Config, 20),
    MaxCount = maps:get(max_size, Config, 40),
    MaxAge = maps:get(max_idle_secs, Config, {30, sec}),
    %% Time between checks for the removal of stale pool members.  A
    %% stale members is one that have not been accessed in `max_age'
    %% time units.
    %% Culling can be disabled by specifying a zero time value. Culling
    %% will also be disabled if `init_count' is the same as `max_count'.
    %% Culling of idle members will never reduce the pool
    %% below `init_count'.
    CullInterval = maps:get(
        idle_removal_interval_secs, Config, {30, sec}
    ),
    %% Time limit for member starts.
    MemberStartTimeout = {1, min},
    Host = host(Config),
    Port = port(Config),
    RiakOpts = riak_opts(Config),

    PoolerConfig = [
        %% We add group just in case pooler is being used by other app in the
        %% node
        %% {group, ?MODULE},
        {name, Poolname},
        {start_mfa, {?MODULE, new_connection, [Host, Port, RiakOpts]}},
        {init_count, InitCount},
        {max_count, MaxCount},
        {max_age, MaxAge},
        {cull_interval, CullInterval},
        {member_start_timeout, MemberStartTimeout}
    ],

    case pooler:new_pool(PoolerConfig) of
        {error, _} = Error ->
            Error;
        _ ->
            ok
    end.



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec remove_pool(Poolname :: atom()) -> ok | {error, any()}.

remove_pool(Poolname) ->
    pooler:rm_pool(Poolname).



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec checkout(Poolname :: atom(), Opts :: riak_pool:opts()) ->
    {ok, pid()} | {error, any()}.

checkout(Poolname, Opts) ->
    Timeout = maps:get(timeout, Opts, ?DEFAULT_TIMEOUT),
    case pooler:take_member(Poolname, Timeout) of
        Pid when is_pid(Pid) ->
            {ok, Pid};
        error_no_members ->
            {error, busy}
    end.



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec checkin(Poolname :: atom(), Pid :: pid(), Status :: atom()) ->
    ok.

checkin(Poolname, Pid, Status) ->
    %% TODO Check for overload status and implement backpreassure
    pooler:return_member(Poolname, Pid, coerce_status(Status)).




%% =============================================================================
%% PRIVATE
%% =============================================================================


%% @private
coerce_status(ok) -> ok;
coerce_status(fail) -> fail;
coerce_status(_) -> fail.


%% @private
new_connection(Host, Port, RiakOpts) ->
    case riakc_pb_socket:start_link(Host, Port, RiakOpts) of
        {ok, Pid} ->
            {ok, Pid};
        {error, _} = Error ->
             %% TODO Check for errors and implement backpreassure
            Error
    end.


%% @private
host(#{riak_host := Val}) ->
    Val;

host(_) ->
    riak_pool_config:get(riak_host, "127.0.0.1").


%% @private
port(#{riak_port := Val}) ->
    Val;

port(_) ->
    riak_pool_config:get(riak_port, 8087).


%% @private
riak_opts(#{riak_opts := Val}) ->
    Val;

riak_opts(_) ->
    riak_pool_config:get(riak_opts, [
        {queue_if_disconnected, false},
        {auto_reconnect, false},
        {keepalive, true},
        {connect_timeout, 2 * ?DEFAULT_TIMEOUT}
    ]).