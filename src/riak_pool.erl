%% =============================================================================
%%  riak_pool.erl -
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
-module(riak_pool).

-include_lib("kernel/include/logger.hrl").



-record(execute_state, {
    backoff             ::  backoff:backoff() | undefined,
    deadline            ::  pos_integer(),
    timeout             ::  non_neg_integer(),
    max_retries         ::  non_neg_integer(),
    retry_count = 0     ::  non_neg_integer()
}).

-type config()    ::  #{
    min_size => pos_integer(),
    max_size => pos_integer(),
    idle_removal_interval_secs => non_neg_integer(),
    max_idle_secs => non_neg_integer()
}.

-type opts()    ::  #{
    deadline => pos_integer(),
    timeout => pos_integer(),
    max_retries => non_neg_integer(),
    retry_backoff_interval_min => non_neg_integer(),
    retry_backoff_interval_max => non_neg_integer(),
    retry_backoff_type => jitter | normal
}.

-export_type([config/0]).
-export_type([opts/0]).

-export([add_pool/2]).
-export([checkin/2]).
-export([checkin/3]).
-export([checkout/1]).
-export([checkout/2]).
-export([execute/3]).
-export([remove_pool/1]).
-export([start/0]).
-export([stop/0]).



%% =============================================================================
%% BEHAVIOUR
%% =============================================================================


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



%% =============================================================================
%% API
%% =============================================================================



%% -----------------------------------------------------------------------------
%% @doc Starts a pool
%% @end
%% -----------------------------------------------------------------------------
-spec start() -> ok.

start() ->
    Mod = riak_pool_config:get(backend_mod),
    Mod:start().


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec stop() -> ok.

stop() ->
    Mod = riak_pool_config:get(backend_mod),
    Mod:stop().


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec add_pool(Poolname :: atom(), Config :: config()) ->
    ok | {error, any()}.

add_pool(Poolname, #{backend_mod := Mod} = Config) ->
    Key = {?MODULE, Poolname},
    case persistent_term:get(Key, undefined) of
        undefined ->
            ok = persistent_term:put(Key, Config),
            Mod:add_pool(Poolname, Config);
        Existing ->
            {error, {already_exists, Existing}}
    end;

add_pool(Poolname, Config) ->
    Mod = riak_pool_config:get(backend_mod),
    add_pool(Poolname, Config#{backend_mod => Mod}).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec remove_pool(Poolname :: atom()) -> ok | {error, any()}.

remove_pool(Poolname) ->
    Key = {?MODULE, Poolname},
    case persistent_term:get(Key, undefined) of
        undefined ->
            ok;
        #{backend_mod := Mod} ->
            _ = persistent_term:erase(Key),
            Mod:remove_pool(Poolname)
    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec checkout(Poolname :: atom()) ->
    {ok, pid()} | {error, any()}.

checkout(Poolname) ->
    checkout(Poolname, #{}).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec checkout(Poolname :: atom(), Opts :: opts()) ->
    {ok, pid()} | {error, any()}.

checkout(Poolname, Opts) ->
    Mod = riak_pool_config:get(backend_mod),
    Mod:checkout(Poolname, Opts).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec checkin(Poolname :: atom(), Pid :: pid()) -> ok.

checkin(Poolname, Pid) ->
    Mod = riak_pool_config:get(backend_mod),
    Mod:checkin(Poolname, Pid, ok).



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec checkin(Poolname :: atom(), Pid :: pid(), Status :: atom()) ->
    ok.

checkin(Poolname, Pid, Status) ->
    Mod = riak_pool_config:get(backend_mod),
    Mod:checkin(Poolname, Pid, Status).


%% -----------------------------------------------------------------------------
%% @doc Executes a number of operations using the same Riak client connection.
%% @end
%% -----------------------------------------------------------------------------
-spec execute(
    Poolname :: atom(),
    Fun :: fun((RiakConn :: pid()) -> Result :: any()),
    Opts :: map()) ->
    {true, Result :: any()} | {false, Reason :: any()} | no_return().

execute(Poolname, Fun, Opts)  ->
    State = execute_state(Opts),
    execute(Poolname, Fun, Opts, State).






%% =============================================================================
%% PRIVATE
%% =============================================================================


execute_state(Opts) ->
    Timeout = maps:get(timeout, Opts, 2000),
    Deadline = maps:get(deadline, Opts, 60000),
    MaxRetries = maps:get(max_retries, Opts, 3),
    Min = maps:get(retry_backoff_interval_min, Opts, 1000),
    Max = maps:get(retry_backoff_interval_max, Opts, 15000),
    Type = maps:get(retry_backoff_type, Opts, jitter),

    %% Quick validation
    is_integer(Timeout) andalso Timeout > 0 andalso
    is_integer(Deadline) andalso Deadline > Timeout andalso
    is_integer(MaxRetries) andalso MaxRetries >= 0 andalso
    is_integer(Min) andalso Min > 0 andalso
    is_integer(Max) andalso Max > Min andalso
    (Type == jitter orelse Type == normal)
    orelse error({badarg, Opts}),

    State = #execute_state{
        deadline = erlang:system_time(millisecond) + Deadline,
        timeout = Timeout,
        max_retries = MaxRetries
    },

    case MaxRetries > 0 of
        true ->
            B = backoff:type(backoff:init(Min, Max), Type),
            State#execute_state{max_retries = MaxRetries, backoff = B};
        false ->
            State
    end.


%% @private
execute(Poolname, Fun, Opts, State)  ->
    case checkout(Poolname, Opts) of
        {ok, Pid} ->
            try
                Result = Fun(Pid),
                ok = checkin(Poolname, Pid, ok),
                {true, Result}
            catch
                _:EReason when EReason == timeout ->
                    ok = checkin(Poolname, Pid, EReason),
                    EResult = {true, {error, EReason}},
                    maybe_retry(Poolname, Fun, Opts, State, EResult);
                _:EReason when EReason == overload ->
                    ok = checkin(Poolname, Pid, EReason),
                    {true, {error, EReason}};
                _:EReason:Stacktrace ->
                    ok = checkin(Poolname, Pid, fail),
                    error(EReason, Stacktrace)
            end;
        {error, busy} ->
            Result = {false, busy},
            maybe_retry(Poolname, Fun, Opts, State, Result);
        {error, Reason} ->
            {false, Reason}
    end.


%% @private
maybe_retry(_, _, _, #execute_state{backoff = undefined}, Result) ->
    %% Retry disabled
    Result;

maybe_retry(_, _, _, #execute_state{max_retries = N, retry_count = M}, Result)
when N < M ->
    %% We reached the max retry limit
    Result;

maybe_retry(Poolname, Fun, Opts, State0, Result) ->
    Now = erlang:system_time(millisecond),
    Deadline = State0#execute_state.deadline,

    case Deadline =< Now of
        true ->
            io:format("D ~p Now ~p~n", [Deadline, Now]),
            Result;
        false ->
            %% We will retry
            {Delay, B1} = backoff:fail(State0#execute_state.backoff),
            N = State0#execute_state.retry_count,
            State1 = State0#execute_state{backoff = B1, retry_count = N + 1},
            ?LOG_INFO(#{
                message => "Will retry riak pool execute",
                delay => Delay
            }),
             io:format("Will retry in ~p~n", [Delay]),
            ok = timer:sleep(Delay),
            execute(Poolname, Fun, Opts, State1)
    end.

