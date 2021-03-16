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


-define(CONNECTION_KEY, connection).

-record(execute_state, {
    backoff                     ::  backoff:backoff() | undefined,
    deadline                    ::  pos_integer(),
    timeout                     ::  non_neg_integer(),
    max_retries                 ::  non_neg_integer(),
    retry_count = 0             ::  non_neg_integer(),
    opts                        ::  map(),
    poolname                    ::  atom() | undefined,
    connection                  ::  pid() | undefined,
    cleanup_on_exit = false     ::  boolean()
}).

-type config()    ::  #{
    backend => module(),
    riak_host => string(),
    riak_port => integer(),
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
-export([get_connection/0]).
-export([has_connection/0]).
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
    ok = Mod:start(),
    maybe_add_pools().


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
%% @doc Executes a number of operations using the same Riak client connection
%% from pool `Poolname'.
%% The connection will be passed to the function object `Fun' and also
%% temporarily stored in the process dictionary for the duration of the call
%% and it is accessible via the {@link get_connection/0} function.
%%
%% The function returns:
%% * `{ok, Result}' when a connection was succesfully checked out from the
%% pool `Poolname'. `Result' is is the value of the last expression in
%% `Fun'.
%% * `{error, Reason}' when the a connection could not be obtained from the
%% pool `Poolname'. `Reason' is `busy' when the pool runout of connections or `
%% {error, Reason}' when it was a Riak connection error such as
%% `{error, timeout}/ or `{error, overload}'.
%%
%% In the case of an exception the function will catch it, checkin any checked
%% out connection and cleanup the state and finally raise the exception.
%% -----------------------------------------------------------------------------
-spec execute(
    Poolname :: atom(),
    Fun :: fun((RiakConn :: pid()) -> Result :: any()),
    Opts :: map()) ->
    {ok, Result :: any()} | {error, Reason :: any()} | no_return().

execute(Poolname, Fun, Opts)  ->
    do_execute(Fun, execute_state(Opts#{poolname => Poolname})).


%% -----------------------------------------------------------------------------
%% @doc Returns a Riak connection from the process
%% dictonary or `undefined' if there is none.
%% @end
%% -----------------------------------------------------------------------------
-spec get_connection() -> undefined | pid().

get_connection() ->
    get(?CONNECTION_KEY).



%% -----------------------------------------------------------------------------
%% @doc Returns `true' if there is a Riak connection stored in the process
%% dictionary or `false' otherwise.
%% @end
%% -----------------------------------------------------------------------------
-spec has_connection() -> boolean().

has_connection() ->
    get(?CONNECTION_KEY) =/= undefined.



%% =============================================================================
%% PRIVATE
%% =============================================================================


execute_state(Opts) ->
    Poolname = maps:get(poolname, Opts, undefined),
    Conn = maps:get(connection, Opts, undefined),
    Timeout = maps:get(timeout, Opts, 5000),
    MaxRetries = maps:get(max_retries, Opts, 0),

    %% Validation
    (
        is_integer(MaxRetries) andalso MaxRetries >= 0
        andalso is_integer(Timeout) andalso Timeout > 0
    ) orelse error({badarg, Opts}),



    State = #execute_state{
        timeout = Timeout,
        max_retries = MaxRetries,
        connection = Conn,
        poolname = Poolname,
        opts = Opts
    },

    case MaxRetries > 0 of
        true ->
            Deadline0 = maps:get(deadline, Opts, 60000),
            Min = maps:get(retry_backoff_interval_min, Opts, 1000),
            Max = maps:get(retry_backoff_interval_max, Opts, 15000),
            Type = maps:get(retry_backoff_type, Opts, jitter),

            %% Validation
            (
                is_integer(Deadline0) andalso Deadline0 > Timeout
                andalso is_integer(Min) andalso Min > 0
                andalso is_integer(Max) andalso Max > Min
                andalso (Type == jitter orelse Type == normal)
            ) orelse error({badarg, Opts}),

            %% Bound deadline
            Deadline = deadline(Deadline0, Timeout, MaxRetries),
            Backoff = backoff:type(backoff:init(Min, Max), Type),

            State#execute_state{
                deadline = Deadline,
                backoff = Backoff
            };
        false ->
            %% Retries is disabled
            State
    end.


%% @private
do_execute(Fun, State)  ->
    case maybe_checkout(State) of
        {ok, Pid, NewState} ->
            try
                {ok, Fun(Pid)}
            catch
                _:timeout ->
                    ok = maybe_checkin(timeout, NewState),
                    maybe_retry(Fun, NewState, {error, timeout});
                _:overload ->
                    ok = maybe_checkin(overload, NewState),
                    {error, overload};
                Class:Reason:Stacktrace ->
                    ok = maybe_checkin(fail, NewState),
                    erlang:raise(Class, Reason, Stacktrace)
            after
                ok = maybe_checkin(ok, NewState),
                cleanup(NewState)
            end;
        {error, busy, NewState} ->
            maybe_retry(Fun, NewState, {error, busy});
        {error, Reason, _NewState} ->
            {error, Reason}
    end.


%% -----------------------------------------------------------------------------
%% @private
%% @doc Only checkout if the user has not provided a connection. Also only
%% checkin on exit when a checkout was made.
%% @end
%% -----------------------------------------------------------------------------
maybe_checkout(#execute_state{connection = undefined} = State) ->
    %% If user has not provided a connection try to reuse an existing
    %% connection checkout by this process already if any, and only then
    %% checkout a connection
    case get_connection() of
        undefined ->
            Poolname = State#execute_state.poolname,
            Opts = State#execute_state.opts,

            case checkout(Poolname, Opts) of
                {ok, Pid} ->
                    undefined = put(?CONNECTION_KEY, Pid),
                    NewState = State#execute_state{
                        connection = Pid,
                        cleanup_on_exit = true
                    },
                    {ok, Pid, NewState};
                {error, Reason} ->
                    {error, Reason, State}
            end;
        Pid when is_pid(Pid) ->
            NewState = State#execute_state{
                connection = Pid,
                cleanup_on_exit = false
            },
            {ok, Pid, NewState}
    end;

maybe_checkout(#execute_state{connection = Pid} = State) ->
    {ok, Pid, State}.


%% @private
maybe_checkin(Reason, #execute_state{cleanup_on_exit = true} = S) ->
    checkin(S#execute_state.poolname, S#execute_state.connection, Reason);

maybe_checkin(_, _) ->
    ok.


%% @private
maybe_retry(_, #execute_state{backoff = undefined}, Result) ->
    %% Retry disabled
    Result;

maybe_retry(_, #execute_state{max_retries = N, retry_count = M}, Result)
when N < M ->
    %% We reached the max retry limit
    Result;

maybe_retry(Fun, State0, Result) ->
    Now = erlang:system_time(millisecond),
    Deadline = State0#execute_state.deadline,

    case Deadline =< Now of
        true ->
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
            ok = timer:sleep(Delay),
            do_execute(Fun, State1)
    end.


%% -----------------------------------------------------------------------------
%% @private
%% @doc
%% @end
%% -----------------------------------------------------------------------------
cleanup(#execute_state{cleanup_on_exit = true}) ->
    %% We cleanup the process dictionary
    _ = erase(?CONNECTION_KEY),
    ok;

cleanup(_) ->
    ok.


%% @private
deadline(_, _, 0) ->
    0;

deadline(Deadline, Timeout, _) when Deadline > Timeout ->
    erlang:system_time(millisecond) + Deadline;

deadline(_, Timeout, Retries) ->
    erlang:system_time(millisecond) + Timeout * Retries.


%% @private
maybe_add_pools() ->
    case riak_pool_config:get(pools, undefined) of
        undefined ->
            ok;
        Pools when is_list(Pools) ->
            ok = lists:foreach(
                fun
                    (#{name := Name} = Pool) ->
                        Config = maps:without([name], Pool),
                        case riak_pool:add_pool(default, Config) of
                            ok ->
                                ?LOG_INFO(#{
                                    message => "Riak KV connection pool configured",
                                    poolname => Name,
                                    config => Pool
                                }),
                                ok;
                            {error, Reason} ->
                                throw(Reason)
                        end;
                    (Pool) ->
                        throw({missing_poolname, Pool})
                end,
                Pools
            )
    end.