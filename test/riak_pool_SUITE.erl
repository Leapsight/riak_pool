-module(riak_pool_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0]).

-compile([nowarn_export_all, export_all]).



all() ->
    [
        execute_with_user_connection,
        execute_reuses_parent_connection
    ].


init_per_suite(Config) ->
    meck:unload(),
    _ = application:ensure_all_started(riak_pool),
    Config.

end_per_suite(Config) ->
    meck:unload(),
    {save_config, Config}.


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
        {true, true},
        riak_pool:execute(
            does_not_exist,
            fun(Pid) -> Pid =:= Conn end,
            #{connection => Conn}
        ),
        "The user-provided connection takes precedence."
    ),

    ?assertEqual(
        {true, ok},
        riak_pool:execute(
            default,
            fun(_) ->
                {true, true} = riak_pool:execute(
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
        {true, ok},
        riak_pool:execute(
            default,
            fun(Pid1) ->
                {true, true} = riak_pool:execute(
                    default,
                    fun(Pid2) -> Pid1 =:= Pid2 end,
                    #{}
                ),
                ok
            end,
            #{}
        )
    ),
    ?assertEqual(
        undefined,
        riak_pool:get_connection(),
        "The connection was cleared from the process dictionary"
    ).



