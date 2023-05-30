-module(riak_pool_pooler_metrics).

-export([setup/0]).

%% Exometer API
-export([update_or_create/4]).


%% =============================================================================
%% API
%% =============================================================================


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
setup() ->
    ok.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
update_or_create(
    [<<"pooler">>, Pool, <<"in_use_count">>], Val, histogram, []) ->
    telemetry:execute(
        [riak_pool, pool, busy],
        #{count => Val},
        #{poolname => Pool}
    );

update_or_create(
    [<<"pooler">>, Pool, <<"free_count">>], Val, histogram, []) ->
    telemetry:execute(
        [riak_pool, pool, idle],
        #{count => Val},
        #{poolname => Pool}
    );

update_or_create(
    [<<"pooler">>, Pool, <<"error_no_members">>], Val, counter, []) ->
    telemetry:execute(
        [riak_pool, pool, no_members],
        #{count => Val},
        #{poolname => Pool}
    );

update_or_create(_, _, _, _) ->
    %% We ignore others
    ok.

