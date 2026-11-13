using JSON3, LinearAlgebra
BLAS.set_num_threads(1)
include("AnalysisEngine.jl")
try
    input=JSON3.read(read(ARGS[2],String),Dict{String,Any})
    result=AnalysisEngine.analyze(ARGS[1],input)
    write(ARGS[3],JSON3.write(Dict("ok"=>true,"data"=>result)))
catch err
    expected=err isa ArgumentError
    write(ARGS[3],JSON3.write(Dict("ok"=>false,"status"=>expected ? 422 : 500,
        "message"=>expected ? sprint(showerror,err) : "The solver could not verify this model. Check restraints and stiffness contrasts.")))
    @error "analysis_error" exception_type=string(typeof(err))
end
