-module(riak_pool_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0]).

-compile([nowarn_export_all, export_all]).



all() ->
    [
        execute_no_connection,
        execute_with_user_connection,
        execute_reuses_parent_connection,
        execute_errors,
        execute_exceptions
    ].


init_per_suite(Config) ->
    meck:unload(),
    _ = application:ensure_all_started(riak_pool),
    Config.

end_per_suite(Config) ->
    meck:unload(),
    {save_config, Config}.


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

    ?assertExit(
        {noproc, {gen_server, call, [does_not_exist, _, _]}},
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
            fun(_) -> error(timeout) end,
            #{}
        ),
        "If any pool or riak error occurs, execute will return an error tuple."
    ),
    connection_has_cleared(),

    ?assertEqual(
        {error, overload},
        riak_pool:execute(
            default,
            fun(_) -> error(overload) end,
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



connection_has_cleared() ->
    ?assertEqual(
        undefined,
        riak_pool:get_connection(),
        "The connection was cleared from the process dictionary"
    ).