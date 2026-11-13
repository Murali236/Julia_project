using Plots, Printf, TOML
include(joinpath(@__DIR__, "cli_support.jl"))
using .AnalysisCLI
include(joinpath(@__DIR__, "arch_analysis.jl"))
include(joinpath(@__DIR__, "arch_legacy.jl"))

# Interactive wrapper. Numerical functions are namespaced in ArchAnalysis;
# original three-hinged/moving-point-load helpers remain in ArchLegacy.
# Input: m, kN, kN/m of horizontal projection, kN-m, GPa, m^2 and m^4.
function arch_number(prompt; positive=false, nonnegative=false)
    while true
        print(prompt)
        eof(stdin) && throw(EOFError())
        x=tryparse(Float64,strip(readline()))
        if x!==nothing && isfinite(x) && (!positive || x>0) && (!nonnegative || x>=0)
            return x
        end
        println("Enter a finite number",positive ? " greater than zero." : nonnegative ? " at least zero." : ".")
    end
end
function arch_integer(prompt,lo,hi=typemax(Int))
    while true
        print(prompt);eof(stdin) && throw(EOFError())
        n=tryparse(Int,strip(readline()))
        n!==nothing && lo<=n<=hi && return n
        println("Enter an integer between $lo and $hi.")
    end
end
function arch_position(prompt,L;lo=0.0,hi=L,strict=false)
    while true
        x=arch_number(prompt)
        (strict ? lo<x<hi : lo<=x<=hi) && return x
        println(strict ? "Require $lo < x < $hi." : "Require $lo <= x <= $hi.")
    end
end
function read_arch_geometry()
    choice=arch_integer("Geometry: 1 parabola, 2 circular arc, 3 polyline: ",1,3)
    L=arch_number("Horizontal span L (m): ";positive=true)
    if choice==1
        return ArchAnalysis.Geometry(:parabolic,L,arch_number("Rise f (m): ";positive=true))
    elseif choice==2
        mode=arch_integer("Circular geometry: 1 enter rise, 2 enter radius: ",1,2)
        if mode==1
            f=arch_position("Rise f (m, 0 < f <= L/2): ",L;hi=L/2)
            while f==0;f=arch_position("Enter positive rise (m): ",L;hi=L/2);end
        else
            R=arch_number("Radius R (m, R >= L/2): ";positive=true)
            while R<L/2;R=arch_number("Radius must be at least $(L/2) m: ";positive=true);end
            f=(L/2)^2/(R+sqrt(R^2-(L/2)^2))
        end
        return ArchAnalysis.Geometry(:circular,L,f)
    else
        n=arch_integer("Number of interior polyline vertices: ",1)
        xs=[0.0];ys=[0.0]
        for i in 1:n
            x=arch_position("Vertex $i x (m): ",L;lo=xs[end],strict=true)
            y=arch_number("Vertex $i y above support line (m): ")
            push!(xs,x);push!(ys,y)
        end
        push!(xs,L);push!(ys,0.0)
        f=maximum(abs,ys)
        f>0 || throw(ArgumentError("An arch must have a nonzero rise."))
        return ArchAnalysis.Geometry(:polyline,L,f;xs=xs,ys=ys)
    end
end
function read_arch_sections(g)
    n=arch_integer("Number of property regions (1 for uniform): ",1)
    sections=ArchAnalysis.Section[];a=0.0
    for i in 1:n
        b=i==n ? g.L : arch_position("End of property region $i (m): ",g.L;lo=a,strict=true)
        E=1e9arch_number("Region $i E (GPa): ";positive=true)
        A=arch_number("Region $i area A (m^2): ";positive=true)
        I=arch_number("Region $i I (m^4): ";positive=true)
        law=arch_integer("I variation: 0 constant, 1 I(x)=I0/cos(phi) (textbook model): ",0,1)
        push!(sections,ArchAnalysis.Section(a,b,E,A,I;law=law==0 ? :constant : :secant))
        a=b
    end
    sections
end
function read_arch_loads(g,support,hinge)
    println("Angles: 0 right, 90 up, -90 down, 180 left. Positive moments anticlockwise.")
    println("Distributed intensities are per horizontal projected metre.")
    n=arch_integer("Number of applied loads: ",0)
    loads=ArchAnalysis.Load[]
    for i in 1:n
        kind=arch_integer("Load $i: 1 point force, 2 UDL, 3 UVL, 4 moment: ",1,4)
        if kind in (1,4)
            x=arch_position("Load x from left support (m): ",g.L)
            if kind==4 && support==:three_hinged
                while x==hinge
                    println("A moment at the internal hinge needs a member side; choose a position off the hinge.")
                    x=arch_position("Moment x (m): ",g.L)
                end
            end
            @printf("Arch ordinate y = %.8g m (calculated automatically).\n",ArchAnalysis.ordinate(g,x))
            if kind==4
                push!(loads,ArchAnalysis.Couple(x,1000arch_number("Moment (kN-m): ")))
            else
                P=1000arch_number("Force magnitude (kN): ";nonnegative=true)
                angle=arch_number("Force angle (degrees): ")
                push!(loads,ArchAnalysis.PointForce(x,P*cosd(angle),P*sind(angle)))
            end
        else
            a=arch_position("Load start x (m): ",g.L)
            while a==g.L;a=arch_position("Start must be less than L (m): ",g.L);end
            b=arch_position("Load end x (m): ",g.L;lo=a)
            while b==a;b=arch_position("End must be greater than start (m): ",g.L;lo=a);end
            wa=1000arch_number(kind==2 ? "UDL intensity (kN/m): " : "Start intensity (kN/m): ")
            wb=kind==2 ? wa : 1000arch_number("End intensity (kN/m): ")
            angle=arch_number("Load angle (degrees): ")
            push!(loads,ArchAnalysis.LineLoad(a,b,wa*cosd(angle),wa*sind(angle),wb*cosd(angle),wb*sind(angle)))
        end
    end
    loads
end
function arch_plot_save(p,folder,name)
    png=joinpath(folder,name*".png");savefig(p,png)
    if Sys.isapple()
        jpg=joinpath(folder,name*".jpg")
        try
            run(pipeline(`sips -s format jpeg $png --out $jpg`,stdout=devnull))
            rm(png)
            return jpg
        catch
            println("JPEG conversion unavailable; retained $png")
        end
    end
    png
end
function arch_write_samples(path,s)
    open(path,"w") do io
        println(io,"x_m,M_kNm,N_kN,Q_kN,u_mm,v_mm,theta_rad")
        for i in eachindex(s.x)
            println(io,join((s.x[i],s.M[i]/1000,s.N[i]/1000,s.Q[i]/1000,1000s.u[i],1000s.v[i],s.theta[i]),","))
        end
    end
end
function arch_symbolic_export(folder; timeout=45.0)
    isfinite(timeout) && timeout>0 || throw(ArgumentError("Symbolic timeout must be finite and positive."))
    localpython=joinpath(@__DIR__,"..",".venv-arch","bin","python")
    python=get(ENV,"ARCH_PYTHON",isfile(localpython) ? localpython : something(Sys.which("python3"),"python3"))
    helper=joinpath(@__DIR__,"arch_symbolic.py")
    if Sys.which(python) === nothing
        println("Optional symbolic export skipped: Python executable unavailable: ", python)
        return nothing
    end
    started=time()
    probe=run(pipeline(`$python -c "import sympy, tomllib"`,stdout=devnull,stderr=devnull);wait=false)
    status=timedwait(()->process_exited(probe),min(10.0,timeout);pollint=0.1)
    if status==:timed_out
        process_exited(probe) || kill(probe)
        wait(probe)
        println("Optional symbolic export skipped: Python dependency check timed out. Numerical results remain available.")
        return nothing
    end
    wait(probe)
    if success(probe)
        process=run(`$python $helper $(joinpath(folder,"Arch_Model.toml"))`;wait=false)
        status=timedwait(()->process_exited(process),max(0.1,timeout-(time()-started));pollint=0.1)
        if status==:timed_out
            process_exited(process) || kill(process)
            wait(process)
            println("Symbolic export timed out. Numerical equations and results remain available.")
        elseif !success(process)
            println("Symbolic export failed; see numerical equations in Arch_Analysis_Results.txt.")
        end
    else
        println("SymPy export is optional: install requirements-arch.txt using Python 3.11+; see ARCH_ANALYSIS.md.")
    end
end
function arches_main(; show_plots=show_plot_windows())
    println("ARCH ANALYSIS: force method and frame stiffness")
    kind=arch_integer("Arch: 1 two-hinged, 2 three-hinged, 3 fixed-fixed: ",1,3)
    support=(:two_hinged,:three_hinged,:fixed)[kind]
    println("Base degree of static indeterminacy = ",ArchAnalysis.doi(support))
    g=read_arch_geometry()
    hinge=support==:three_hinged && g.kind==:polyline ? arch_position("Internal hinge x (m): ",g.L;strict=true) : g.L/2
    elements=arch_integer("Base number of frame elements (e.g. 80): ",2)
    sections=read_arch_sections(g)
    axial=arch_integer("Include axial deformation? 1 yes (frame comparison), 0 bending-only force method: ",0,1)==1
    springs=ArchAnalysis.Spring[]
    if axial
        n=arch_integer("Additional elastic supports (0 for none; uses stiffness method only): ",0)
        for i in 1:n
            x=arch_position("Spring $i x (m): ",g.L)
            kx=1000arch_number("Horizontal stiffness (kN/m, 0 for none): ";nonnegative=true)
            ky=1000arch_number("Vertical stiffness (kN/m, 0 for none): ";nonnegative=true)
            kr=1000arch_number("Rotational stiffness (kN-m/rad, 0 for none): ";nonnegative=true)
            push!(springs,ArchAnalysis.Spring(x,kx,ky,kr))
        end
    end
    loads=read_arch_loads(g,support,hinge)
    model=ArchAnalysis.Model(g,support,sections,loads;axial=axial,hinge=hinge,springs=springs)
    println("Solving compatibility and assembling frame elements...")
    force=isempty(springs) ? ArchAnalysis.solve_force(model) : nothing
    frame=axial ? ArchAnalysis.solve_stiffness(model;elements=elements) : nothing
    textreport=ArchAnalysis.report(model,force,frame)
    println(textreport)
    folder=joinpath(pwd(),"Arch_Analysis_Results");mkpath(folder)
    write(joinpath(folder,"Arch_Analysis_Results.txt"),textreport)
    ArchAnalysis.export_model(joinpath(folder,"Arch_Model.toml"),model,force,frame)
    fs=force===nothing ? nothing : ArchAnalysis.force_samples(force)
    ks=frame===nothing ? nothing : ArchAnalysis.stiffness_samples(frame)
    fs!==nothing && arch_write_samples(joinpath(folder,"Force_Method_Stations.csv"),fs)
    ks!==nothing && arch_write_samples(joinpath(folder,"Stiffness_Stations.csv"),ks)
    plots=[]
    for (key,title,unit,factor,name) in ((:M,"Arch bending moment","kN-m",0.001,"Arch_BMD"),(:N,"Arch axial force (tension positive)","kN",0.001,"Arch_NFD"),(:Q,"Arch local shear force","kN",0.001,"Arch_SFD"),(:u,"Horizontal displacement","mm",1000.0,"Arch_Horizontal_Displacement"),(:v,"Vertical displacement","mm",1000.0,"Arch_Deflection"),(:theta,"Cross-section rotation","rad",1.0,"Arch_Rotation"))
        p=plot(xlabel="Horizontal distance x (m)",ylabel=unit,title=title,size=(1200,650),
               left_margin=12Plots.mm,bottom_margin=10Plots.mm,top_margin=4Plots.mm,right_margin=5Plots.mm)
        fs!==nothing && plot!(p,fs.x,getproperty(fs,key).*factor,label="Force method",linewidth=2)
        ks!==nothing && plot!(p,ks.x,getproperty(ks,key).*factor,label="Frame stiffness",linestyle=:dash,linewidth=2)
        hline!(p,[0.0],color=:gray,label="",linewidth=0.7)
        arch_plot_save(p,folder,name);push!(plots,p)
    end
    combined=plot(plots...,layout=(6,1),size=(1400,3000))
    arch_plot_save(combined,folder,"Arch_Analysis_Combined")
    x=frame===nothing ? collect(range(0,g.L,length=101)) : frame.x
    geometryplot=plot(x,ArchAnalysis.ordinate.(Ref(g),x),aspect_ratio=:equal,linewidth=2,xlabel="x (m)",ylabel="y (m)",title="$(support) arch",legend=false,size=(1200,650),left_margin=12Plots.mm,bottom_margin=10Plots.mm)
    scatter!(geometryplot,[0.0,g.L],[0.0,0.0],markersize=5)
    support==:three_hinged && scatter!(geometryplot,[hinge],[ArchAnalysis.ordinate(g,hinge)],markersize=5)
    arch_plot_save(geometryplot,folder,"Arch_Geometry")
    arch_symbolic_export(folder)
    # Preserve the old moving-load equations for the original geometry family.
    if support==:three_hinged && isempty(springs) && length(loads)==1 && loads[1] isa ArchAnalysis.PointForce && g.kind!=:polyline
        l=loads[1];P=hypot(l.fx,l.fy);angle=atand(l.fy,l.fx)
        oldload=ArchLegacy.PointLoad(l.x,ArchAnalysis.ordinate(g,l.x),P/1000,angle)
        open(joinpath(folder,"Moving_Point_Load_Equations.txt"),"w") do io
            redirect_stdout(io) do
                ArchLegacy.print_point_reaction_functions(oldload,g.kind==:parabolic ? 1 : 2,g.L,g.f)
            end
        end
    end
    if show_plots
        display(combined);display(geometryplot)
    end
    println("Results saved to ",abspath(folder))
    return (model=model,force=force,frame=frame)
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(run_cli(arches_main))
end
