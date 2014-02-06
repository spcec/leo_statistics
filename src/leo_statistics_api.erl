%%======================================================================
%%
%% Leo Statistics
%%
%% Copyright (c) 2012-2014 Rakuten, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% ---------------------------------------------------------------------
%% Leo Statistics - API.
%% @doc
%% @end
%%======================================================================
-module(leo_statistics_api).

-author('Yosuke Hara').

-include_lib("eunit/include/eunit.hrl").

-export([start_link/1, start_link/2,
         new_counter/1, inc_counter/2, dec_counter/2, clear_counter/1,
         get/1, notify/2,
         new_histogram/2, get_histogram/1, get_histogram/2,
         new_history/1, get_history/2, sum/2, clear_history/1
        ]).

-define(env_snmp_agent(Server),
        case application:get_env(Server, snmp_agent) of
            {ok, _SNMPAgent} -> _SNMPAgent;
            _ -> []
        end).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
%% @doc Start SNMP server
%%
-spec(start_link(atom()) ->
             ok | {error, any()}).
start_link(Application) ->
    case ?env_snmp_agent(Application) of
        [] ->
            ok;
        SNMPAgent ->
            application:start(leo_statistics),
            application:start(snmp),

            case catch snmpa:load_mibs(snmp_master_agent, [SNMPAgent]) of
                ok ->
                    %% folsom
                    ChildSpec1 = {folsom,
                                  {folsom_sup, start_link, []},
                                  permanent, 2000, supervisor, [folsom]},
                    {ok, _} = supervisor:start_child(leo_statistics_sup, ChildSpec1),

                    %% request-counter
                    ChildSpec2 = {leo_statistics_req_counter,
                                  {leo_statistics_req_counter, start_link, []},
                                  permanent, 2000, worker, [leo_statistics_req_counter]},
                    {ok, _} = supervisor:start_child(leo_statistics_sup, ChildSpec2),
                    ok;
                Error ->
                    Error
            end
    end.

-spec(start_link(atom(), integer()) ->
             ok | {error, any()}).
start_link(Module, Interval) ->
    PropListOfCounts = supervisor:count_children(leo_statistics_sup),
    Specs = leo_misc:get_value('specs', PropListOfCounts),

    Id = list_to_atom(lists:append(["leo_statistics_", integer_to_list(Specs)])),
    ChildSpec = {Id,
                 {leo_statistics_server, start_link, [Id, Module, Interval]},
                 permanent, 2000, worker, [leo_statistics_server]},
    {ok, _} = supervisor:start_child(leo_statistics_sup, ChildSpec),
    ok.

%%--------------------------------------------------------------------
%% Counter.
%%--------------------------------------------------------------------
%% @doc Create counter.
%%
-spec(new_counter(atom()) ->
             ok).
new_counter(Name) ->
    ok = folsom_metrics:new_counter(Name).


%% @doc Increment counter.
%%
-spec(inc_counter(atom(), number()) ->
             ok).
inc_counter(Name, Value) ->
    folsom_metrics:notify({Name, {inc, Value}}).


%% @doc Decrement counter.
%%
-spec(dec_counter(atom(), number()) ->
             ok).
dec_counter(Name, Value) ->
    folsom_metrics:notify({Name, {dec, Value}}).


%% @doc Clear counter.
%%
-spec(clear_counter(atom()) ->
             ok).
clear_counter(Name) ->
    folsom_metrics_counter:clear(Name).


%%--------------------------------------------------------------------
%% Metrics - Commons
%%--------------------------------------------------------------------
%% @doc Retrieve metric value.
%%
-spec(get(atom()) ->
             integer() | {error, any()}).
get(Name) ->
    case catch folsom_metrics:get_metric_value(Name) of
        {'EXIT', Cause} ->
            {error, Cause};
        Stats ->
            Stats
    end.


%% @doc Notify metric value.
%%
-spec(notify(atom(), integer()) ->
             ok).
notify(Name, Value) ->
    case catch folsom_metrics:notify({Name,  Value}) of
        ok ->
            ok;
        {'EXIT', Cause} ->
            {error, Cause}
    end.


%%--------------------------------------------------------------------
%% Metrics - Histogram
%%--------------------------------------------------------------------
%% @doc Create a histogram-metric.
%%
-spec(new_histogram(atom(), integer()) ->
             ok | {error, any()}).
new_histogram(Name, SampleSize) ->
    case catch folsom_metrics:new_histogram(Name, uniform, SampleSize) of
        ok ->
            ok;
        {'EXIT', Cause} ->
            {error, Cause}
    end.


%% @doc Retrieve historgram-metric values.
%%
-spec(get_histogram(atom()) ->
             list() | {error, any()}).
get_histogram(Name) ->
    case folsom_metrics:get_histogram_statistics(Name) of
        {'EXIT', Cause} ->
            {error, Cause};
        Values ->
            Values
    end.

-spec(get_histogram(atom(), atom()) ->
             list() | {error, any()}).
get_histogram(Name, Property) ->
    case get_histogram(Name) of
        {error, _Cause} = Error ->
            Error;
        Values ->
            leo_misc:get_value(Property, Values)
    end.


%%--------------------------------------------------------------------
%% Metrics - History
%%--------------------------------------------------------------------
%% @doc Create a hitory-metric.
%%
-spec(new_history(atom()) ->
             ok | {error, any()}).
new_history(Name) ->
    case catch folsom_metrics:new_history(Name) of
        ok ->
            ok;
        {'EXIT', Cause} ->
            {error, Cause}
    end.


%% @doc Retrieve histories.
%%
-spec(get_history(atom(), integer()) ->
             list() | {error, any()}).
get_history(Name, Count) ->
    case catch folsom_metrics:get_history_values(Name, Count) of
        {'EXIT', Cause} ->
            {error, Cause};
        Values ->
            lists:map(fun({DateTime, [{_, V}]}) ->
                              {DateTime, V}
                      end, Values)
    end.


%% @doc
%%
-spec(sum(atom(), integer()) ->
             number()).
sum(Name, Count) ->
    case get_history(Name, Count) of
        Values when is_list(Values) andalso length(Values) == Count ->
            lists:foldl(fun({_, V}, Sum) ->
                                Sum + V
                        end, 0, Values);
        _Error ->
            -1
    end.


%% @doc Clear history.
%%
-spec(clear_history(atom()) ->
             ok | {error, any()}).
clear_history(Name) ->
    catch folsom_metrics:delete_metric(Name),
    new_history(Name).
