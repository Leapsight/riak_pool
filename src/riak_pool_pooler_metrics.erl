-module(riak_pool_pooler_metrics).

-export([setup/0]).
-export([update_or_create/4]).


%% =============================================================================
%% API
%% =============================================================================


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
setup() ->
    do_setup_metrics().


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
update_or_create([<<"pooler">>, Poolname, Name], {inc, Value}, counter, []) ->
    prometheus_counter:inc(name(Name), [Poolname, riak_pool_pooler], Value);

update_or_create([<<"pooler">>, Poolname, Name], Value, meter, []) ->
    prometheus_counter:inc(name(Name), [Poolname, riak_pool_pooler], Value);

update_or_create([<<"pooler">>, Poolname, Name], Value, histogram, []) ->
    prometheus_histogram:observe(
        name(Name), [Poolname, riak_pool_pooler], Value
    );

update_or_create(_, _, _, _) ->
    %% We ignore others
    ok.



%% =============================================================================
%% PRIVATE
%% =============================================================================


name(Suffix) ->
    <<"riak_pool_", Suffix/binary>>.


do_setup_metrics() ->
    prometheus_counter:declare([
        {name, <<"riak_pool_take_rate">>},
        {help,
            <<"TBD">>
        },
        {labels, [poolname, mod]}
    ]),
    prometheus_counter:declare([
        {name, <<"riak_pool_starting_member_timeout">>},
        {help,
            <<"TBD">>
        },
        {labels, [poolname, mod]}
    ]),
    prometheus_counter:declare([
        {name, <<"riak_pool_error_no_members_count">>},
        {help,
            <<"TBD">>
        },
        {labels, [poolname, mod]}
    ]),
    prometheus_counter:declare([
        {name, <<"riak_pool_queue_max_reached">>},
        {help,
            <<"TBD">>
        },
        {labels, [poolname, mod]}
    ]),
    prometheus_counter:declare([
        {name, <<"riak_pool_killed_free_count">>},
        {help,
            <<"TBD">>
        },
        {labels, [poolname, mod]}
    ]),
    prometheus_histogram:declare([
        {name, <<"riak_pool_in_use_count">>},
        {help,
            <<"TBD">>
        },
        {labels, [poolname, mod]}
    ]),
    prometheus_histogram:declare([
        {name, <<"riak_pool_free_count">>},
        {help,
            <<"TBD">>
        },
        {labels, [poolname, mod]}
    ]),
    prometheus_histogram:declare([
        {name, <<"riak_pool_queue_count">>},
        {help,
            <<"TBD">>
        },
        {labels, [poolname, mod]}
    ]),


    ok.

