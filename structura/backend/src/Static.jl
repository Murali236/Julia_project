# Serve only files present in the frontend build. A URL never becomes an
# arbitrary filesystem path, so traversal cannot expose backend source files.
const STATIC_ROOT=normpath(joinpath(@__DIR__,"../../frontend/dist"))
const STATIC_FILES=Dict{String,String}()
if isdir(STATIC_ROOT)
    for (dir,_,files) in walkdir(STATIC_ROOT), file in files
        full=joinpath(dir,file)
        STATIC_FILES["/"*replace(relpath(full,STATIC_ROOT),'\\'=>'/')]=full
    end
end
const STATIC_TYPES=Dict(
    ".html"=>"text/html; charset=utf-8", ".js"=>"text/javascript; charset=utf-8",
    ".css"=>"text/css; charset=utf-8", ".json"=>"application/json",
    ".svg"=>"image/svg+xml", ".png"=>"image/png", ".ico"=>"image/x-icon",
    ".jpg"=>"image/jpeg", ".webp"=>"image/webp", ".woff2"=>"font/woff2")
function static_response(path)
    isempty(STATIC_FILES) && return failure(404,"Endpoint not found.")
    file=get(STATIC_FILES,path,nothing)
    # Extensionless application routes use React Router's entry point. Missing
    # assets and API endpoints must still produce a real 404.
    if file===nothing && isempty(splitext(path)[2])
        file=get(STATIC_FILES,"/index.html",nothing)
    end
    file===nothing && return failure(404,"File not found.")
    HTTP.Response(200,["Content-Type"=>get(STATIC_TYPES,splitext(file)[2],"application/octet-stream")],read(file))
end
