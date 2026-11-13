module BucklingCore
using LinearAlgebra, SparseArrays, Printf
export RectPart, composite_properties, Section, section_properties
struct RectPart
    b::Float64
    h::Float64
    x::Float64
    y::Float64
end


# ================================================================
# COMPOSITE SECTION CALCULATION
#
# Calculates:
#
# Area
# Centroid
# Ix
# Iy
#
# using parallel-axis theorem.
#
# ================================================================

function composite_properties(parts)

    # ------------------------------------------------
    # Total area
    # ------------------------------------------------

    areas = [p.b * p.h for p in parts]

    A = sum(areas)


    # ------------------------------------------------
    # Centroid of each rectangle
    # ------------------------------------------------

    xc = [p.x + p.b / 2 for p in parts]
    yc = [p.y + p.h / 2 for p in parts]


    # ------------------------------------------------
    # Composite centroid
    # ------------------------------------------------

    xbar = sum(areas .* xc) / A
    ybar = sum(areas .* yc) / A


    # ------------------------------------------------
    # Moments of inertia
    # ------------------------------------------------

    Ix = 0.0
    Iy = 0.0

    for i in eachindex(parts)

        p = parts[i]

        Ai = areas[i]

        # Local rectangle inertia

        Ix_local = p.b * p.h^3 / 12

        Iy_local = p.h * p.b^3 / 12


        # Distance from composite centroid

        dx = xc[i] - xbar
        dy = yc[i] - ybar


        # Parallel axis theorem

        Ix += Ix_local + Ai * dy^2

        Iy += Iy_local + Ai * dx^2
    end


    return A, xbar, ybar, Ix, Iy
end



struct Section
    name::String
    parts::Vector{RectPart}
    diameter::Float64
    A::Float64
    xbar::Float64
    ybar::Float64
    Ix::Float64
    Iy::Float64
end
function section_properties(parts::Vector{RectPart}; name="Composite")
    isempty(parts) && throw(ArgumentError("At least one rectangle is required"))
    all(p -> all(isfinite, (p.b,p.h,p.x,p.y)) && p.b > 0 && p.h > 0, parts) || throw(ArgumentError("Invalid rectangle"))
    return Section(name, parts, 0.0, composite_properties(parts)...)
end
function section_properties(D::Real; name="Circle")
    isfinite(D) && D > 0 || throw(ArgumentError("Diameter must be positive and finite"))
    return Section(name, RectPart[], D, π*D^2/4, D/2, D/2, π*D^4/64, π*D^4/64)
end
export assemble_elastic, assemble_geometric, solve_eigen, bending_free_dofs, hermite

function check_column(EI, L, n)
    isfinite(EI) && EI > 0 && isfinite(L) && L > 0 && n >= 2 ||
        throw(ArgumentError("Positive finite EI, L and at least two elements required"))
end
# Cubic Hermite interpolation, its slope and its curvature at ξ=x/le.
function hermite(ξ, le)
    H = [1-3ξ^2+2ξ^3, le*(ξ-2ξ^2+ξ^3), 3ξ^2-2ξ^3, le*(-ξ^2+ξ^3)]
    B = [(-6ξ+6ξ^2)/le, 1-4ξ+3ξ^2, (6ξ-6ξ^2)/le, -2ξ+3ξ^2]
    C = [(-6+12ξ)/le^2, (-4+6ξ)/le, (6-12ξ)/le^2, (-2+6ξ)/le]
    return H,B,C
end
function assemble_elastic(EI::Real, L::Real, n::Integer)
    check_column(EI,L,n)
    l = L/n
    # Elastic bending energy Hessian for [w1, θ1, w2, θ2].
    ke = EI/l^3 * [12 6l -12 6l; 6l 4l^2 -6l 2l^2; -12 -6l 12 -6l; 6l 2l^2 -6l 4l^2]
    K = spzeros(2(n+1),2(n+1))
    for e in 1:n
        d = (2*e-1):(2*e+2)
        K[d,d] += ke
    end
    return K
end
function assemble_geometric(Pref::Real, L::Real, n::Integer)
    check_column(Pref,L,n)
    l = L/n
    # Positive reference compression matrix: tangent is K - λ*G.
    ge = Pref/(30l) * [36 3l -36 3l; 3l 4l^2 -3l -l^2; -36 -3l 36 -3l; 3l -l^2 -3l 4l^2]
    G = spzeros(2(n+1),2(n+1))
    for e in 1:n
        d = (2*e-1):(2*e+2)
        G[d,d] += ge
    end
    return G
end
function bending_free_dofs(n, support::Symbol)
    lastw = 2n+1
    fixed = support == :pinned_pinned ? [1,lastw] :
            support == :fixed_free ? [1,2] :
            support == :fixed_pinned ? [1,2,lastw] :
            support == :fixed_fixed ? [1,2,lastw,lastw+1] :
            throw(ArgumentError("FEM requires explicit support restraints, not an effective-length factor"))
    return setdiff(1:2(n+1),fixed)
end
function solve_eigen(EI, L, n, support; Pref=1.0)
    K,G = assemble_elastic(EI,L,n),assemble_geometric(Pref,L,n)
    free = bending_free_dofs(n,support)
    eig = eigen(Symmetric(Matrix(K[free,free])),Symmetric(Matrix(G[free,free])))
    j = findfirst(v -> isfinite(v) && v > 0, eig.values)
    isnothing(j) && error("No positive buckling eigenvalue")
    mode = zeros(2(n+1)); mode[free] = eig.vectors[:,j]
    # Normalize on a dense Hermite sample (including interior element extrema).
    vals = [dot(hermite(t,L/n)[1],mode[2*e-1:2*e+2]) for e in 1:n for t in range(0,1,length=21)]
    scale = vals[argmax(abs.(vals))]; mode ./= scale
    return (; Pcr=eig.values[j]*Pref, mode, K, G, free, L, n, support)
end

export Material, material_tangent, tangent_buckling, Fiber, fiber_mesh, FiberState, section_response
struct Material
    E::Float64
    sy::Float64
    model::Symbol
    ratio::Float64
    exponent::Float64
    offset::Float64
    function Material(E,sy; model=:epp, ratio=0.01, exponent=6.0, offset=0.002)
        all(isfinite,(E,sy,ratio,exponent,offset)) && E>0 && sy>0 && 0<=ratio<1 && exponent>1 && offset>0 || throw(ArgumentError("Invalid material parameters"))
        model in (:elastic,:epp,:bilinear,:ramberg_osgood) || throw(ArgumentError("Unknown material model"))
        new(E,sy,model,ratio,exponent,offset)
    end
end
# Monotonic dσ/dε. RO: ε=σ/E + offset*(σ/sy)^exponent, for σ≥0.
function material_tangent(m::Material, σ::Real)
    m.model == :elastic && return m.E
    m.model == :ramberg_osgood && return inv(1/m.E+m.offset*m.exponent/m.sy*(abs(σ)/m.sy)^(m.exponent-1))
    abs(σ) < m.sy && return m.E
    return m.model == :epp ? 0.0 : m.ratio*m.E
end
function tangent_buckling(m::Material, slenderness::Real)
    isfinite(slenderness) && slenderness>0 || throw(ArgumentError("Slenderness must be positive and finite"))
    euler = π^2*m.E/slenderness^2
    m.model == :elastic && return (;stress=euler,status=:elastic)
    if m.model != :ramberg_osgood
        euler <= m.sy && return (;stress=euler,status=:elastic)
        # A discontinuous tangent may skip the implicit root. The first loss of
        # stability is then the yield corner, not a fabricated smooth root.
        hard = m.model == :epp ? 0.0 : euler*m.ratio
        return (;stress=max(m.sy,hard),status=hard>m.sy ? :hardening_root : :yield_corner)
    end
    lo,hi = 0.0,euler
    for _ in 1:100
        mid=(lo+hi)/2
        f=mid-π^2*material_tangent(m,mid)/slenderness^2
        f>0 ? (hi=mid) : (lo=mid)
    end
    return (;stress=(lo+hi)/2,status=:smooth_root)
end
struct Fiber
    area::Float64
    y::Float64 # signed distance normal to the selected centroidal bending axis
end
function fiber_mesh(s::Section, axis::Symbol; layers=24, sectors=64)
    axis in (:x,:y) || throw(ArgumentError("Axis must be :x or :y"))
    layers>=2 && sectors>=8 || throw(ArgumentError("Insufficient fiber resolution"))
    f=Fiber[]
    if s.diameter>0
        # Equal intervals in r², two-point Gauss in r² and uniform azimuth.
        # Area and second moment are exact for elastic circular sections.
        R=s.diameter/2
        for j in 1:layers, g in (-inv(sqrt(3)),inv(sqrt(3))), k in 1:sectors
            r=R*sqrt((j-0.5+g/2)/layers)
            push!(f,Fiber(π*R^2/(2layers*sectors),r*cos(2π*(k-0.5)/sectors)))
        end
    else
        # Two-point Gauss fibers in each layer integrate elastic I exactly.
        for p in s.parts
            h=axis==:x ? p.h : p.b
            b=axis==:x ? p.b : p.h
            origin=axis==:x ? p.y-s.ybar : p.x-s.xbar
            for j in 1:layers, g in (-inv(sqrt(3)),inv(sqrt(3)))
                push!(f,Fiber(b*h/(2layers),origin+h*(j-0.5+g/2)/layers))
            end
        end
    end
    return f
end
struct FiberState
    plastic::Float64
    accumulated::Float64
end
FiberState()=FiberState(0.0,0.0)
# Return mapping from the last COMMITTED state; trials never mutate history.
function material_response(m::Material, ε, old::FiberState, residual=0.0)
    trial=m.E*(ε-old.plastic)+residual
    m.model==:elastic && return trial,m.E,old
    a=old.accumulated
    if m.model==:ramberg_osgood
        # Isotropic RO hardening: yield radius sy*(α/offset)^(1/n).
        yieldstress=m.sy*(a/m.offset)^(1/m.exponent)
    else
        H=m.model==:epp ? 0.0 : m.E*m.ratio/(1-m.ratio)
        yieldstress=m.sy+H*a
    end
    abs(trial)<=yieldstress && return trial,m.E,old
    if m.model==:ramberg_osgood
        # Solve in stress, avoiding the infinite hardening derivative at α=0.
        lo,hi=0.0,abs(trial)
        for _ in 1:60
            σ=(lo+hi)/2
            g=σ+m.E*max(0.0,m.offset*(σ/m.sy)^m.exponent-a)-abs(trial)
            g>0 ? (hi=σ) : (lo=σ)
        end
        σ=(lo+hi)/2
        dp=max(0.0,(abs(trial)-σ)/m.E)
        Et=material_tangent(m,σ)
    else
        dp=(abs(trial)-yieldstress)/(m.E+H)
        σ=abs(trial)-m.E*dp
        Et=m.E*H/(m.E+H)
    end
    signσ=sign(trial)
    return signσ*σ,Et,FiberState(old.plastic+signσ*dp,a+dp)
end
function section_response(fibers, m, ε0, κ, old; residual=zeros(length(fibers)))
    length(old)==length(fibers)==length(residual) || throw(DimensionMismatch("Fiber state count"))
    N=M=EA=ES=EI=0.0
    states=Vector{FiberState}(undef,length(fibers)); stress=zeros(length(fibers))
    for i in eachindex(fibers)
        f=fibers[i]
        # Plane sections: ε(y)=ε0+κ*y; N=ΣσA, M=ΣσAy.
        σ,Et,state=material_response(m,ε0+κ*f.y,old[i],residual[i])
        N+=σ*f.area; M+=σ*f.area*f.y
        EA+=Et*f.area; ES+=Et*f.area*f.y; EI+=Et*f.area*f.y^2
        states[i]=state; stress[i]=σ
    end
    return (;N,M,EA,ES,EI,states,stress,ε0)
end

export ColumnModel, newton_raphson_step, load_control, riks_solver, nonlinear_response, sample_shape, path_summary
const GAUSS_X = [(1-0.8611363115940526)/2,(1-0.3399810435848563)/2,(1+0.3399810435848563)/2,(1+0.8611363115940526)/2]
const GAUSS_W = [0.3478548451374538/2,0.6521451548625461/2,0.6521451548625461/2,0.3478548451374538/2]
struct ColumnModel
    section::Section
    material::Material
    fibers::Vector{Fiber}
    L::Float64
    n::Int
    support::Symbol
    free::Vector{Int}
    imperfection::Vector{Float64}
    residual::Vector{Float64}
    scale::Vector{Float64}
    Pscale::Float64
    K0::Matrix{Float64}
end
function ColumnModel(s,m,L,n,support; axis=:y,imperfection=L/1000,layers=24,residual_fraction=0.0,sectors=32)
    isfinite(imperfection) && imperfection>=0 || throw(ArgumentError("Imperfection must be finite and nonnegative"))
    isfinite(residual_fraction) && 0<=residual_fraction<1 || throw(ArgumentError("Residual fraction must be in [0,1)"))
    I=axis==:x ? s.Ix : s.Iy
    eig=solve_eigen(m.E*I,L,n,support)
    f=fiber_mesh(s,axis;layers,sectors)
    # First eigenmode is sinusoidal for pins and satisfies every other restraint.
    w0=imperfection*eig.mode
    ys=[x.y for x in f]; areas=[x.area for x in f]
    # Project a parabolic pattern onto zero section force AND zero section moment.
    raw=ys.^2; X=hcat(ones(length(f)),ys)
    raw-=X*((X'*(areas.*X))\(X'*(areas.*raw)))
    residual=residual_fraction*m.sy*raw/max(maximum(abs,raw),eps())
    scale=repeat([Float64(L),1.0],n+1)
    return ColumnModel(s,m,f,L,n,support,eig.free,w0,residual,scale,min(m.sy*s.A,eig.Pcr),Matrix(eig.K[eig.free,eig.free]))
end
function initial_states(c)
    # RO residual stresses start on their local hardening surface.
    fs=[FiberState(0.0,c.material.model==:ramberg_osgood ? c.material.offset*(abs(r)/c.material.sy)^c.material.exponent : 0.0) for r in c.residual]
    return [[copy(fs) for _ in GAUSS_X] for _ in 1:c.n]
end
# Static condensation of axial extension: solve N(ε0,κ)=-P at each section.
function force_section(c,P,κ,old;tol=1e-10)
    m=c.material; A=c.section.A
    ε0=-P/(m.E*A)-sum(f.area*f.y for f in c.fibers)/A*κ
    lo,hi=-Inf,Inf
    for _ in 1:100
        s=section_response(c.fibers,m,ε0,κ,old;residual=c.residual)
        r=s.N+P
        abs(r)<=tol*max(c.Pscale,abs(P)) && return s
        r>0 ? (hi=ε0) : (lo=ε0)
        trial=s.EA>m.E*A*1e-14 ? ε0-r/s.EA : ε0-sign(r)*max(abs(ε0),m.sy/m.E)
        if !(lo<trial<hi)
            trial=isfinite(lo)&&isfinite(hi) ? (lo+hi)/2 : ε0-sign(r)*max(abs(ε0),m.sy/m.E)
        end
        ε0=trial
    end
    return nothing
end
function nonlinear_response(c,q,P,committed)
    nd=length(q); F=zeros(nd); KT=zeros(nd,nd); dFdP=zeros(nd)
    states=Vector{Vector{Vector{FiberState}}}(undef,c.n)
    yielded=zeros(c.n,4); strains=zeros(c.n,4); axial=0.0
    le=c.L/c.n
    for e in 1:c.n
        d=(2*e-1):(2*e+2); qe=q[d]; q0=c.imperfection[d]
        states[e]=Vector{Vector{FiberState}}(undef,4)
        for g in 1:4
            _,B,C=hermite(GAUSS_X[g],le); weight=GAUSS_W[g]*le
            slope=dot(B,qe+q0); κ=dot(C,qe)
            s=force_section(c,P,κ,committed[e][g])
            isnothing(s) && return nothing
            s.EA>c.material.E*c.section.A*1e-14 || return nothing
            # Condensed tangent at fixed N: dM/dκ=EI-ES²/EA, dM/dP=-ES/EA.
            D=s.EI-s.ES^2/s.EA
            F[d]+=weight*(s.M*C-P*slope*B)
            KT[d,d]+=weight*(D*(C*C')-P*(B*B'))
            dFdP[d]+=weight*(-s.ES/s.EA*C-slope*B)
            states[e][g]=s.states
            yielded[e,g]=sum(c.fibers[i].area for i in eachindex(c.fibers) if s.states[i].accumulated>1e-10;init=0.0)/c.section.A
            strains[e,g]=s.ε0
            # von Kármán centerline strain: ε0=u'+(w'²-w0'²)/2.
            axial+=weight*(s.ε0-(slope^2-dot(B,q0)^2)/2)
        end
    end
    return (;F,KT,dFdP,states,yielded,strains,axial)
end
function residual_norm(c,r,P)
    return norm(c.scale[c.free].*r.F[c.free])/(c.Pscale*c.L)
end
function newton_raphson_step(c,qold,committed,P;tol=1e-8,maxiter=40)
    isfinite(P) && isfinite(tol) && tol>0 && maxiter isa Integer && maxiter>0 ||
        throw(ArgumentError("Finite load, positive finite tolerance and positive integer iteration count required"))
    q=copy(qold)
    for iteration in 1:maxiter
        r=nonlinear_response(c,q,P,committed)
        isnothing(r) && return (;converged=false,q=qold,response=nothing,iterations=iteration)
        err=residual_norm(c,r,P)
        err<tol && return (;converged=true,q,response=r,iterations=iteration)
        dq=try -(r.KT[c.free,c.free]\r.F[c.free]) catch; return (;converged=false,q=qold,response=nothing,iterations=iteration) end
        accepted=false
        for j in 0:12
            trial=copy(q); trial[c.free]+=2.0^(-j)*dq
            rt=nonlinear_response(c,trial,P,committed)
            if !isnothing(rt) && residual_norm(c,rt,P)<err
                q=trial; accepted=true; break
            end
        end
        accepted || return (;converged=false,q=qold,response=nothing,iterations=iteration)
    end
    return (;converged=false,q=qold,response=nothing,iterations=maxiter)
end
function sample_shape(c,q;points_per_element=12)
    x=Float64[]; w=Float64[]
    for e in 1:c.n, ξ in range(0,1,length=points_per_element+1)
        H=hermite(ξ,c.L/c.n)[1]
        push!(x,(e-1+ξ)*c.L/c.n)
        push!(w,dot(H,(q+c.imperfection)[2*e-1:2*e+2]))
    end
    return (;x,w)
end
function point_record(c,q,P,r,iterations)
    # Generalized eigenvalues relative to the initial elastic stiffness are dimensionless.
    mineig=minimum(eigvals(Symmetric(r.KT[c.free,c.free]),Symmetric(c.K0)))
    e=min(floor(Int,c.n/2)+1,c.n); ξ=c.n/2-(e-1)
    mid=dot(hermite(ξ,c.L/c.n)[1],(q+c.imperfection)[2*e-1:2*e+2])
    return (;P,q=copy(q),mid,mineig,yielded=copy(r.yielded),axial=r.axial,iterations,residual=residual_norm(c,r,P))
end
function initialize_path(c)
    states=initial_states(c); q=zeros(2(c.n+1))
    step=newton_raphson_step(c,q,states,0.0)
    step.converged || error("Initial residual-stress state could not be equilibrated")
    return step.q,step.response.states,[point_record(c,step.q,0.0,step.response,step.iterations)]
end
function path_summary(points,status)
    event=:none; critical=NaN; bracket=(NaN,NaN)
    for i in 2:length(points)
        a,b=points[i-1],points[i]
        if a.mineig>0 && b.mineig<=0
            # Interpolate an explicitly bracketed zero of the tangent eigenvalue.
            critical=a.P+(b.P-a.P)*a.mineig/(a.mineig-b.mineig)
            bracket=(a.P,b.P); event=:tangent_singularity; break
        elseif i>2 && b.P<a.P && a.P>points[i-2].P
            critical=a.P; bracket=(points[i-2].P,b.P); event=:limit_point; break
        end
    end
    # A converged local maximum is a direct limit-point observation.
    for i in 2:length(points)-1
        if points[i].P>points[i-1].P && points[i].P>points[i+1].P
            critical=points[i].P; bracket=(points[i-1].P,points[i+1].P); event=:limit_point; break
        end
    end
    return (;points,status,event,critical,bracket,Pmax=maximum(p.P for p in points))
end
# The perfectly straight, residual-free EPP column has an exact uniform axial
# branch. If Py precedes Euler, EA vanishes simultaneously in every fiber at Py.
# Close that axial mechanism analytically instead of inverting zero condensed EA
# or interpreting failure of a section iteration as lateral instability.
function has_uniform_yield_limit(c)
    return c.material.model==:epp && all(iszero,c.imperfection) &&
           all(iszero,c.residual) && c.Pscale==c.material.sy*c.section.A
end
function uniform_yield_path(c;step_fraction,max_fraction,maxsteps)
    q,states,points=initialize_path(c)
    py=c.material.sy*c.section.A
    for _ in 1:maxsteps
        target=min(points[end].P+step_fraction*py,max_fraction*py,py)
        # Evaluate the elastic-side limit; strain/stress are continuous at first
        # yield. The relative 1e-10 offset avoids the undefined 0/0 ES²/EA.
        r=nonlinear_response(c,q,min(target,(1-1e-10)*py),states)
        isnothing(r) && error("Uniform axial branch failed before its analytical yield limit")
        push!(points,point_record(c,q,target,r,0))
        if target>=py
            p=path_summary(points,:yield_capacity_reached)
            return merge(p,(event=:axial_yielding,critical=py,bracket=(py,py)))
        elseif target>=max_fraction*py*(1-1e-12)
            return path_summary(points,:target_reached)
        end
    end
    return path_summary(points,:step_limit)
end
function load_control(c;step_fraction=0.025,max_fraction=1.1,maxsteps=300,tol=1e-8)
    all(x -> isfinite(x) && x>0, (step_fraction,max_fraction,tol)) && maxsteps isa Integer && maxsteps>0 ||
        throw(ArgumentError("Positive finite solver controls and a positive integer step count required"))
    has_uniform_yield_limit(c) && return uniform_yield_path(c;step_fraction,max_fraction,maxsteps)
    q,states,points=initialize_path(c); P=0.0; dp=step_fraction*c.Pscale
    status=:step_limit
    for _ in 1:maxsteps
        target=min(P+dp,max_fraction*c.Pscale)
        step=newton_raphson_step(c,q,states,target;tol)
        if !step.converged
            dp/=2
            if dp<step_fraction*c.Pscale/1024
                status=:unresolved_nonconvergence; break
            end
            continue
        end
        q=step.q; states=step.response.states; P=target
        push!(points,point_record(c,q,P,step.response,step.iterations))
        if points[end].mineig<=0
            status=:instability_bracketed; break
        elseif P>=max_fraction*c.Pscale*(1-1e-12)
            status=:target_reached; break
        end
    end
    return path_summary(points,status)
end

# Spherical arc length in dimensionless displacement and load coordinates.
# ||Δz||² + α² Δλ² = ds²; q=S*z, P=λ*Pscale.
function riks_solver(c;ds=0.001,alpha=0.02,maxsteps=240,tol=1e-8,max_deflection=0.08*c.L,max_fraction=1.5)
    all(x -> isfinite(x) && x>0, (ds,alpha,tol,max_deflection,max_fraction)) && maxsteps isa Integer && maxsteps>0 ||
        throw(ArgumentError("Positive finite arc-length controls and a positive integer step count required"))
    has_uniform_yield_limit(c) && return uniform_yield_path(c;step_fraction=ds/alpha,max_fraction,maxsteps)
    q,states,points=initialize_path(c)
    free=c.free; S=c.scale[free]*sqrt(c.n+1)
    z=q[free]./S; λ=0.0; previous=zeros(length(z)+1)
    dsmax=ds; status=:step_limit; failures=0
    for _ in 1:maxsteps
        base=nonlinear_response(c,q,λ*c.Pscale,states)
        K=(S.*base.KT[free,free]).*S'/(c.Pscale*c.L)
        f=S.*base.dFdP[free]/c.L
        tangent=try -(K\f) catch; status=:unresolved_singular_predictor; break end
        dλ=ds/sqrt(dot(tangent,tangent)+alpha^2)
        direction=vcat(tangent*dλ,alpha*dλ)
        dot(direction,previous)<0 && (dλ=-dλ)
        zt=z+tangent*dλ; λt=λ+dλ
        converged=false; trial=nothing; iterations=0
        for it in 1:40
            iterations=it
            qt=copy(q); qt[free]=S.*zt
            trial=nonlinear_response(c,qt,λt*c.Pscale,states)
            isnothing(trial) && break
            dz=zt-z; dl=λt-λ
            g=dot(dz,dz)+alpha^2*dl^2-ds^2
            R=S.*trial.F[free]/(c.Pscale*c.L)
            if norm(R)<tol && abs(g)<1e-6*ds^2
                converged=true; break
            end
            KT=(S.*trial.KT[free,free]).*S'/(c.Pscale*c.L)
            fp=S.*trial.dFdP[free]/c.L
            augmented=[KT fp; 2dz' 2alpha^2*dl]
            correction=try augmented\vcat(-R,-g) catch; break end
            all(isfinite,correction) || break
            zt+=correction[1:end-1]; λt+=correction[end]
        end
        if !converged
            ds/=2; failures+=1
            if ds<dsmax/1024
                status=:unresolved_nonconvergence; break
            end
            continue # retain committed stresses and plastic strains on rejection
        end
        previous=vcat(zt-z,alpha*(λt-λ))
        z=zt; λ=λt; q[free]=S.*z; states=trial.states
        push!(points,point_record(c,q,λ*c.Pscale,trial,iterations))
        summary=path_summary(points,:running)
        if iszero(maximum(abs,c.imperfection)) && summary.event==:tangent_singularity
            status=:bifurcation_bracketed; break
        elseif maximum(abs,sample_shape(c,q).w)>=max_deflection
            status=:deformation_limit; break
        elseif λ>=max_fraction
            status=:load_limit; break
        elseif summary.event!=:none && λ*c.Pscale<0.8*summary.Pmax
            status=:postpeak_traced; break
        elseif λ<0
            status=:negative_load_limit; break
        end
        iterations<8 && (ds=min(dsmax,ds*1.25))
    end
    return path_summary(points,status)
end

end # module
