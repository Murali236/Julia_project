module BucklingPlots
using Plots
using ..BucklingCore
export save_extended_plots
function save_extended_plots(c, path, elastic_path, material, slenderness; directory=pwd())
    λc=π*sqrt(material.E/material.sy)
    λ=range(max(1.0,min(slenderness,λc)/4),max(200.0,2slenderness,2λc),length=500)
    p=plot(λ,[π^2*material.E/x^2/1e6 for x in λ];label="Euler",xlabel="Slenderness λ",ylabel="Critical stress (MPa)",ylim=(0,1.5material.sy/1e6),lw=2)
    plot!(p,λ,[tangent_buckling(material,x).stress/1e6 for x in λ];label="Tangent modulus",lw=2)
    hline!(p,[material.sy/1e6];label="Yield / proof stress",ls=:dash)
    vline!(p,[λc];label="Euler validity λc",ls=:dot)
    scatter!(p,[slenderness],[tangent_buckling(material,slenderness).stress/1e6];label="Current column")
    savefig(p,joinpath(directory,"inelastic_stress_vs_slenderness.png"))
    isnothing(path) && return
    p=plot([r.mid*1000 for r in path.points],[r.P/1000 for r in path.points];label="Inelastic equilibrium",lw=2,xlabel="Total midspan deflection (mm)",ylabel="Axial load (kN)")
    plot!(p,[r.mid*1000 for r in elastic_path.points],[r.P/1000 for r in elastic_path.points];label="Elastic imperfect column",lw=2,ls=:dash)
    if isfinite(path.critical)
        j=argmax([r.P for r in path.points])
        scatter!(p,[path.points[j].mid*1000],[path.points[j].P/1000];label="Sampled peak")
    end
    mids=[r.mid*1000 for r in path.points]
    span=max(maximum(mids)-minimum(mids),1.0)
    xlims!(p,min(0.0,minimum(mids)-.05span),maximum(mids)+.1span)
    savefig(p,joinpath(directory,"load_vs_midspan_deflection.png"))
    last=path.points[end]; shape=sample_shape(c,last.q)
    p=plot(shape.x,shape.w*1000;label="Final equilibrium shape",lw=2,xlabel="Column coordinate (m)",ylabel="Total deflection (mm)",legend=:bottomright)
    # Highlight each integration station containing plastic fibers, not whole elements.
    xp=Float64[]; wp=Float64[]; fraction=Float64[]
    for e in 1:c.n, g in 1:4
        if last.yielded[e,g]>0
            ξ=BucklingCore.GAUSS_X[g]
            push!(xp,(e-1+ξ)*c.L/c.n)
            push!(wp,1000*sum(hermite(ξ,c.L/c.n)[1].*(last.q+c.imperfection)[2*e-1:2*e+2]))
            push!(fraction,last.yielded[e,g])
        end
    end
    if !isempty(xp)
        scatter!(p,xp,wp;marker_z=fraction,clim=(0,1),color=:inferno,label="Plastic stations",colorbar_title="Plastic area fraction")
    end
    savefig(p,joinpath(directory,"final_deflected_shape.png"))
end
end
