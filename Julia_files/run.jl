module AnalysisRunner

const ROOT = @__DIR__
const SCRIPTS = Dict("beam"=>"sfd_bmd_def.jl", "arch"=>"arches.jl",
                     "buckling"=>"buckling.jl", "shear"=>"shear_centre.jl")
const EXAMPLES = Dict("beam"=>"examples/beam_input.txt",
                      "arch"=>"tests/arch_example_input.txt",
                      "buckling"=>"examples/buckling_input.txt")

function usage(io=stdout)
    println(io, """
Usage: julia Julia_files/run.jl <beam|arch|buckling|shear> [options]

  --example       Run the supplied worked example without prompts
  --headless      Save plots without opening windows
  --output DIR    Working/output directory (default: Julia_files/output/<tool>)
  --help          Show this help

Shear also accepts: [section.json] [--vx N] [--vy N] [--no-plots] [--validate]
Interactive analyses accept answers from the terminal or redirected standard input.
Setup: julia --project=Julia_files -e 'using Pkg; Pkg.instantiate()'
Tests: julia --project=Julia_files Julia_files/tests/runtests.jl --all
""")
end

function main(args=ARGS)
    if isempty(args) || any(a -> a in ("--help", "-h"), args)
        usage()
        return 0
    end
    tool = first(args)
    haskey(SCRIPTS, tool) || throw(ArgumentError("Unknown analysis '$tool'. Use --help."))
    output = joinpath(ROOT, "output", tool)
    example = false
    headless = false
    extra = String[]
    input_file = nothing
    i = 2
    while i <= length(args)
        arg = args[i]
        if arg == "--output"
            i += 1
            i <= length(args) && !startswith(args[i], "--") ||
                throw(ArgumentError("--output requires a directory."))
            output = abspath(args[i])
        elseif arg == "--example"
            example = true
        elseif arg == "--headless"
            headless = true
        elseif tool == "shear" && arg in ("--vx", "--vy")
            i += 1
            i <= length(args) || throw(ArgumentError("$arg requires a number."))
            value = tryparse(Float64, args[i])
            value !== nothing && isfinite(value) || throw(ArgumentError("$arg requires a finite number."))
            append!(extra, [arg, args[i]])
        elseif tool == "shear" && arg in ("--no-plots", "--validate")
            push!(extra, arg)
        elseif tool == "shear" && !startswith(arg, "-") && input_file === nothing
            input_file = abspath(arg)  # Resolve before changing the child's directory.
        else
            throw(ArgumentError("Unexpected argument '$arg'. Use --help."))
        end
        i += 1
    end
    example && input_file !== nothing && throw(ArgumentError("Choose --example or an input file."))
    validate = "--validate" in extra
    validate && (example || input_file !== nothing || length(extra) != 1) &&
        throw(ArgumentError("--validate cannot be combined with a shear load case."))
    if tool == "shear" && !validate
        input_file !== nothing && push!(extra, input_file)
        example && push!(extra, "--example")
        append!(extra, ["--output", joinpath(output, "Shear_Analysis_Results")])
    end
    mkpath(output)
    cmd = Cmd(`$(Base.julia_cmd()) --startup-file=no --project=$ROOT $(joinpath(ROOT,SCRIPTS[tool])) $extra`; dir=output)
    if headless
        cmd = addenv(cmd, "GKSwstype"=>"100", "JULIA_ANALYSIS_HEADLESS"=>"1")
    end
    function launch(input)
        process = run(pipeline(ignorestatus(cmd); stdin=input, stdout=stdout, stderr=stderr))
        return process.exitcode
    end
    if example && tool != "shear"
        return open(launch, joinpath(ROOT, EXAMPLES[tool]))
    end
    return launch(stdin)
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        exit(AnalysisRunner.main())
    catch err
        if err isa ArgumentError
            showerror(stderr, err); println(stderr)
            exit(1)
        end
        rethrow()
    end
end
