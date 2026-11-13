module AnalysisCLI

export run_cli, required_line, show_plot_windows

"""Read one answer, failing on exhausted input instead of retrying forever."""
function required_line(input=stdin)
    eof(input) && throw(EOFError())
    readline(input)
end

show_plot_windows() = get(ENV, "JULIA_ANALYSIS_HEADLESS", "0") != "1"

"""Translate expected input failures into a useful message and nonzero status."""
function run_cli(f)
    try
        f()
        return 0
    catch err
        if err isa EOFError
            println(stderr, "Input ended before all model data were supplied.")
        elseif err isa ArgumentError
            showerror(stderr, err)
            println(stderr)
        elseif err isa InterruptException
            println(stderr, "Analysis interrupted.")
            return 130
        else
            rethrow()
        end
        return 1
    end
end

end
