-module(riak_pool_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0]).

-compile([nowarn_export_all, export_all]).



all() ->
    [
        connection_refused,
        execute_no_connection,
        execute_with_user_connection,
        execute_reuses_parent_connection,
        execute_errors,
        execute_exceptions,
        execute_timeout_retry,
        execute_disconnected_retry
    ].


init_per_suite(Config) ->
    meck:unload(),
    _ = application:ensure_all_started(riak_pool),
    meck:new(riak_pool, [passthrough]),
    Config.

end_per_suite(Config) ->
    meck:unload(),
    {save_config, Config}.


connection_refused(_) ->
    ?assertEqual(
        {error, {tcp, econnrefused}},
        riakc_pb_socket:start("127.0.0.1", 1972)
    ).



execute_no_connection(_) ->
    ?assertEqual(
        {error, invalid_poolname},
        riak_pool:execute(
            undefined,
            fun(_) -> ok end,
            #{}
        ),
        "If poolname is undefined we need to have a connection"
    ),

    {ok, Conn} = riakc_pb_socket:start_link("127.0.0.1", 8087),
    pong = riakc_pb_socket:ping(Conn),
    ?assertEqual(
        {ok, true},
        riak_pool:execute(
            undefined,
            fun(Pid) -> Pid =:= Conn end,
            #{connection => Conn}
        ),
        "If we pass a connection, poolname can be undefined"
    ).


execute_with_user_connection(_) ->
    {ok, Conn} = riakc_pb_socket:start_link("127.0.0.1", 8087),
    pong = riakc_pb_socket:ping(Conn),

    ?assertEqual(
        {error, invalid_poolname},
        riak_pool:execute(
            does_not_exist,
            fun(_) -> ok end,
            #{}
        ),
        "We validate 'does_not_exist' is not a pool"
    ),

    ?assertEqual(
        {ok, true},
        riak_pool:execute(
            does_not_exist,
            fun(Pid) -> Pid =:= Conn end,
            #{connection => Conn}
        ),
        "The user-provided connection takes precedence."
    ),

    ?assertEqual(
        {ok, ok},
        riak_pool:execute(
            default,
            fun(_) ->
                {ok, true} = riak_pool:execute(
                    does_not_exist,
                    fun(Pid) -> Pid =:= Conn end,
                    #{connection => Conn}
                ),
                ok
            end,
            #{}
        ),
        "Even when a connection exists for the process, "
        "the user-provided connection is used"
    ).


execute_reuses_parent_connection(_) ->
    ?assertEqual(
        {ok, ok},
        riak_pool:execute(
            default,
            fun(Pid1) ->
                {ok, true} = riak_pool:execute(
                    default,
                    fun(Pid2) -> Pid1 =:= Pid2 end,
                    #{}
                ),
                ok
            end,
            #{}
        )
    ),
    connection_has_cleared().


execute_errors(_) ->
    ?assertEqual(
        {error, timeout},
        riak_pool:execute(
            default,
            fun(_) -> throw(timeout) end,
            #{}
        ),
        "If any pool or riak error occurs, execute will return an error tuple."
    ),
    connection_has_cleared(),


    ?assertEqual(
        {error, disconnected},
        riak_pool:execute(
            default,
            fun(_) -> throw(disconnected) end,
            #{}
        ),
        "If any pool or riak error occurs, execute will return an error tuple."
    ),
    connection_has_cleared(),

    ?assertEqual(
        {error, overload},
        riak_pool:execute(
            default,
            fun(_) -> throw(overload) end,
            #{}
        ),
        "If any pool or riak error occurs, execute will return an error tuple."
    ),
    connection_has_cleared().


execute_exceptions(_) ->
    ?assertException(
        error,
        foo,
        riak_pool:execute(
            default,
            fun(_) -> error(foo) end,
            #{}
        ),
        "If any exception occurs, execute will raise the exception."
    ),
    connection_has_cleared(),

    ?assertException(
        throw,
        foo,
        riak_pool:execute(
            default,
            fun(_) -> throw(foo) end,
            #{}
        ),
        "If any exception occurs, execute will raise the exception."
    ),
    connection_has_cleared(),

    ?assertException(
        exit,
        foo,
        riak_pool:execute(
            default,
            fun(_) -> exit(foo) end,
            #{}
        ),
        "If any exception occurs, execute will raise the exception."
    ),
    connection_has_cleared().


execute_timeout_retry(Config) ->
    execute_retry(Config, timeout).


execute_disconnected_retry(Config) ->
    execute_retry(Config, disconnected).




%% =============================================================================
%% UTILS
%% =============================================================================




connection_has_cleared() ->
    ?assertEqual(
        undefined,
        riak_pool:get_connection(),
        "The connection was cleared from the process dictionary"
    ).



execute_retry(_, Reason) ->

    ?assertEqual(
        {error, Reason},
        riak_pool:execute(
            default,
            fun(_) -> throw(Reason) end,
            #{
                deadline => 8000,
                max_retries => 3,
                retry_backoff_interval_min => 2000,
                retry_backoff_interval_max => 3000,
                retry_backoff_type => normal
            }
        ),
        "If any pool or riak error occurs, execute will return an error tuple."
    ),

    connection_has_cleared().