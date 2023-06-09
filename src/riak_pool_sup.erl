%% =============================================================================
%%  riak_pool_sup.erl -
%%
%%  Copyright (c) 2020 Leapsight Holdings Limited. All rights reserved.
%%
%%  Licensed under the Apache License, Version 2.0 (the "License");
%%  you may not use this file except in compliance with the License.
%%  You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%%  Unless required by applicable law or agreed to in writing, software
%%  distributed under the License is distributed on an "AS IS" BASIS,
%%  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%  See the License for the specific language governing permissions and
%%  limitations under the License.
%% =============================================================================

%%%-------------------------------------------------------------------
%% @doc riak_pool top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(riak_pool_sup).
-behaviour(supervisor).


-export([start_link/0]).
-export([init/1]).




%% =============================================================================
%% API
%% =============================================================================



start_link() ->
    ok = riak_pool_config:init(),
    ok = riak_pool:start(),
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).



%% =============================================================================
%% SUPERVISOR CALLBACKS
%% =============================================================================



init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 0,
        period => 1
    },
    ChildSpecs = [],

    {ok, {SupFlags, ChildSpecs}}.

