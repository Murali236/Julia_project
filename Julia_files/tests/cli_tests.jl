using Test, TOML

const ROOT = dirname(@__DIR__)
include(joinpath(ROOT, "run.jl"))

"""Run a real CLI with bounded runtime and captured output."""
function capture_cli(cmd; input="", timeout=180)
    mktempdir() do dir
        input_path = joinpath(dir, "stdin.txt")
        output_path = joinpath(dir, "stdout.txt")
        write(input_path, input)
        code = open(input_path) do source
            open(output_path, "w") do sink
                process = run(pipeline(ignorestatus(cmd); stdin=source, stdout=sink, stderr=sink); wait=false)
                status = timedwait(() -> process_exited(process), timeout; pollint=0.1)
                if status == :timed_out
                    kill(process)
                    wait(process)
                    return -1
                end
                wait(process)
                process.exitcode
            end
        end
        output = read(output_path, String)
        return (; code, output)
    end
end

julia_script(file, args=String[]) = `$(Base.julia_cmd()) --startup-file=no --project=$ROOT $(joinpath(ROOT,file)) $args`

@testset "Launcher rejects invalid arguments" begin
    for args in (["missing"], ["beam","--unknown"], ["beam","--output"],
                 ["beam","--output","--headless"], ["shear","--vx","NaN"],
                 ["shear","--example","input.json"], ["shear","--validate","--example"])
        @test_throws ArgumentError AnalysisRunner.main(args)
    end
    result = capture_cli(julia_script("run.jl", ["--help"]))
    @test result.code == 0
    @test occursin("Usage:", result.output)
end

@testset "Entry scripts can be included without prompting or writing files" begin
    mktempdir() do dir
        files = [joinpath(ROOT, file) for file in ("sfd_bmd_def.jl", "arches.jl", "buckling.jl", "shear_centre.jl", "tempCodeRunnerFile.jl")]
        code = join(["module Import$(i)\ninclude($(repr(file)))\nend" for (i,file) in enumerate(files)], "\n")
        code *= "\nisempty(readdir()) || error(\"Include wrote output files\"); println(\"SAFE_INCLUDE\")"
        cmd = Cmd(`$(Base.julia_cmd()) --startup-file=no --project=$ROOT -e $code`; dir=dir)
        result = capture_cli(cmd)
        @test result.code == 0
        @test strip(result.output) == "SAFE_INCLUDE"
    end
end

@testset "EOF and unstable beam produce failure status" begin
    for script in ("sfd_bmd_def.jl", "arches.jl", "buckling.jl", "shear_centre.jl")
        result = capture_cli(julia_script(script))
        @test result.code == 1
        @test occursin("Input ended", result.output)
    end
    answers = readlines(joinpath(ROOT,"examples","beam_input.txt"))
    # Exhaust input at the load type, both on first entry and after a bad choice.
    prefix = join(answers[1:15], '\n') * "\n"
    for input in (prefix, prefix * "bad load\n")
        result = capture_cli(julia_script("sfd_bmd_def.jl"); input)
        @test result.code == 1
        @test occursin("Input ended", result.output)
    end
    unstable = "6\n2\n0\n6\n200\n0.000008\n0\n1\n1\npin\n0\n0\n"
    result = capture_cli(julia_script("sfd_bmd_def.jl"); input=unstable)
    @test result.code == 1
    @test occursin("unstable", result.output)
end

function example_directory(f)
    destination = get(ENV,"ANALYSIS_EXAMPLE_OUTPUT","")
    isempty(destination) && return mktempdir(f)
    mkpath(destination)
    f(abspath(destination))
end

@testset "All worked examples produce reports and plots" begin
    example_directory() do dir
        for tool in ("beam", "arch", "buckling", "shear")
            destination = joinpath(dir,tool)
            result = capture_cli(julia_script("run.jl", [tool,"--example","--headless","--output",destination]))
            result.code == 0 || println(result.output)
            @test result.code == 0
            files = [joinpath(base,name) for (base,_,names) in walkdir(destination) for name in names]
            plots = filter(f -> endswith(f,".jpg") || endswith(f,".png"), files)
            @test length(plots) == Dict("beam"=>6,"arch"=>8,"buckling"=>6,"shear"=>4)[tool]
            @test all(f -> filesize(f)>1000, plots)
            if tool == "beam"
                report = read(joinpath(destination,"Beam_Analysis_Results","Beam_Analysis_Equations.txt"),String)
                @test occursin("VERIFICATION: PASS",report)
                @test occursin("-21.09375",report)
            elseif tool == "arch"
                model = TOML.parsefile(joinpath(destination,"Arch_Analysis_Results","Arch_Model.toml"))
                @test length(model["frame_reactions"]) == 6
                @test all(isfinite,model["frame_d"])
            elseif tool == "buckling"
                @test occursin("limit_point",result.output)
                @test occursin("postpeak_traced",result.output)
            else
                @test isfile(joinpath(destination,"Shear_Analysis_Results","results.json"))
            end
        end
        # A relative input path must keep referring to the caller's directory.
        result = cd(ROOT) do
            capture_cli(julia_script("run.jl", ["shear","examples/shear_channel.json","--no-plots","--output",joinpath(dir,"relative")]))
        end
        @test result.code == 0
        # Optional Python absence must not prevent a completed numerical export.
        code = "include($(repr(joinpath(ROOT,"arches.jl")))) ; arch_symbolic_export($(repr(dir)))"
        result = capture_cli(addenv(`$(Base.julia_cmd()) --startup-file=no --project=$ROOT -e $code`, "ARCH_PYTHON"=>joinpath(dir,"missing-python")))
        @test result.code == 0
        @test occursin("Optional symbolic export skipped",result.output)
        if Sys.isunix()
            # Bound dependency discovery as well as the symbolic calculation.
            stalled_python=joinpath(dir,"stalled-python")
            write(stalled_python,"#!/bin/sh\nexec sleep 10\n")
            chmod(stalled_python,0o755)
            code = "include($(repr(joinpath(ROOT,"arches.jl")))) ; arch_symbolic_export($(repr(dir)); timeout=0.2)"
            result = capture_cli(addenv(`$(Base.julia_cmd()) --startup-file=no --project=$ROOT -e $code`, "ARCH_PYTHON"=>stalled_python))
            @test result.code == 0
            @test occursin("dependency check timed out",result.output)
            rm(stalled_python)
        end
    end
end
