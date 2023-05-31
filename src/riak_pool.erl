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
    event_name                  ::  telemetry:event_name() | undefined,
    event_metadata              ::  telemetry:event_metadata(),
    system_time                 ::  integer(),
    start_time                  ::  integer(),
    cleanup_on_exit = false     ::  boolean()
}).

-record(riak_pool_result, {
    value                       ::  any(),
    metadata                    ::  telemetry:event_metadata()
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

-type exec_opts()    ::  #{
    connection => pid(),
    telemetry => #{
        event_name => telemetry:event_name(),
        event_metadata => telemetry:event_metadata()
    },
    deadline => pos_integer(),
    timeout => pos_integer(),
    max_retries => non_neg_integer(),
    retry_backoff_interval_min => non_neg_integer(),
    retry_backoff_interval_max => non_neg_integer(),
    retry_backoff_type => jitter | normal
}.

-type exec_fun()            ::  fun((Connection :: pid()) ->
                                Result :: any())
                                | result_with_meta().

-opaque result_with_meta() ::   #riak_pool_result{}.


-export_type([config/0]).
-export_type([exec_opts/0]).
-export_type([exec_fun/0]).

-export([add_pool/2]).
-export([checkin/2]).
-export([checkin/3]).
-export([checkout/1]).
-export([checkout/2]).
-export([execute/2]).
-export([execute/3]).
-export([get_connection/0]).
-export([has_connection/0]).
-export([remove_pool/1]).
-export([result/2]).
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

-callback checkout(
    Poolname :: atom(), Opts :: #{timeout => non_neg_integer()}) ->
    {ok, pid()}
    | {error,  busy | down | invalid_poolname | any()}
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
-spec checkout(Poolname :: atom(), Opts :: #{timeout => non_neg_integer()}) ->
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
%% @doc Calls {@link execute/3} passing an empty options map.
%% @end
%% -----------------------------------------------------------------------------
-spec execute(Poolname :: atom(), Fun :: exec_fun()) ->
    {ok, Result :: any()} | {error, Reason :: any()} | no_return().

execute(Poolname, Fun) ->
    execute(Poolname, Fun, #{}).


%% -----------------------------------------------------------------------------
%% @doc Executes a number of operations using the same Riak client connection
%% from pool `Poolname'.
%% The connection will be passed to the function object `Fun' and also
%% temporarily stored in the process dictionary for the duration of the call
%% and it is accessible via the {@link get_connection/0} function.
%%
%% In case `Opts' has a `connection' key containing a pid(), this will be used
%% instead. In this case the poolname might be `undefined' but no retries will
%% be possible in case the passed connection is no longer healthy.
%%
%% The function returns:
%%
%% <ul>
%% <li>`{ok, Result}' when a connection was succesfully checked out from the
%% pool `Poolname'. `Result' is is the value of the last expression in
%% `Fun'.</li>
%% <li>`{error, Reason}' when the a connection could not be obtained from the
%% pool `Poolname'. `Reason' is `busy' when the pool run out of connections or `
%% {error, Reason}' when it was a Riak connection error such as
%% `{error, Reason}' where `Reason' might be `timeout', `disconnected' or
%% `overload'.</li>
%% <ul>
%%
%% In the case of failure if the exception reason is `timeout' or
%% `disconnected' and `Opts' defined a retry strategy,
%% a new connection will be obtained from the pool to retry the operation. If
%% the exception reason is `overload' the function will return
%% `{error, overload}'. Otherwise, the exception will be raised using the
%% original class and reason while preserving the stacktrace.
%%
%% In all failure cases (whether a retry strategy was defined or not) all failed
%% connections and newly checked out connections will be checked in and the
%% process dictionary cleaned up before returning. This function supports
%% nested calls, so it will not clean up a connection that was already in the
%% process dictionary at the beginning of the call or has been passed using the
%% option `connection' in `Opts'.
%%
%% == Telemetry ==
%% This function will emmit start and stop/exception events. This works
%% similarly to {@link telemetry:span/3} with the difference that this function
%% provides additional measurements such as the number of retries performed.
%%
%% If the function `Fun' returns a `result_with_meta()' object (constructed
%% using {@link result/2}, then the stop event will be emmitted using the
%% metadata provided merged with the default metadata provided by this
%% function.)
%% -----------------------------------------------------------------------------
-spec execute(Poolname :: atom(), Fun :: exec_fun(), Opts :: exec_opts()) ->
    {ok, Result :: any()} | {error, Reason :: any()} | no_return().

execute(Poolname, Fun, Opts) when is_function(Fun, 1) ->
    do_execute(Fun, init_execute_state(Poolname, Opts)).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec result(Value :: any(), Meta :: telemetry:event_metadata()) ->
    result_with_meta().

result(Value, Meta) when is_map(Meta) ->
    #riak_pool_result{
        value = Value,
        metadata = Meta
    }.



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


%% @private
-spec init_execute_state(atom(), exec_opts()) -> #execute_state{}.

init_execute_state(Poolname, #{connection := Pid} = Opts) when is_pid(Pid) ->
    case is_process_alive(Pid) of
        true ->
            init_execute_state(Poolname, Opts, Pid);
        false ->
            init_execute_state(undefined, maps:without(connection, Opts))
    end;

init_execute_state(Poolname, Opts) when is_map(Opts) ->
    init_execute_state(Poolname, Opts, get_connection()).


%% @private
-spec init_execute_state(atom(), exec_opts(), pid() | undefined) ->
    #execute_state{}.

init_execute_state(Poolname, Opts, Connection) ->
    Timeout = maps:get(timeout, Opts, 5000),
    MaxRetries = maps:get(max_retries, Opts, 0),
    CtxtMaker = fun() -> erlang:make_ref() end,

    %% Validation
    (
        is_integer(MaxRetries) andalso MaxRetries >= 0
        andalso is_integer(Timeout) andalso Timeout > 0
    ) orelse error({badarg, Opts}),


    {EventName, EventMetadata} =
        case maps:find(telemetry, Opts) of
            {ok, #{event_name := Name, event_metadata := Meta}} ->
                {Name, merge_ctx(Meta, CtxtMaker)};

            {ok, #{event_name := Name}} ->
                {Name, merge_ctx(#{}, CtxtMaker)};

            _ ->
                %% {ok, #{}} or error
                Name = [riak_pool, execute],
                Meta = merge_ctx(#{}, CtxtMaker),
                {Name, Meta}
        end,


    State = #execute_state{
        timeout = Timeout,
        max_retries = MaxRetries,
        connection = Connection,
        poolname = Poolname,
        event_name = EventName,
        event_metadata = EventMetadata,
        system_time = erlang:system_time(),
        start_time = erlang:monotonic_time(),
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
do_execute(Fun, State0)  ->
    case maybe_checkout(State0) of
        {ok, Pid, State1} ->
            try
                {ok, execute_apply(Fun, Pid, State1)}
            catch
                _:overload ->
                    %% Transient failure but we shouldn't retry. Let the user
                    %% handle the situation
                    _ = maybe_checkin(overload, State1),
                    {error, overload};

                _:Reason when Reason == timeout orelse Reason == disconnected ->
                    %% Transient failure, we will retry (if enabled)
                    State = maybe_checkin(Reason, State1),
                    maybe_retry(Fun, State, {error, Reason});

                Class:Reason:Stacktrace ->
                    _ = maybe_checkin(fail, State1),
                    erlang:raise(Class, Reason, Stacktrace)

            after
                FinalState = maybe_checkin(ok, State1),
                cleanup(FinalState)
            end;

        {error, busy, State} ->
            maybe_retry(Fun, State, {error, busy});

        {error, down, State} ->
            maybe_retry(Fun, State, {error, down});

        {error, Reason, _} ->
            {error, Reason}
    end.


%% -----------------------------------------------------------------------------
%% @private
%% @doc A separate function to improve testing
%% @end
%% -----------------------------------------------------------------------------
execute_apply(Fun, Pid, #execute_state{event_name = undefined}) ->
    Fun(Pid);

execute_apply(Fun, Pid, #execute_state{} = State) ->
    %% We do not use telemetry:span/3 as we want to add additional measurements
    %% to the event e.g. retries
    %% Send start event
    telemetry:execute(
        State#execute_state.event_name ++ [start],
        #{
            monotonic_time => State#execute_state.start_time,
            system_time => State#execute_state.system_time
        },
        State#execute_state.event_metadata
    ),

    try Fun(Pid) of
        #riak_pool_result{value = Val, metadata = StopMeta0} ->
            execute_stop(Val, StopMeta0, State);

        Val ->
            execute_stop(Val, #{}, State)

    catch
        Class:Reason:Stacktrace ->
            execute_exception(Class, Reason, Stacktrace, State)
    end.


%% -----------------------------------------------------------------------------
%% @private
%% @doc
%% @end
%% -----------------------------------------------------------------------------
execute_stop(Result, StopMeta0, #execute_state{} = State) ->
    StopTime = erlang:monotonic_time(),
    DefaultCtxt = maps:get(
        telemetry_span_context, State#execute_state.event_metadata
    ),

    StopMeta1 = merge_ctx(StopMeta0, DefaultCtxt),
    StopMeta = merge_meta(StopMeta1, State),

    telemetry:execute(
        State#execute_state.event_name ++ [stop],
        #{
            retries => State#execute_state.retry_count,
            duration => StopTime - State#execute_state.start_time,
            monotonic_time => StopTime
        },
        StopMeta
    ),
    Result.


%% -----------------------------------------------------------------------------
%% @private
%% @doc
%% @end
%% -----------------------------------------------------------------------------
execute_exception(Class, Reason, Stacktrace, State) ->
    StopTime = erlang:monotonic_time(),
    DefaultCtxt = maps:get(
        telemetry_span_context, State#execute_state.event_metadata
    ),

    StopMeta0 = #{
        kind => Class,
        reason => Reason,
        stacktrace => Stacktrace
    },
    StopMeta1 = merge_ctx(StopMeta0, DefaultCtxt),
    StopMeta = merge_meta(StopMeta1, State),

    telemetry:execute(
        State#execute_state.event_name ++ [exception],
        #{
            retries => State#execute_state.retry_count,
            duration => StopTime - State#execute_state.start_time,
            monotonic_time => StopTime
        },
        StopMeta
    ),
    erlang:raise(Class, Reason, Stacktrace).


%% -----------------------------------------------------------------------------
%% @private
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec merge_ctx(telemetry:event_metadata(), fun(() -> any()) | any()) ->
    telemetry:event_metadata().

merge_ctx(#{telemetry_span_context := _} = Metadata, _) ->
    Metadata;

merge_ctx(Metadata, MakeCtxt) when is_function(MakeCtxt, 0) ->
    maps:put(telemetry_span_context, MakeCtxt(), Metadata);

merge_ctx(Metadata, Ctxt) ->
    maps:put(telemetry_span_context, Ctxt, Metadata).


%% -----------------------------------------------------------------------------
%% @private
%% @doc
%% @end
%% -----------------------------------------------------------------------------
merge_meta(Metadata, State) ->
    Metadata#{
        poolname => State#execute_state.poolname,
        deadline => State#execute_state.deadline,
        max_retries => State#execute_state.max_retries
    }.

%% -----------------------------------------------------------------------------
%% @private
%% @doc Only checkout if the user has not provided a connection. Also only
%% checkin on exit when a checkout was made.
%% @end
%% -----------------------------------------------------------------------------
maybe_checkout(#execute_state{connection = undefined} = State) ->
    Poolname = State#execute_state.poolname,
    Opts = State#execute_state.opts,

    case checkout(Poolname, Opts) of
        {ok, Pid} ->
            _ = put(?CONNECTION_KEY, Pid),
            NewState = State#execute_state{
                connection = Pid,
                cleanup_on_exit = true
            },
            {ok, Pid, NewState};
        {error, Reason} ->
            {error, Reason, State}
    end;

maybe_checkout(#execute_state{connection = Pid} = State) ->
    {ok, Pid, State}.


%% @private
maybe_checkin(ok, #execute_state{cleanup_on_exit = true} = S) ->
    ok = checkin(S#execute_state.poolname, S#execute_state.connection, ok),
    S#execute_state{connection = undefined};

maybe_checkin(ok, #execute_state{cleanup_on_exit = false} = S) ->
    S#execute_state{connection = undefined};

maybe_checkin(timeout, #execute_state{} = S) ->
    %% If we retry we reuse the same connection
    S;

maybe_checkin(Reason, #execute_state{cleanup_on_exit = true} = S) ->
    %% Failed for other reason e.g. disconnect, so we remove the connection so
    %% that if we retry we checckout another one.
    ok = checkin(S#execute_state.poolname, S#execute_state.connection, Reason),
    S#execute_state{connection = undefined};

maybe_checkin(_, S) ->
    S#execute_state{connection = undefined}.



%% @private
maybe_retry(_, #execute_state{backoff = undefined}, Result) ->
    %% Retry disabled
    Result;

maybe_retry(_, #execute_state{max_retries = N, retry_count = M}, Result)
when N < M ->
    %% We reached the max retry limit
    Result;

maybe_retry(Fun, State0, {error, Reason} = Result) ->
    Now = erlang:system_time(millisecond),
    Deadline = State0#execute_state.deadline,

    case Deadline =< Now of
        true ->
            Result;
        false ->
            %% We will retry
            {Delay, B1} = backoff:fail(State0#execute_state.backoff),
            N = State0#execute_state.retry_count + 1,
            State1 = State0#execute_state{backoff = B1, retry_count = N},

            State =
                case Reason of
                    disconnected ->
                        State1#execute_state{connection = undefined};
                    _ ->
                        State1
                end,

            ?LOG_INFO(#{
                message => "Will retry riak_pool:execute/3",
                retry_count => N,
                delay => Delay
            }),
            ok = timer:sleep(Delay),
            do_execute(Fun, State)
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
                                    message =>
                                        "Riak KV connection pool configured",
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