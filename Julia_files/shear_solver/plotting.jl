"""Save geometry and three signed shear-flow diagrams as PNGs (optional Plots.jl)."""
function save_plots(r, directory::AbstractString)
    @eval import Plots
    return Base.invokelatest(_save_plots, r, directory)
end

function _save_plots(r, directory)
    mkpath(directory)
    nodes, p, c = r.section.nodes, r.properties, r.centre
    span = max(maximum(x[1] for x in values(nodes))-minimum(x[1] for x in values(nodes)),
               maximum(x[2] for x in values(nodes))-minimum(x[2] for x in values(nodes)))
    tmax = maximum(s.t for s in r.section.segments)
    function geometry(title)
        fig = Plots.plot(; aspect_ratio=:equal, xlabel="x (mm)", ylabel="y (mm)",
                         title, legend=:outertopright, size=(1100,750), margin=8Plots.mm)
        for (k,s) in enumerate(r.section.segments)
            a,b = nodes[s.i],nodes[s.j]
            Plots.plot!(fig, [a[1],b[1]],[a[2],b[2]];
                        color=:gray, linewidth=2+6s.t/tmax, label="Wall $k: t=$(s.t) mm")
            Plots.annotate!(fig,(a[1]+b[1])/2+.045span,(a[2]+b[2])/2+.06span,
                            Plots.text(string(k),10,:black))
        end
        Plots.scatter!(fig,[p.xc],[p.yc]; marker=:+,markersize=10,color=:black,label="Centroid")
        Plots.scatter!(fig,[c.x],[c.y]; marker=:x,markersize=9,color=:red,label="Shear centre")
        return fig
    end
    files = String[]
    fig = geometry("$(r.section.name): centreline geometry")
    path = joinpath(directory,"section.png")
    Plots.savefig(fig,path); push!(files,path)
    for (name,case) in [("unit_Vy",r.unit_y),("unit_Vx",r.unit_x),("applied",r.applied)]
        qmax = maximum(w.tau_max*w.t for w in case.walls)
        scale = qmax == 0 ? 0.0 : 0.18span/qmax
        fig = geometry("$name: Vx=$(case.Vx) N, Vy=$(case.Vy) N\nSigned q(s), peak |q|=$(round(qmax,sigdigits=5)) N/mm")
        for (k,w) in enumerate(case.walls)
            a,b = nodes[w.i],nodes[w.j]
            ux,uy = (b .- a) ./ w.L
            ss = range(0,w.L;length=61)
            qs = [flow_at(w,s) for s in ss]
            xx = [a[1]+s*ux-scale*q*uy for (s,q) in zip(ss,qs)]
            yy = [a[2]+s*uy+scale*q*ux for (s,q) in zip(ss,qs)]
            Plots.plot!(fig,xx,yy;color=:royalblue,linewidth=2,label=k==1 ? "q, normal offset" : "")
            for f in (0.2,0.5,0.8)
                s=f*w.L; q=flow_at(w,s)
                x,y=a[1]+s*ux,a[2]+s*uy
                Plots.plot!(fig,[x,x-scale*q*uy],[y,y+scale*q*ux];color=:royalblue,alpha=.45,label="")
                if abs(q) > 1e-10*qmax
                    length_arrow=min(.075span,.2w.L)*sign(q)
                    Plots.quiver!(fig,[x],[y];quiver=([length_arrow*ux],[length_arrow*uy]),
                                  color=:darkgreen,label="")
                end
            end
        end
        path=joinpath(directory,"shear_flow_$name.png")
        Plots.savefig(fig,path); push!(files,path)
    end
    return files
end
