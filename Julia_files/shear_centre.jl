# Phase 1: open thin-wall centreline geometry (mm), force (N), q (N/mm).
# Positive q follows node_i -> node_j; positive Mz is CCW.
# Solid rectangle/circle shortcuts do not recover thin-wall flow or stress.
include(joinpath(@__DIR__, "shear_solver", "ShearSolver.jl"))
using .ShearSolver
using Printf
include(joinpath(@__DIR__, "shear_solver", "io.jl"))
include(joinpath(@__DIR__, "shear_solver", "plotting.jl"))

function read_number(prompt; positive=false, integer=false)
    while true
        print(prompt)
        eof(stdin) && throw(EOFError())
        value = tryparse(integer ? Int : Float64, strip(readline()))
        if value !== nothing && isfinite(value) && (!positive || value > 0)
            return value
        end
        println(positive ? "Enter a finite positive number." : "Enter a finite number.")
    end
end
get_positive(prompt) = read_number(prompt; positive=true)
shear_centre_distance(xc,yc,xs,ys) = (xs-xc,ys-yc,hypot(xs-xc,ys-yc))

"""Exact solid rectangle; original outside-corner coordinates, mm."""
function rectangular_section(L::Real, B::Real)
    ShearSolver.positive_dimensions(L,B)
    (L*B,L/2,B/2,L*B^3/12,B*L^3/12,0.0,L/2,B/2,0.0,0.0,0.0)
end
rectangular_section() = rectangular_section(get_positive("Length in x (mm): "),get_positive("Width in y (mm): "))

"""Exact solid circle; origin at lower-left of bounding square, mm."""
function circular_section(R::Real)
    ShearSolver.positive_dimensions(R)
    (π*R^2,R,R,π*R^4/4,π*R^4/4,0.0,R,R,0.0,0.0,0.0)
end
circular_section() = circular_section(get_positive("Radius (mm): "))

function display_results(name, A,xc,yc,Ix,Iy,Ixy,xs,ys,dx,dy,e)
    println("\n$name (solid symmetry shortcut; no thin-wall flow/stress calculation)")
    @printf("A = %.8g mm^2; centroid = (%.8g, %.8g) mm\n",A,xc,yc)
    @printf("Ixx = %.8g; Iyy = %.8g; Ixy = %.8g mm^4\n",Ix,Iy,Ixy)
    @printf("Shear centre absolute = (%.8g, %.8g) mm\n",xs,ys)
    @printf("Shear centre relative = (%.8g, %.8g) mm; distance = %.8g mm\n",dx,dy,e)
end

function display_results(r)
    p,c=r.properties,r.centre
    println("\n",r.section.name," — open thin-wall centreline model")
    @printf("Area                         %16.8g mm^2\n",p.A)
    @printf("Centroid (x, y)               (% .8g, % .8g) mm\n",p.xc,p.yc)
    for key in (:Ixx,:Iyy,:Ixy,:I1,:I2)
        @printf("%-28s %16.8g mm^4\n",string(key),getproperty(p,key))
    end
    @printf("Principal-axis angle          %16.8g deg\n",rad2deg(p.theta))
    @printf("SC relative to centroid       (% .8g, % .8g) mm\n",c.xs,c.ys)
    @printf("SC in original coordinates    (% .8g, % .8g) mm\n",c.x,c.y)
    @printf("Distance from centroid        %16.8g mm\n",c.distance)
    for (name,case) in [("Unit Vy",r.unit_y),("Unit Vx",r.unit_x),("Applied",r.applied)]
        @printf("\n%s: Vx=%.8g N, Vy=%.8g N; principal=(%.8g, %.8g) N\n",
                name,case.Vx,case.Vy,case.principal_shear...)
        println("  i    j    t [mm]     q_start        q_mid         q_end       max|tau|")
        println("                         N/mm          N/mm          N/mm        N/mm^2")
        for w in case.walls
            @printf("%3d  %3d  %8.3f  %12.5g  %12.5g  %12.5g  %12.5g\n",
                    w.i,w.j,w.t,w.q_start,w.q_mid,w.q_end,w.tau_max)
        end
        @printf("Force residual: %.3g N; continuity residual: %.3g N/mm; max|tau|: %.6g N/mm^2\n",
                case.resultant_residual,case.continuity_residual,case.tau_max)
    end
end

function interactive_section()
    println("\nSHEAR CENTRE & SHEAR FLOW — Phase 1")
    println("1. Channel   2. Angle   3. T   4. I   5. Solid rectangle   6. Solid circle   7. Z")
    choice=read_number("Choice (1-7): ";integer=true)
    if choice==5
        display_results("Rectangle",rectangular_section()...); return nothing
    elseif choice==6
        display_results("Circle",circular_section()...); return nothing
    end
    choice in (1,2,3,4,7) || throw(ArgumentError("Choose a number from 1 to 7."))
    println("Use wall CENTRELINE lengths, not outside dimensions.")
    b=get_positive(choice in (3,4) ? "Total flange centreline width b (mm): " : "Flange/leg centreline length b (mm): ")
    h=get_positive("Web/vertical-leg centreline depth h (mm): ")
    if choice==2
        section=angle_section(b,h,get_positive("Thickness t (mm): "))
    else
        tw=get_positive("Web thickness tw (mm): ")
        tf=get_positive("Flange thickness tf (mm): ")
        builder=Dict(1=>channel_section,3=>tee_section,4=>i_section,7=>z_section)[choice]
        section=builder(b,h,tw,tf)
    end
    vx=read_number("Applied Vx (N, signed; 0 allowed): ")
    vy=read_number("Applied Vy (N, signed; 0 allowed): ")
    return section,vx,vy
end

function main(args=ARGS)
    if "--help" in args || "-h" in args
        println("Usage: julia Julia_files/shear_centre.jl [section.json | --example] [--vx N] [--vy N] [--output DIR] [--no-plots]")
        println("No input selects the interactive menu. --validate runs built-in benchmarks only.")
        println("Setup: julia --project=Julia_files/shear_solver -e 'using Pkg; Pkg.instantiate()'")
        return nothing
    end
    checks=validation_report()
    if args==["--validate"]
        for (label,pass) in checks
            println(pass ? "PASS " : "FAIL ",label)
        end
        all(last,checks) || error("Benchmark validation failed.")
        return checks
    end
    output=joinpath(@__DIR__,"Shear_Analysis_Results")
    plots=true; input=nothing; example=false; vx=nothing; vy=nothing
    i=1
    while i<=length(args)
        arg=args[i]
        if arg in ("--vx","--vy","--output")
            i+=1
            i<=length(args) || throw(ArgumentError("Missing value for $arg."))
            if arg=="--output"
                output=args[i]
            else
                value=tryparse(Float64,args[i])
                value!==nothing && isfinite(value) || throw(ArgumentError("$arg needs a finite number."))
                arg=="--vx" ? (vx=value) : (vy=value)
            end
        elseif arg=="--no-plots"
            plots=false
        elseif arg=="--example"
            example=true
        elseif startswith(arg,"--")
            throw(ArgumentError("Unknown option: $arg"))
        elseif input===nothing
            input=arg
        else
            throw(ArgumentError("Only one input JSON file is accepted."))
        end
        i+=1
    end
    example && input!==nothing && throw(ArgumentError("Use either --example or an input JSON file."))
    # Isolated dependencies, without installing or changing the global project.
    pushfirst!(LOAD_PATH,joinpath(@__DIR__,"shear_solver"))
    try
        if example
            selected=(channel_section(75,200,6,12),2500.0,10000.0)
        elseif input!==nothing
            selected=load_section_json(input)
        else
            selected=interactive_section()
        end
        selected===nothing && return nothing
        section,default_x,default_y=selected
        r=solve_section(section;Vx=something(vx,default_x),Vy=something(vy,default_y))
        display_results(r)
        all(last,checks) || error("Built-in validation failed; output not saved.")
        println("\nValidation: ",length(checks),"/",length(checks)," built-in benchmarks passed.")
        mkpath(output)
        save_results_json(joinpath(output,"results.json"),r;validation=checks)
        plots && save_plots(r,output)
        println("Saved results",plots ? " and PNG plots" : ""," to ",abspath(output))
        return r
    finally
        popfirst!(LOAD_PATH)
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    try
        main()
    catch err
        if err isa EOFError
            println(stderr,"Input ended before all dimensions/loads were supplied.")
        else
            showerror(stderr,err); println(stderr)
        end
        exit(1)
    end
end
