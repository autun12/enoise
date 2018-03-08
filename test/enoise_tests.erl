%%%-------------------------------------------------------------------
%%% @copyright (C) 2018, Aeternity Anstalt
%%%-------------------------------------------------------------------

-module(enoise_tests).

-include_lib("eunit/include/eunit.hrl").

noise_dh25519_test_() ->
    %% Test vectors from https://raw.githubusercontent.com/rweather/noise-c/master/tests/vector/noise-c-basic.txt
    {setup,
        fun() -> setup_dh25519() end,
        fun(_X) -> ok end,
        fun({Tests, SKP, CKP}) ->
            [ {T, fun() -> noise_test(T, SKP, CKP) end} || T <- Tests ]
        end
    }.

setup_dh25519() ->
    %% Generate a static key-pair for Client and Server
    SrvKeyPair = enoise_keypair:new(dh25519),
    CliKeyPair = enoise_keypair:new(dh25519),

    #{ hs_pattern := Ps, hash := Hs, cipher := Cs } = enoise_protocol:supported(),
    Configurations = [ enoise_protocol:to_name(P, dh25519, C, H)
                       || P <- Ps, C <- Cs, H <- Hs ],
    %% Configurations = [ enoise_protocol:to_name(xk, dh25519, 'ChaChaPoly', blake2b) ],
    {Configurations, SrvKeyPair, CliKeyPair}.

noise_test(Conf, SKP, CKP) ->
    Protocol = enoise_protocol:from_name(Conf),
    Port     = 4556,

    EchoSrv = echo_srv_start(Port, Protocol, SKP, CKP),

    {ok, TcpSock} = gen_tcp:connect("localhost", Port, [{active, false}, binary, {reuseaddr, true}], 100),

    Opts = [{noise, Protocol}, {s, CKP}] ++ [{rs, SKP} || need_rs(initiator, Conf) ],
    {ok, EConn} = enoise:connect(TcpSock, Opts),

    ok = enoise:send(EConn, <<"Hello World!">>),
    {ok, <<"Hello World!">>} = enoise:recv(EConn, 12, 100),

    ok = enoise:send(EConn, <<"Goodbye!">>),
    timer:sleep(10),
    {ok, <<"Goodbye!">>} = enoise:recv(EConn, 0, 100),

    enoise:close(EConn),
    echo_srv_stop(EchoSrv),
    ok.

echo_srv_start(Port, Protocol, SKP, CPub) ->
    Pid = spawn(fun() -> echo_srv(Port, Protocol, SKP, CPub) end),
    timer:sleep(10),
    Pid.

echo_srv(Port, Protocol, SKP, CPub) ->
    TcpOpts  = [{active, true}, binary, {reuseaddr, true}],

    {ok, LSock} = gen_tcp:listen(Port, TcpOpts),
    {ok, TcpSock} = gen_tcp:accept(LSock, 500),

    Opts = [{noise, Protocol}, {s, SKP}] ++  [{rs, CPub} || need_rs(responder, Protocol)],
    {ok, EConn} = enoise:accept(TcpSock, Opts),

    gen_tcp:close(LSock),

    %% {ok, Msg} = enoise:recv(EConn, 0, 100),
    Msg0 = receive {noise, EConn, Data0} -> Data0
           after 200 -> error(timeout) end,
    ok = enoise:send(EConn, Msg0),

    %% {ok, Msg} = enoise:recv(EConn, 0, 100),
    Msg1 = receive {noise, EConn, Data1} -> Data1
          after 200 -> error(timeout) end,
    ok = enoise:send(EConn, Msg1),

    ok.

echo_srv_stop(Pid) ->
    erlang:exit(Pid, kill).

need_rs(Role, Conf) when is_binary(Conf) -> need_rs(Role, enoise_protocol:from_name(Conf));
need_rs(Role, Protocol) ->
    PreMsgs = enoise_protocol:pre_msgs(Role, Protocol),
    lists:member({in, [s]}, PreMsgs).

%% Talks to local echo-server (noise-c)
client_test() ->
    TestProtocol = enoise_protocol:from_name("Noise_XK_25519_ChaChaPoly_BLAKE2b"),
    ClientPrivKey = <<64,168,119,119,151,194,94,141,86,245,144,220,78,53,243,231,168,216,66,199,49,148,202,117,98,40,61,109,170,37,133,122>>,
    ClientPubKey  = <<115,39,86,77,44,85,192,176,202,11,4,6,194,144,127,123, 34,67,62,180,190,232,251,5,216,168,192,190,134,65,13,64>>,
    ServerPubKey  = <<112,91,141,253,183,66,217,102,211,40,13,249,238,51,77,114,163,159,32,1,162,219,76,106,89,164,34,71,149,2,103,59>>,

    {ok, TcpSock} = gen_tcp:connect("localhost", 7890, [{active, false}, binary, {reuseaddr, true}], 1000),
    gen_tcp:send(TcpSock, <<0,8,0,0,3>>), %% "Noise_XK_25519_ChaChaPoly_Blake2b"

    Opts = [ {noise, TestProtocol}
           , {s, enoise_keypair:new(dh25519, ClientPrivKey, ClientPubKey)}
           , {rs, enoise_keypair:new(dh25519, ServerPubKey)}
           , {prologue, <<0,8,0,0,3>>}],

    {ok, EConn} = enoise:connect(TcpSock, Opts),
    ok = enoise:send(EConn, <<"ok\n">>),
    %% receive
    %%     {noise, EConn, <<"ok\n">>} -> ok
    %% after 1000 -> error(timeout) end,
    {ok, <<"ok\n">>} = enoise:recv(EConn, 3, 1000),
    enoise:close(EConn).


%% Expects a call-in from a local echo-client (noise-c)
%% server_test_() ->
%%     {timeout, 20, fun() ->
%%     TestProtocol = enoise_protocol:from_name("Noise_XK_25519_ChaChaPoly_Blake2b"),

%%     ServerPrivKey = <<200,81,196,192,228,196,182,200,181,83,169,255,242,54,99,113,8,49,129,92,225,220,99,50,93,96,253,250,116,196,137,103>>,
%%     ServerPubKey  = <<112,91,141,253,183,66,217,102,211,40,13,249,238,51,77,114,163,159,32,1,162,219,76,106,89,164,34,71,149,2,103,59>>,

%%     Opts = [ {noise, TestProtocol}
%%            , {s, enoise_keypair:new(dh25519, ServerPrivKey, ServerPubKey)}
%%            , {prologue, <<0,8,0,0,3>>}],

%%     {ok, LSock} = gen_tcp:listen(7891, [{reuseaddr, true}, binary]),

%%     {ok, TcpSock} = gen_tcp:accept(LSock, 10000),

%%     receive {tcp, TcpSock, <<0,8,0,0,3>>} -> ok
%%     after 1000 -> error(timeout) end,

%%     {ok, EConn} = enoise:accept(TcpSock, Opts),

%%     {EConn1, Msg} = enoise:recv(EConn),
%%     EConn2 = enoise:send(EConn1, Msg),

%%     enoise:close(EConn2)
%%     end}.



