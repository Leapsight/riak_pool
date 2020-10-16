%%%-------------------------------------------------------------------
%% @doc riak_pool public API
%% @end
%%%-------------------------------------------------------------------

-module(riak_pool_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    riak_pool_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
