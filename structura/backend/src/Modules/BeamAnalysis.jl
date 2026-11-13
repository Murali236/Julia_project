module BeamAnalysis
using ..InputValidation
include("../Legacy/beam_stiffness.jl")
using .BeamStiffness
export analyze
function analyze(input)
    m=validate_beam(input)
    s=solve_beam(m.L,m.nodes,m.supports,m.loads;E=m.E,I=m.I,sections=m.sections)
    samples=sample_beam(s;points_per_element=61)
    checks=beam_checks(s)
    checks.passed || error("The beam solution did not pass its numerical verification.")
    series=[(key="shear",label="Shear force",unit="kN",values=samples.V,color="#3566de"),
            (key="moment",label="Bending moment",unit="kN·m",values=samples.M,color="#7857ce"),
            (key="deflection",label="Deflection",unit="mm",values=samples.v_mm,color="#12958b"),
            (key="slope",label="Slope",unit="rad",values=samples.theta,color="#d28b31")]
    plots=[(;p...,x=samples.x) for p in series]
    extrema=[(key=p.key,label=p.label,unit=p.unit,
              minimum=(value=minimum(p.values),x=samples.x[argmin(p.values)]),
              maximum=(value=maximum(p.values),x=samples.x[argmax(p.values)]),
              absolute=(value=p.values[argmax(abs.(p.values))],x=samples.x[argmax(abs.(p.values))])) for p in series]
    evaluation=NamedTuple[]
    for x in m.evaluation
        # Both one-sided values are returned at discontinuities.
        found=findall(e->e.Start<=x<=e.End,s.elements)
        for j in found
            e=s.elements[j]; r=element_response(e,x-e.Start)
            push!(evaluation,(x=x,side=length(found)==1 ? "interior" : (j==first(found) ? "left" : "right"),
                              shear=r.V/1000,moment=r.M/1000,deflection=r.v*1000,slope=r.theta))
        end
    end
    reactions=[(node=r.Node,x=r.x,type=r.Type,vertical=r.Vertical/1000,moment=r.Moment/1000) for r in s.reactions]
    elements=[(start=e.Start,stop=e.End,EI=e.EI,V1=e.forces[1],M1=e.forces[2],w0=e.w0,gradient=e.gradient,
               v1=e.d[1],theta1=e.d[2],endForces=e.forces) for e in s.elements]
    nodal=[(x=x,deflection=1000s.d[2i-1],slope=s.d[2i]) for (i,x) in enumerate(s.x)]
    return (results=(extrema=extrema,reactions=reactions,evaluation=evaluation,nodal=nodal,elements=elements,
                     checks=checks,equations=equation_summary(s),zeroShear=samples.zero_shear),plots=plots,
            warnings=["Linear elastic Euler–Bernoulli bending; shear deformation, axial response, yielding, and geometric nonlinearity are excluded.",
                      "Educational and research use. Independent professional verification is required for design."],
            solverMethod="Euler–Bernoulli direct stiffness with exact polynomial element recovery",
            meshElements=length(s.elements))
end
end
