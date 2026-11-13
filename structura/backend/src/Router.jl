using HTTP, JSON3, Dates
const ROOT=normpath(joinpath(@__DIR__,"../.."))
const ORIGINS=split(get(ENV,"FRONTEND_ORIGINS","http://localhost:5173,http://127.0.0.1:5173"),',')
const MAX_BODY=parse(Int,get(ENV,"MAX_BODY_BYTES","262144"))
const MAX_JOBS=parse(Int,get(ENV,"MAX_CONCURRENT_JOBS","2"))
const ACTIVE=Ref(0); const JOB_LOCK=ReentrantLock(); const CACHE_LOCK=ReentrantLock()
const CACHE=Dict{String,Tuple{Float64,Any}}()
json(status,data)=HTTP.Response(status,["Content-Type"=>"application/json"],JSON3.write(data))
failure(status,message)=json(status,Dict("status"=>"failed","error"=>Dict("message"=>message)))
function limited_job(f)
    accepted=lock(JOB_LOCK) do
        ACTIVE[]>=MAX_JOBS && return false
        ACTIVE[]+=1; true
    end
    accepted || return failure(429,"The solver is busy. Please try again shortly.")
    try f() finally lock(JOB_LOCK) do; ACTIVE[]-=1; end; end
end
function run_bounded(command,seconds)
    process=run(pipeline(command,stdout=devnull);wait=false)
    try
        if timedwait(()->process_exited(process),seconds;pollint=0.05)==:timed_out
            kill(process,Base.SIGKILL); wait(process)
            return false
        end
        wait(process); success(process)
    finally
        process_running(process) && (kill(process,Base.SIGKILL); wait(process))
    end
end
function route(req)
    path=split(req.target,'?')[1]
    if req.method=="GET" && path=="/api/health"
        return json(200,(status="ok",engine="Julia",version=string(VERSION),softwareVersion="0.1.0",modules=["beam","deflection","shear-centre","buckling","arch"]))
    end
    req.method=="POST" || return failure(404,"Endpoint not found.")
    startswith(HTTP.header(req,"Content-Type",""),"application/json") || return failure(415,"Use application/json.")
    body=try JSON3.read(req.body,Dict{String,Any}) catch; return failure(400,"Malformed JSON object."); end
    if startswith(path,"/api/analysis/")
        kind=split(path,'/')[end]
        kind in ("beam","deflection","shear-centre","buckling","arch") || return failure(404,"Unknown analysis module.")
        return limited_job() do
            mktempdir() do dir
                source=joinpath(dir,"input.json"); destination=joinpath(dir,"result.json")
                write(source,JSON3.write(body))
                cmd=`$(Base.julia_cmd()) --startup-file=no --threads=1 --project=$(joinpath(ROOT,"backend")) $(joinpath(@__DIR__,"Worker.jl")) $kind $source $destination`
                ok=run_bounded(cmd,parse(Float64,get(ENV,"ANALYSIS_TIMEOUT_SECONDS","45")))
                ok && isfile(destination) || return failure(504,"Analysis timed out or the worker stopped. Simplify the model and retry.")
                envelope=JSON3.read(read(destination,String),Dict{String,Any})
                envelope["ok"] || return failure(envelope["status"],envelope["message"])
                result=envelope["data"]
                lock(CACHE_LOCK) do
                    for (id,(at,_)) in collect(CACHE); time()-at>86400 && delete!(CACHE,id); end
                    if length(CACHE)>=100
                        oldest=first(sort!(collect(keys(CACHE));by=id->CACHE[id][1])); delete!(CACHE,oldest)
                    end
                    CACHE[result["analysisId"]]=(time(),result)
                end
                @info JSON3.write((event="analysis_completed",analysisId=result["analysisId"],kind=kind))
                return json(200,result)
            end
        end
    elseif path=="/api/report/generate"
        id=get(body,"analysisId",nothing)
        id isa String || return failure(400,"analysisId is required.")
        record=lock(()->get(CACHE,id,nothing),CACHE_LOCK)
        record===nothing && return failure(404,"Analysis expired or the API restarted. Run this model again to generate a report.")
        time()-record[1]<=86400 || return failure(410,"Analysis expired. Recompute to generate a report.")
        return limited_job() do
            mktempdir() do dir
                source=joinpath(dir,"analysis.json"); destination=joinpath(dir,"report.pdf")
                write(source,JSON3.write(record[2]))
                cmd=`node $(joinpath(ROOT,"reports","render.mjs")) $source $destination`
                ok=run_bounded(cmd,parse(Float64,get(ENV,"REPORT_TIMEOUT_SECONDS","45")))
                ok && isfile(destination) || return failure(503,"PDF rendering is unavailable. Install report dependencies and Chromium; see the README.")
                kind=record[2]["analysisType"]
                name=replace(record[2]["inputSummary"]["projectName"],r"[^A-Za-z0-9_-]"=>"_")
                return HTTP.Response(200,["Content-Type"=>"application/pdf","Content-Disposition"=>"attachment; filename=\"Structura_$(kind)_Analysis_$(name).pdf\""],read(destination))
            end
        end
    end
    failure(404,"Endpoint not found.")
end
function handler(req)
    origin=HTTP.header(req,"Origin","")
    origin!="" && !(origin in ORIGINS) && return failure(403,"This frontend origin is not allowed.")
    response=try
        req.method=="OPTIONS" ? HTTP.Response(204) : route(req)
    catch err
        @error JSON3.write((event="request_error",exceptionType=string(typeof(err))))
        failure(500,"The request could not be completed. Please retry.")
    end
    for (key,value) in ["X-Content-Type-Options"=>"nosniff","Cache-Control"=>"no-store","Vary"=>"Origin"]
        HTTP.setheader(response,key=>value)
    end
    if origin in ORIGINS
        HTTP.setheader(response,"Access-Control-Allow-Origin"=>origin)
        HTTP.setheader(response,"Access-Control-Allow-Methods"=>"GET, POST, OPTIONS")
        HTTP.setheader(response,"Access-Control-Allow-Headers"=>"Content-Type")
    end
    response
end
# Read in bounded chunks before constructing a request body (including chunked uploads).
function streamhandler(stream)
    req=stream.message; body=UInt8[]
    response=nothing
    declared=try parse(Int,HTTP.header(req,"Content-Length","0")) catch; -1; end
    if declared<0 || declared>MAX_BODY
        response=failure(413,"Request body exceeds the configured limit.")
    else
        while !eof(stream)
            chunk=read(stream,min(8192,MAX_BODY+1-length(body)))
            append!(body,chunk)
            if length(body)>MAX_BODY
                response=failure(413,"Request body exceeds the configured limit."); break
            end
        end
    end
    if response===nothing
        req.body=body; response=handler(req)
    else
        HTTP.setheader(response,"Connection"=>"close")
    end
    HTTP.setstatus(stream,response.status)
    for h in response.headers; HTTP.setheader(stream,h); end
    HTTP.startwrite(stream); write(stream,response.body)
end
