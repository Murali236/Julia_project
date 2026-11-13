# Optional JSON dependency is loaded only for file input/output.
function load_section_json(path::AbstractString)
    @eval import JSON
    data = Base.invokelatest(() -> JSON.parsefile(path; dicttype=Dict{String,Any}))
    section = Section(data["nodes"], data["segments"];
        E=get(data,"E",nothing), G=get(data,"G",nothing), name=get(data,"name","Custom section"))
    return section, Float64(get(data,"Vx",0.0)), Float64(get(data,"Vy",1.0))
end

function case_dictionary(c)
    Dict("Vx"=>c.Vx, "Vy"=>c.Vy, "principal_shear"=>c.principal_shear,
        "resultant"=>[c.Fx,c.Fy], "moment_about_centroid"=>c.Mz,
        "max_abs_tau"=>c.tau_max, "resultant_residual"=>c.resultant_residual,
        "continuity_residual"=>c.continuity_residual,
        "segments"=>[Dict("node_i"=>w.i, "node_j"=>w.j, "t"=>w.t,
            "L"=>w.L, "q_coefficients"=>collect(w.coefficients),
            "q_start"=>w.q_start, "q_mid"=>w.q_mid, "q_end"=>w.q_end,
            "tau_start"=>w.q_start/w.t, "tau_mid"=>w.q_mid/w.t,
            "tau_end"=>w.q_end/w.t, "max_abs_tau"=>w.tau_max) for w in c.walls])
end

function save_results_json(path::AbstractString, r; validation=validation_report())
    @eval import JSON
    p, c = r.properties, r.centre
    data = Dict(
        "model"=>"Phase 1 open thin-wall centreline; homogeneous linear elastic",
        "units"=>Dict("length"=>"mm","area"=>"mm^2","inertia"=>"mm^4",
                      "force"=>"N","q"=>"N/mm","tau"=>"N/mm^2","theta"=>"rad"),
        "sign_convention"=>"q positive node_i -> node_j; Mz = xs*Vy - ys*Vx",
        "section"=>Dict("name"=>r.section.name,
            "nodes"=>Dict(string(k)=>collect(v) for (k,v) in r.section.nodes),
            "segments"=>[[s.i,s.j,s.t] for s in r.section.segments],
            "E"=>r.section.E,"G"=>r.section.G),
        "properties"=>Dict(string(k)=>getproperty(p,k) for k in
            (:A,:xc,:yc,:Ixx,:Iyy,:Ixy,:D,:I1,:I2,:theta)),
        "principal_rotation"=>[collect(p.rotation[i,:]) for i in 1:2],
        "shear_centre"=>Dict("relative"=>[c.xs,c.ys],"absolute"=>[c.x,c.y],"distance"=>c.distance),
        "load_cases"=>Dict("unit_Vy"=>case_dictionary(r.unit_y),
                           "unit_Vx"=>case_dictionary(r.unit_x),
                           "applied"=>case_dictionary(r.applied)),
        "validation"=>Dict(validation))
    open(path,"w") do io
        print(io, Base.invokelatest(() -> JSON.json(data)))
        println(io)
    end
    return path
end
