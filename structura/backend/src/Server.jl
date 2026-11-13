include("Router.jl")
host=get(ENV,"HOST","127.0.0.1"); port=parse(Int,get(ENV,"PORT","8080"))
@info JSON3.write((event="server_start",host=host,port=port,engine="Julia",version=string(VERSION)))
HTTP.serve(streamhandler,host,port;stream=true,readtimeout=60)
