%%%-------------------------------------------------------------------
%%% File    : sqlite3_test.erl
%%% Author  : Tee Teoh <tteoh@teemac.ott.cti.com>
%%% Description :
%%%
%%% Created : 10 Jun 2008 by Tee Teoh <tteoh@teemac.ott.cti.com>
%%%-------------------------------------------------------------------
-module(sqlite3_test).

%% ====================================================================
%% API
%% ====================================================================
%% --------------------------------------------------------------------
%% Function: 
%% Description:
%% --------------------------------------------------------------------
-include_lib("eunit/include/eunit.hrl").

-define(FuncTest(Name), {??Name, fun Name/0}).
-define(WARN_ERROR_MESSAGE, io:format(user, "Error message should be shown...~n", [])).

drop_all_tables(Db) ->
    Tables = sqlite3:list_tables(Db),
    [sqlite3:drop_table(Db, Table) || Table <- Tables],
    Tables.

drop_table_if_exists(Db, Table) ->
    case lists:member(Table, sqlite3:list_tables(Db)) of
        true -> sqlite3:drop_table(Db, Table);
        false -> ok
    end.

rows(SqlExecReply) ->
    case SqlExecReply of
        [{columns, _Columns}, {rows, Rows}] -> Rows;
        {error, Code, Reason} -> {error, Code, Reason}
    end.

all_test_() ->
    {setup,
     fun open_db/0,
     fun close_db/1,
     [?FuncTest(basic_functionality),
      ?FuncTest(parametrized),
      ?FuncTest(negative),
      ?FuncTest(blob),
      ?FuncTest(escaping),
      ?FuncTest(select_many_records),
      ?FuncTest(nonexistent_table_info),
      ?FuncTest(large_number),
      ?FuncTest(unicode),
      ?FuncTest(acc_string_encoding),
      ?FuncTest(large_offset)]}.

open_db() ->
    sqlite3:open(ct, [in_memory]).

close_db({ok, _Pid}) ->
    sqlite3:close(ct);
close_db(_) ->
    ok.

basic_functionality() ->
    Columns = ["id", "name", "age", "wage"],
    AllRows = [{1, <<"abby">>, 20, 2000}, {2, <<"marge">>, 30, 2000}],
    AbbyOnly = [{1, <<"abby">>, 20, 2000}],
    TableInfo = [{id, integer, [{primary_key, [asc, autoincrement]}]}, 
                 {name, text, [not_null, unique]}, 
                 {age, integer, not_null}, 
                 {wage, integer}],
    TableInfo1 = lists:keyreplace(age, 1, TableInfo, {age, integer, [not_null]}),
    drop_all_tables(ct),
    ?WARN_ERROR_MESSAGE,
    ?assertEqual(
        {error, 21, "empty statement"},
        sqlite3:sql_exec(ct, "-- Comment")),
    ?assertEqual(
        [], 
        sqlite3:list_tables(ct)),
    ok = sqlite3:create_table(ct, user, TableInfo),
    ?assertEqual(
        [user, sqlite_sequence], 
        sqlite3:list_tables(ct)),
    ?assertEqual(
        TableInfo1, 
        sqlite3:table_info(ct, user)),
    ?assertEqual(
        {rowid, 1}, 
        sqlite3:write(ct, user, [{name, "abby"}, {age, 20}, {<<"wage">>, 2000}])),
    ?assertEqual(
        {rowid, 2}, 
        sqlite3:write(ct, user, [{name, "marge"}, {age, 30}, {wage, 2000}])),
    ?WARN_ERROR_MESSAGE,
    ?assertEqual(
        {error, 19, "constraint failed"}, 
        sqlite3:write(ct, user, [{name, "marge"}, {age, 30}, {wage, 2000}])),
    ?assertEqual(
        [{columns, Columns}, {rows, AllRows}], 
        sqlite3:sql_exec(ct, "select * from user;")),
    ?assertEqual(
        [{columns, Columns}, {rows, AllRows}], 
        sqlite3:read_all(ct, user)),
    ?assertEqual(
        [{columns, ["name"]}, {rows, [{<<"abby">>}, {<<"marge">>}]}], 
        sqlite3:read_all(ct, user, [name])),
    ?assertEqual(
        [{columns, Columns}, {rows, AbbyOnly}], 
        sqlite3:read(ct, user, {name, "abby"})),
    ?assertEqual(
        [{columns, Columns}, {rows, AllRows}], 
        sqlite3:read(ct, user, {wage, 2000})),
    ?assertEqual(
        ok, 
        sqlite3:delete(ct, user, {name, "marge"})),
    ?assertEqual(
        ok, 
        sqlite3:update(ct, user, {name, "abby"}, [{wage, 3000}])),
    ?assertEqual(
        [{columns, Columns}, {rows, [{1, <<"abby">>, 20, 3000}]}], 
        sqlite3:sql_exec(ct, "select * from user;")),
    ?assertEqual(
        ok, 
        sqlite3:drop_table(ct, user)).

parametrized() ->
    drop_table_if_exists(ct, user1),
    sqlite3:create_table(ct, user1, [{id, integer}, {name, text}]),
    sqlite3:sql_exec(ct, "INSERT INTO user1 (id, name) VALUES (?, ?)", [{1, 1}, {2, "john"}]),
    sqlite3:sql_exec(ct, "INSERT INTO user1 (id, name) VALUES (?3, ?5)", [{3, 2}, {5, "joe"}]),
    sqlite3:sql_exec(ct, "INSERT INTO user1 (id, name) VALUES (:id, @name)", [{":id", 3}, {'@name', <<"jack">>}]),
    sqlite3:sql_exec(ct, "INSERT INTO user1 (id, name) VALUES (?, ?)", [4, "james"]),
    ?WARN_ERROR_MESSAGE,
    ?assertMatch(
        {error, _, _},
        sqlite3:sql_exec(ct, "INSERT INTO user1 (id, name) VALUES (?, ?)", [4, bad_sql_value])),
    ?assertEqual(
        [{columns, ["id", "name"]}, 
         {rows, [{1, <<"john">>}, {2, <<"joe">>}, {3, <<"jack">>}, {4, <<"james">>}]}], 
        sqlite3:read_all(ct, user1)),
    sqlite3:drop_table(ct, user1),
    sqlite3:create_table(ct, user1, [{i, integer}, {d, double}, {b, blob}]),
    sqlite3:sql_exec(ct, "INSERT INTO user1 (i, d, b) VALUES (?, ?, ?)", 
        [null, 1.0, {blob, <<1,0,0>>}]),
    ?assertEqual(
        [{columns, ["i", "d", "b"]}, 
         {rows, [{null, 1.0, {blob, <<1,0,0>>}}]}],
        sqlite3:read_all(ct, user1)).

negative() ->
    drop_table_if_exists(ct, negative),
    sqlite3:create_table(ct, negative, [{id, int}]),
    ?assertEqual({error, badarg}, 
                 sqlite3:write(ct, negative, [{id, bad_sql_value}])).

blob() ->
    drop_table_if_exists(ct, blobs),
    sqlite3:create_table(ct, blobs, [{blob_col, blob}]),
    sqlite3:write(ct, blobs, [{blob_col, {blob, <<0,255,1,2>>}}]),
    ?assertEqual(
        [{columns, ["blob_col"]}, {rows, [{{blob, <<0,255,1,2>>}}]}], 
        sqlite3:read_all(ct, blobs)).

escaping() ->
    drop_table_if_exists(ct, escaping),
    sqlite3:create_table(ct, escaping, [{str, text}]),
    Strings = ["a'", "b\"c", "d''e", "f\"\""],
    Input = [[{str, String}] || String <- Strings],
    ExpectedRows = [{list_to_binary(String)} || String <- Strings],
    sqlite3:write_many(ct, escaping, Input),
    ?assertEqual(
        [{columns, ["str"]}, {rows, ExpectedRows}], 
        sqlite3:read_all(ct, escaping)).

select_many_records() ->
    N = 1024,
    drop_table_if_exists(ct, many_records),
    sqlite3:create_table(ct, many_records, [{id, integer}, {name, text}]),
    sqlite3:write_many(ct, many_records, [[{id, X}, {name, "bar"}] || X <- lists:seq(1, N)]),
    Columns = ["id", "name"],
    ?assertEqual(
        [{columns, Columns}, {rows, [{1, <<"bar">>}]}], 
        sqlite3:read(ct, many_records, {id, 1})),
    [?assertEqual(
         M, 
         length(rows(sqlite3:sql_exec(
             ct, io_lib:format("select * from many_records limit ~p;", [M])))))
     || M <- [10, 100, 1000]],
    ?assertEqual(
        N, 
        length(rows(sqlite3:sql_exec(ct, "select * from many_records;")))).

%% note that inserts are actually serialized by gen_server
concurrent_inserts_test() ->
    N = 1024,
    sqlite3:open(concurrent, [in_memory]), %% doing this test not in memory is much slower!
    drop_table_if_exists(concurrent, t),
    sqlite3:create_table(concurrent, t, [{id0, integer}]),
    Self = self(),
    [spawn(fun () ->
               sqlite3:write(concurrent, t, [{id0, X}]),
               Self ! {finished, N}
           end) || X <- lists:seq(1, N)],
    loop_concurrent_inserts(N),
    ?assertEqual(
        N, length(rows(sqlite3:read_all(concurrent, t)))),
    sqlite3:close(concurrent).

loop_concurrent_inserts(0) ->
    ok;
loop_concurrent_inserts(N) ->
    receive
        {finished, _} ->
            loop_concurrent_inserts(N - 1)
    end.

nonexistent_table_info() ->
    ?assertEqual(table_does_not_exist, sqlite3:table_info(ct, nonexistent)).

large_number() ->
    N1 = 9223372036854775807,
    N2 = -9223372036854775808,
    Query1 = io_lib:format("select ~p, ~p", [N1, N2]),
    ?assertEqual([{N1, N2}], rows(sqlite3:sql_exec(ct, Query1))),
    Query2 = "select ?, ?",
    ?assertEqual([{N1, N2}], rows(sqlite3:sql_exec(ct, Query2, [N1, N2]))),
    ?assertNot([{N1 + 1, N2 - 1}] == rows(sqlite3:sql_exec(ct, Query2, [N1 + 1, N2 - 1]))).

unicode() ->
    UnicodeString = [1102,1085,1080,1082,1086,1076], %% "Unicode" in Russian, in UTF-8
    drop_table_if_exists(ct, unicode),
    sqlite3:create_table(ct, unicode, [{str, text}]),
    sqlite3:write(ct, unicode, [{str, UnicodeString}]),
    ?assertEqual([{unicode:characters_to_binary(UnicodeString)}], rows(sqlite3:read_all(ct, unicode))). 

acc_string_encoding() ->
    ?assertEqual([{62}], rows(sqlite3:sql_exec(ct, "SELECT ? + ?", [30,32]))).

prepared_test() ->
    Columns = ["id", "name", "age", "wage"],
    Abby = {1, <<"abby">>, 20, 2000},
    Marge = {2, <<"marge">>, 30, 2000},
    TableInfo = [{id, integer, [primary_key]}, {name, text, [unique]}, {age, integer}, {wage, integer}],
    sqlite3:open(prepared, [in_memory]),
    ok = sqlite3:create_table(prepared, user, TableInfo),
    sqlite3:write(prepared, user, [{name, "abby"}, {age, 20}, {wage, 2000}]),
    sqlite3:write(prepared, user, [{name, "marge"}, {age, 30}, {wage, 2000}]),
    {ok, Ref1} = sqlite3:prepare(prepared, "SELECT * FROM user"),
    {ok, Ref2} = sqlite3:prepare(prepared, "SELECT * FROM user WHERE name = ?"),
    ?assertMatch({error, _}, sqlite3:next(prepared, make_ref())),
    ?assertEqual(Columns, sqlite3:columns(prepared, Ref1)),
    ?assertEqual(Abby, sqlite3:next(prepared, Ref1)),
    ?assertEqual(ok, sqlite3:reset(prepared, Ref1)),
    ?assertEqual(Abby, sqlite3:next(prepared, Ref1)),
    ?assertEqual(Marge, sqlite3:next(prepared, Ref1)),
    ?assertEqual(done, sqlite3:next(prepared, Ref1)),
    ?assertEqual(ok, sqlite3:finalize(prepared, Ref1)),
    ?assertMatch({error, _}, sqlite3:next(prepared, Ref1)),
    ?assertEqual(ok, sqlite3:reset(prepared, Ref2)),
    ?assertEqual(ok, sqlite3:bind(prepared, Ref2, ["marge"])),
    ?assertEqual(Marge, sqlite3:next(prepared, Ref2)),
    ?assertEqual(done, sqlite3:next(prepared, Ref2)),
    ?assertEqual(ok, sqlite3:finalize(prepared, Ref2)),
    sqlite3:close(prepared).

script_test() ->
    sqlite3:open(script, [in_memory]),
    Script = string:join(
                 ["CREATE TABLE person(",
                  "id INTEGER",
                  ");",
                  "  ",
                  "-- Comment",
                  "INSERT INTO person (id) VALUES (1);",
                  "INSERT INTO person (id) VALUES (2);",
                  "   "
                 ], "\n"),
    ?assertEqual(
        [ok, ok, ok], 
        sqlite3:sql_exec_script(script, Script)),
    ?assertEqual(
        [{columns,["id"]},{rows,[{1},{2}]}], 
        sqlite3:read_all(script, person)),
    BadScript = string:join(
                 ["CREATE TABLE person2(",
                  "id INTEGER",
                  ");",
                  "  ",
                  "-- Comment",
                  "SYNTAX ERROR;",
                  "INSERT INTO person (id) VALUES (2);",
                  "   "
                 ], "\n"),
    ?WARN_ERROR_MESSAGE,
    ?assertEqual(
        [ok, {error, 1, "near \"SYNTAX\": syntax error"}], 
        sqlite3:sql_exec_script(script, BadScript)),
    sqlite3:close(script).

large_offset() ->
	drop_table_if_exists(ct, large_offset),
	ok = sqlite3:create_table(ct, large_offset, [{id, integer}]),
	?assertEqual(
	    [{columns, ["id"]}, {rows, []}, {error, 20, "datatype mismatch"}],
	    sqlite3:sql_exec(ct, "select * from large_offset limit 1 offset 9223372036854775808")).

% create, read, update, delete
%%====================================================================
%% Internal functions
%%====================================================================
