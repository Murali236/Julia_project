using Test
using TOML

function runtests(args=ARGS)
    if "--help" in args
        println("Usage: julia Julia_files/tests/runtests.jl [--io] [--cli] [--all]")
        println("Default: numerical suites (standard libraries only). --io adds JSON; --cli adds examples/plotting; --all enables both.")
        return
    end
    all(a -> a in ("--io", "--cli", "--all"), args) || throw(ArgumentError("Unknown test option; use --help."))
    root = dirname(@__DIR__)
    suites = ["beam_stiffness_tests.jl", "arch_analysis_tests.jl", "buckling_tests.jl", "shear_solver_tests.jl"]
    any(a -> a in ("--cli", "--all"), args) && push!(suites, "cli_tests.jl")
    @testset "Structural analysis project" begin
        @testset "Source and environment syntax" begin
            has_parse_error(x) = x isa Expr && (x.head in (:error,:incomplete) || any(has_parse_error,x.args))
            for (dir, subdirs, files) in walkdir(root)
                filter!(!=("output"), subdirs)
                for file in files
                    if endswith(file,".jl") || endswith(file,".jl.bak")
                        @test !has_parse_error(Meta.parseall(read(joinpath(dir,file),String)))
                    elseif endswith(file,".toml")
                        @test TOML.parsefile(joinpath(dir,file)) isa Dict
                    end
                end
            end
        end
        for suite in suites
            flags = suite == "shear_solver_tests.jl" && any(a -> a in ("--io", "--all"), args) ? ["--io"] : String[]
            @testset "$suite" begin
                cmd = `$(Base.julia_cmd()) --startup-file=no --project=$root $(joinpath(@__DIR__,suite)) $flags`
                # Separate processes isolate solver modules and test constants.
                @test success(pipeline(cmd; stdout=stdout, stderr=stderr))
            end
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    runtests()
end
