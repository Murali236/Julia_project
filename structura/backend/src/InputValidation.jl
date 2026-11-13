module InputValidation
using ..UnitConversion
export validate_beam, number, fields
function fields(d, allowed, required=String[])
    d isa AbstractDict || throw(ArgumentError("Expected a JSON object."))
    all(k->k in allowed,keys(d)) || throw(ArgumentError("Unknown input field. Check the version 1 API schema."))
    all(k->haskey(d,k),required) || throw(ArgumentError("Missing required input field."))
end
function number(d,key; default=nothing)
    v=get(d,key,default)
    v isa Real && !(v isa Bool) && isfinite(v) || throw(ArgumentError("$key must be a finite number."))
    Float64(v)
end
function array(d,key; limit=32)
    a=get(d,key,Any[])
    a isa AbstractVector && length(a)<=limit || throw(ArgumentError("$key must be an array with at most $limit entries."))
    a
end
function validate_beam(d)
    fields(d,["schemaVersion","projectName","length","E","I","units","supports","loads","nodes","sections","evaluationPoints"],
             ["schemaVersion","projectName","length","E","I","units","supports","loads"])
    get(d,"schemaVersion",0)===1 || throw(ArgumentError("Only schemaVersion 1 is supported."))
    name=d["projectName"]
    name isa AbstractString && 1<=length(strip(name))<=120 || throw(ArgumentError("Project name must contain 1–120 characters."))
    fields(d["units"],["length","force","modulus","inertia"],["length","force","modulus","inertia"])
    u=scales(d["units"])
    L=number(d,"length")*u.length; E=number(d,"E")*u.modulus; I=number(d,"I")*u.inertia
    0.001<=L<=1000 || throw(ArgumentError("Beam length must be between 0.001 and 1000 m."))
    1e6<=E<=1e13 && 1e-14<=I<=1e3 || throw(ArgumentError("E or I is outside the supported finite range."))
    location(x)=begin
        x isa Real && !(x isa Bool) && isfinite(x) && 0<=x*u.length<=L || throw(ArgumentError("All coordinates must lie within the beam."))
        Float64(x)*u.length
    end
    rawsupports=array(d,"supports";limit=16)
    isempty(rawsupports) && throw(ArgumentError("Add at least one restraining support."))
    support_x=Float64[]; supports=NamedTuple[]
    for s in rawsupports
        fields(s,["id","type","x","stiffness","settlement"],["type","x"])
        t=s["type"]; t in ("pin","roller","fixed","spring") || throw(ArgumentError("Unsupported support type."))
        x=location(number(s,"x")); push!(support_x,x)
        k=number(s,"stiffness";default=100000.0)
        t=="spring" && !(0<k<=1e15) && throw(ArgumentError("Spring stiffness must be positive, at most 1e15 N/m."))
        settlement=number(s,"settlement";default=0.0)*u.length
        abs(settlement)<=L || throw(ArgumentError("Settlement magnitude cannot exceed beam length."))
        push!(supports,(Node=length(supports)+1,Type=t,Stiffness=k,Settlement=settlement))
    end
    length(unique(support_x))==length(support_x) || throw(ArgumentError("Support coordinates must be distinct."))
    xs=copy(support_x)
    for x in array(d,"nodes";limit=32)
        p=location(x); p in xs || push!(xs,p)
    end
    nodes=[(ID=i,x=x) for (i,x) in enumerate(xs)]
    loads=NamedTuple[]
    for load in array(d,"loads";limit=32)
        t=get(load,"type","")
        if t in ("point","moment")
            fields(load,["id","type","magnitude","x"],["type","magnitude","x"])
            magnitude=number(load,"magnitude")*u.force*(t=="moment" ? u.length : 1.0)/1000
            abs(magnitude)<=1e9 || throw(ArgumentError("Load magnitude exceeds the supported range."))
            push!(loads,(Type=t=="point" ? "Point Load" : "Moment",Magnitude=magnitude,Location=location(number(load,"x"))))
        elseif t in ("udl","uvl")
            fields(load,t=="uvl" ? ["id","type","magnitude","start","end","endMagnitude"] : ["id","type","magnitude","start","end"],
                   t=="uvl" ? ["type","magnitude","start","end","endMagnitude"] : ["type","magnitude","start","end"])
            a=location(number(load,"start")); b=location(number(load,"end"))
            a<b || throw(ArgumentError("A distributed load must have start < end."))
            w=number(load,"magnitude")*u.force/u.length/1000
            w2=number(load,"endMagnitude";default=load["magnitude"])*u.force/u.length/1000
            max(abs(w),abs(w2))<=1e9 || throw(ArgumentError("Load intensity exceeds the supported range."))
            push!(loads,t=="udl" ? (Type="UDL",Start=a,End=b,Intensity=w) : (Type="UVL",Start=a,End=b,StartIntensity=w,EndIntensity=w2))
        else
            throw(ArgumentError("Use point, moment, udl or uvl loads. Inclined forces are not supported by the bending solver."))
        end
    end
    sections=NamedTuple[]
    for s in array(d,"sections";limit=16)
        fields(s,["start","end","E","I"],["start","end","E","I"])
        se=number(s,"E")*u.modulus; si=number(s,"I")*u.inertia
        1e6<=se<=1e13 && 1e-14<=si<=1e3 || throw(ArgumentError("Section E or I is outside the supported range."))
        push!(sections,(Start=location(number(s,"start")),End=location(number(s,"end")),E=se,I=si))
    end
    isempty(sections) && push!(sections,(Start=0.0,End=L,E=E,I=I))
    evaluation=location.(array(d,"evaluationPoints";limit=50))
    return (;L,E,I,nodes,supports,loads,sections,evaluation)
end
end
