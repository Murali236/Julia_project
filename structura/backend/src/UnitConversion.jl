module UnitConversion
export scales
function scales(units)
    units isa AbstractDict || throw(ArgumentError("units must be an object."))
    choices = ("length"=>Dict("m"=>1.0,"mm"=>0.001), "force"=>Dict("kN"=>1000.0,"N"=>1.0),
               "modulus"=>Dict("GPa"=>1e9,"Pa"=>1.0), "inertia"=>Dict("mm4"=>1e-12,"m4"=>1.0))
    values = Float64[]
    for (key, options) in choices
        value = get(units,key,"")
        haskey(options,value) || throw(ArgumentError("Unsupported $key unit."))
        push!(values,options[value])
    end
    return (length=values[1],force=values[2],modulus=values[3],inertia=values[4])
end
end
