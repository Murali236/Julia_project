module ExtendedAnalysis
using LinearAlgebra
include("../Legacy/shear_solver/ShearSolver.jl")
include("../Legacy/buckling_core.jl")
include("../Legacy/arch_analysis.jl")

function number(d,k; lo=-1e12,hi=1e12,positive=false,integer=false)
    v=get(d,k,nothing)
    v isa Real && !(v isa Bool) && isfinite(v) && lo<=v<=hi && (!positive || v>0) && (!integer || isinteger(v)) ||
        throw(ArgumentError("$k must be a finite $(positive ? "positive " : "")$(integer ? "integer " : "")number in [$lo, $hi]."))
    Float64(v)
end
function choice(d,k,values)
    v=get(d,k,nothing)
    v in values || throw(ArgumentError("$k must be one of: $(join(values, ", "))."))
    String(v)
end
function fields(d,allowed)
    d isa AbstractDict || throw(ArgumentError("Expected a JSON object."))
    all(k->k in allowed,keys(d)) || throw(ArgumentError("Unknown input field. Use this module's input format."))
end
metric(label,value,unit)= (;label,value,unit)
table(title,columns,rows)= (;title,columns,rows)
plot(key,label,unit,x,values,color; xLabel="Horizontal position (m)",xUnit="m") = (;key,label,unit,x,values,color,xLabel,xUnit)
function analyze(kind,d)
    get(d,"schemaVersion",nothing)===1 || throw(ArgumentError("schemaVersion must be integer 1."))
    get(d,"type",nothing)==kind || throw(ArgumentError("Input type must match the selected analysis module."))
    name=get(d,"projectName",nothing)
    name isa String && 1<=length(strip(name))<=120 || throw(ArgumentError("projectName must contain 1–120 characters."))
    kind=="shear-centre" ? shear(d) : kind=="buckling" ? buckling(d) : arch(d)
end

function shear(d)
    fields(d,["schemaVersion","type","projectName","section","b","h","tw","tf","Vx","Vy"])
    shape=choice(d,"section",["channel","angle","tee","i","z"])
    b,h,tw,tf=[number(d,k;positive=true,hi=1e5) for k in ("b","h","tw","tf")]
    vx,vy=[number(d,k;lo=-1e8,hi=1e8) for k in ("Vx","Vy")]
    constructors=Dict("channel"=>ShearSolver.channel_section,"tee"=>ShearSolver.tee_section,"i"=>ShearSolver.i_section,"z"=>ShearSolver.z_section)
    s=shape=="angle" ? ShearSolver.angle_section(b,h,tw) : constructors[shape](b,h,tw,tf)
    r=ShearSolver.solve_section(s;Vx=vx,Vy=vy); p=r.properties; c=r.centre
    cases=map((("applied",r.applied),("unit-x",r.unit_x),("unit-y",r.unit_y))) do (key,f)
        walls=[(;i=w.i,j=w.j,t=w.t,L=w.L,qStart=w.q_start,qEnd=w.q_end,tauMax=w.tau_max,
                 s=collect(range(0,w.L,length=41)),q=[ShearSolver.flow_at(w,x) for x in range(0,w.L,length=41)]) for w in f.walls]
        (;key,walls,Vx=f.Vx,Vy=f.Vy,maxStress=f.tau_max)
    end
    warnings=String[]
    max(tw,shape=="angle" ? tw : tf)/min(b,h)>0.1 && push!(warnings,"Thickness exceeds 10% of a section dimension. The centreline thin-wall approximation may be unsuitable.")
    results=(metrics=[metric("Shear centre x",c.x,"mm"),metric("Shear centre y",c.y,"mm"),metric("Offset from centroid",c.distance,"mm"),metric("Maximum |τ|",r.applied.tau_max,"MPa")],
        tables=[table("Section properties",["Property","Value","Unit"],[["Area",p.A,"mm²"],["Centroid x",p.xc,"mm"],["Centroid y",p.yc,"mm"],["Ixx",p.Ixx,"mm⁴"],["Iyy",p.Iyy,"mm⁴"],["Ixy",p.Ixy,"mm⁴"],["Principal I₁",p.I1,"mm⁴"],["Principal I₂",p.I2,"mm⁴"],["Principal angle",p.theta*180/pi,"°"],["SC offset x",c.xs,"mm"],["SC offset y",c.ys,"mm"]]),
                table("Applied shear flow",["Wall i → j","q start (N/mm)","q end (N/mm)","Peak |τ| (MPa)"],[["$(w.i) → $(w.j)",w.q_start,w.q_end,w.tau_max] for w in r.applied.walls])],
        checks=[metric("Force resultant residual",r.applied.resultant_residual,"N"),metric("Junction continuity residual",r.applied.continuity_residual,"N/mm")],
        notes=["All geometry describes wall centrelines in mm. Positive q follows the numbered wall i → j; Vx acts right and Vy acts up.","Shear-centre coordinates use the input frame; offsets are measured from the centroid. Closed cells and solid-section warping are outside this model."],
        shear=(nodes=[(;id=k,x=v[1],y=v[2]) for (k,v) in sort(collect(s.nodes);by=first)],centroid=(x=p.xc,y=p.yc),centre=(x=c.x,y=c.y),cases=cases))
    (;solverMethod="Open thin-wall tree integration · coupled shear flow",results,plots=Any[],warnings,meshElements=length(s.segments),signConvention="Vx right, Vy up; q positive i → j; Mz = xs·Vy − ys·Vx.")
end

function buckling(d)
    fields(d,["schemaVersion","type","projectName","section","b","h","tw","tf","diameter","length","E","yieldStress","support","axis","elements","material","hardeningRatio","exponent"])
    shape=choice(d,"section",["rectangle","circle","i"])
    support=Symbol(choice(d,"support",["pinned_pinned","fixed_free","fixed_pinned","fixed_fixed"]))
    axis=choice(d,"axis",["weak","x","y"])
    L=number(d,"length";positive=true,hi=1e4)*1000
    E=number(d,"E";positive=true,hi=1e4)*1000
    sy=number(d,"yieldStress";positive=true,hi=1e5)
    n=Int(number(d,"elements";lo=4,hi=100,integer=true))
    b,h,tw,tf,D=[number(d,k;positive=true,hi=1e5) for k in ("b","h","tw","tf","diameter")]
    s = if shape=="circle"
        BucklingCore.section_properties(D)
    elseif shape=="rectangle"
        BucklingCore.section_properties([BucklingCore.RectPart(b,h,0,0)];name="Rectangle")
    else
        2tf<h && tw<b || throw(ArgumentError("I-section requires 2 × flange thickness < depth and web thickness < width."))
        BucklingCore.section_properties([BucklingCore.RectPart(b,tf,0,0),BucklingCore.RectPart(tw,h-2tf,(b-tw)/2,tf),BucklingCore.RectPart(b,tf,0,h-tf)];name="I-section")
    end
    selected=axis=="weak" ? (s.Ix<=s.Iy ? "x" : "y") : axis
    I=selected=="x" ? s.Ix : s.Iy
    r=BucklingCore.solve_eigen(E*I,L,n,support)
    K=Dict(:pinned_pinned=>1.,:fixed_free=>2.,:fixed_pinned=>pi/4.493409457909064,:fixed_fixed=>0.5)[support]
    radius=sqrt(I/s.A); slenderness=K*L/radius; euler=pi^2*E*I/(K*L)^2
    material=Symbol(choice(d,"material",["elastic","epp","bilinear","ramberg_osgood"]))
    ratio=number(d,"hardeningRatio";lo=0,hi=0.99); exponent=number(d,"exponent";lo=1.01,hi=30)
    m=BucklingCore.Material(E,sy;model=material,ratio=ratio,exponent=exponent)
    tangent=BucklingCore.tangent_buckling(m,slenderness)
    xs=Float64[]; ws=Float64[]
    for e in 1:n, t in range(0,1,length=9)
        push!(xs,(e-1+t)*L/n/1000);push!(ws,dot(BucklingCore.hermite(t,L/n)[1],r.mode[2*e-1:2*e+2]))
    end
    residual=norm((r.K*r.mode-r.Pcr*r.G*r.mode)[r.free])/max(norm((r.K*r.mode)[r.free]),eps())
    lengths=collect(range(d["length"]/4,2d["length"],length=81))
    warnings=String[]
    r.Pcr/s.A>sy && push!(warnings,"Elastic critical stress exceeds yield stress. The Euler eigenvalue is an elastic reference, not a usable strength prediction.")
    results=(metrics=[metric("Elastic critical load",r.Pcr/1000,"kN"),metric("Elastic critical stress",r.Pcr/s.A,"MPa"),metric("Slenderness KL/r",slenderness,""),metric("Tangent-model load",tangent.stress*s.A/1000,"kN")],
        tables=[table("Column properties",["Property","Value","Unit"],[["Selected bending axis",selected,""],["Area",s.A,"mm²"],["Ixx",s.Ix,"mm⁴"],["Iyy",s.Iy,"mm⁴"],["Radius of gyration",radius,"mm"],["Effective-length factor K",K,""],["Effective length",K*L/1000,"m"],["Euler reference",euler/1000,"kN"],["Axial yield load",sy*s.A/1000,"kN"],["Tangent status",string(tangent.status),""]])],
        checks=[metric("Relative eigen residual",residual,""),metric("Difference from Euler",abs(r.Pcr/euler-1)*100,"%")],
        notes=["Perfect, prismatic column under uniform axial compression. Mode shape is normalized to unit amplitude; it is not a displacement prediction.","The length sweep is the elastic Euler reference. The tangent-modulus estimate uses the selected constitutive model; nonlinear imperfection paths and design-code resistance are not included."],
        buckling=(x=xs,mode=ws,axis=selected))
    plots=[plot("mode","First buckling mode","normalized",xs,ws,"#d97706";xLabel="Position along column (m)"),
           plot("length","Elastic critical load vs length","kN",lengths,[pi^2*E*I/(K*l*1000)^2/1000 for l in lengths],"#2563eb";xLabel="Column length (m)")]
    (;solverMethod="Elastic geometric-stiffness eigenproblem + tangent-modulus reference",results,plots,warnings,meshElements=n,signConvention="Positive axial load denotes compression; eigenmode amplitude is normalized.")
end

function arch(d)
    fields(d,["schemaVersion","type","projectName","geometry","length","rise","support","hinge","E","A","I","axial","loads"])
    shape=Symbol(choice(d,"geometry",["parabolic","circular"]))
    support=Symbol(choice(d,"support",["three_hinged","two_hinged","fixed"]))
    L=number(d,"length";positive=true,hi=1e4); rise=number(d,"rise";positive=true,hi=1e4)
    E=number(d,"E";positive=true,hi=1e4)*1e9; A=number(d,"A";positive=true,hi=1e10)*1e-6; I=number(d,"I";positive=true,hi=1e16)*1e-12
    hinge=number(d,"hinge")
    support==:three_hinged || (hinge=L/2)
    axial=get(d,"axial",nothing); axial isa Bool || throw(ArgumentError("axial must be true or false."))
    items=get(d,"loads",nothing); items isa AbstractVector && length(items)<=24 || throw(ArgumentError("Use at most 24 arch loads."))
    loads=ArchAnalysis.Load[]
    for l in items
        l isa AbstractDict || throw(ArgumentError("Each load must be an object."))
        kind=choice(l,"type",["point","udl","uvl","moment"])
        if kind=="point"
            fields(l,["id","type","x","fx","fy"])
            push!(loads,ArchAnalysis.PointForce(number(l,"x";lo=0,hi=L),1000number(l,"fx";lo=-1e8,hi=1e8),1000number(l,"fy";lo=-1e8,hi=1e8)))
        elseif kind=="moment"
            fields(l,["id","type","x","moment"])
            push!(loads,ArchAnalysis.Couple(number(l,"x";lo=0,hi=L),1000number(l,"moment";lo=-1e8,hi=1e8)))
        else
            fields(l,kind=="udl" ? ["id","type","start","end","qx","qy"] : ["id","type","start","end","qx","qy","qxEnd","qyEnd"])
            a=number(l,"start";lo=0,hi=L); b=number(l,"end";lo=0,hi=L)
            qx=1000number(l,"qx";lo=-1e8,hi=1e8); qy=1000number(l,"qy";lo=-1e8,hi=1e8)
            qxb=kind=="uvl" ? 1000number(l,"qxEnd";lo=-1e8,hi=1e8) : qx
            qyb=kind=="uvl" ? 1000number(l,"qyEnd";lo=-1e8,hi=1e8) : qy
            push!(loads,ArchAnalysis.LineLoad(a,b,qx,qy,qxb,qyb))
        end
    end
    g=ArchAnalysis.Geometry(shape,L,rise)
    m=ArchAnalysis.Model(g,support,[ArchAnalysis.Section(0.,L,E,A,I)],loads;axial,hinge)
    s=ArchAnalysis.solve_force(m); v=ArchAnalysis.force_samples(s;points_per_interval=41)
    eq=ArchAnalysis.equilibrium(s)
    plots=[plot("moment","Bending moment","kN·m",v.x,v.M/1000,"#2563eb"),plot("shear","Local shear force","kN",v.x,v.Q/1000,"#0d9488"),plot("axial","Axial force · tension positive","kN",v.x,v.N/1000,"#7c3aed"),plot("vertical","Vertical displacement","mm",v.x,v.v*1000,"#d97706"),plot("horizontal","Horizontal displacement","mm",v.x,v.u*1000,"#0284c7"),plot("rotation","Section rotation","rad",v.x,v.theta,"#db2777")]
    results=(metrics=[metric("Left horizontal thrust",s.reactions[1]/1000,"kN"),metric("Peak sampled |M|",maximum(abs,v.M)/1000,"kN·m"),metric("Peak sampled |N|",maximum(abs,v.N)/1000,"kN"),metric("Peak sampled |v|",maximum(abs,v.v)*1000,"mm")],
        tables=[table("Support reactions",["Support","Horizontal (kN)","Vertical (kN)","Moment (kN·m)"],[["A",s.reactions[1:3]./1000...],["B",s.reactions[4:6]./1000...]]),
                table("Sampled response",["x (m)","M (kN·m)","Q (kN)","N (kN)","u (mm)","v (mm)","θ (rad)"],[[v.x[i],v.M[i]/1000,v.Q[i]/1000,v.N[i]/1000,v.u[i]*1000,v.v[i]*1000,v.theta[i]] for i in eachindex(v.x)])],
        checks=[metric("Horizontal equilibrium residual",eq[1],"N"),metric("Vertical equilibrium residual",eq[2],"N"),metric("Moment equilibrium residual",eq[3],"N·m"),metric("Flexibility compatibility residual",isempty(s.D) ? 0. : norm(s.F*s.X+s.D),"SI")],
        notes=["Fx right, Fy up, external moments counterclockwise; internal axial force is tension positive and bending moment sagging positive. Distributed loads are per horizontal projected metre.","Linear elastic force method with $(axial ? "axial and bending" : "bending-only") deformation. Displayed peaks are sampled estimates. Repeated positions retain the two sides of a load or hinge."],
        arch=(x=v.x,y=ArchAnalysis.ordinate.(Ref(g),v.x),u=v.u,v=v.v))
    (;solverMethod="Curved-member flexibility / force method",results,plots,warnings=String[],meshElements=length(ArchAnalysis.breakpoints(m))-1,signConvention="Right/up/counterclockwise positive; N tension positive, M sagging positive.")
end
end
