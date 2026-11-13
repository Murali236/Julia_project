module ArchAnalysis

using LinearAlgebra, SparseArrays, Printf, TOML
export Geometry, Section, PointForce, LineLoad, Couple, Spring, Model,
       ordinate, tangent, solve_force, force_response, force_samples,
       solve_stiffness, frame_response, stiffness_samples, report, export_model,
       doi, integrate, breakpoints, section_at

# Numerical core uses N, m, Pa. Fx right, Fy up, external M anticlockwise.
# Internal N is tension positive, Q follows the left-face beam shear convention,
# and M is sagging positive. Distributed loads are per horizontal projected metre.

struct Geometry
    kind::Symbol
    L::Float64
    f::Float64
    xs::Vector{Float64}
    ys::Vector{Float64}
end
function Geometry(kind::Symbol,L,f; xs=Float64[],ys=Float64[])
    isfinite(L) && L>0 && isfinite(f) && f>0 || throw(ArgumentError("Span and rise must be finite and positive."))
    kind in (:parabolic,:circular,:polyline) || throw(ArgumentError("Unknown geometry."))
    kind==:circular && f>L/2 && throw(ArgumentError("Circular arches require rise <= L/2 (minor arc or semicircle)."))
    if kind==:polyline
        length(xs)==length(ys)>=3 && xs[1]==0 && xs[end]==L && ys[1]==ys[end]==0 &&
            all(isfinite,xs) && all(isfinite,ys) && all(diff(xs).>0) ||
            throw(ArgumentError("Polyline needs increasing x, at least three points, and ends at (0,0), (L,0)."))
    end
    Geometry(kind,Float64(L),Float64(f),Float64.(xs),Float64.(ys))
end
radius(g) = g.L^2/(8g.f)+g.f/2
function polysegment(g,x;side=:right)
    j = side==:left ? searchsortedfirst(g.xs,x)-1 : searchsortedlast(g.xs,x)
    return clamp(j,1,length(g.xs)-1)
end
function ordinate(g,x)
    if g.kind==:parabolic
        return 4g.f*x*(g.L-x)/g.L^2
    elseif g.kind==:circular
        return g.f-radius(g)+sqrt(max(0.0,radius(g)^2-(x-g.L/2)^2))
    else
        j=polysegment(g,x)
        return g.ys[j]+(g.ys[j+1]-g.ys[j])*(x-g.xs[j])/(g.xs[j+1]-g.xs[j])
    end
end
function tangent(g,x;side=:right)
    if g.kind==:circular
        s=-(x-g.L/2)/radius(g)
        return (sqrt(max(0.0,1-s^2)),s)
    end
    slope = if g.kind==:parabolic
        4g.f*(g.L-2x)/g.L^2
    else
        j=polysegment(g,x;side=side)
        (g.ys[j+1]-g.ys[j])/(g.xs[j+1]-g.xs[j])
    end
    c=1/hypot(1,slope)
    return c,slope*c
end

struct Section
    a::Float64; b::Float64; E::Float64; A::Float64; I::Float64; law::Symbol
end
Section(a,b,E,A,I;law=:constant)=Section(a,b,E,A,I,law)
abstract type Load end
struct PointForce <: Load
    x::Float64; fx::Float64; fy::Float64
end
struct LineLoad <: Load
    a::Float64; b::Float64
    qxa::Float64; qya::Float64; qxb::Float64; qyb::Float64
end
struct Couple <: Load
    x::Float64; moment::Float64
end
struct Spring
    x::Float64; kx::Float64; ky::Float64; kr::Float64
end
struct Model
    geometry::Geometry
    support::Symbol
    sections::Vector{Section}
    loads::Vector{Load}
    axial::Bool
    hinge::Float64
    springs::Vector{Spring}
end
doi(s::Symbol)=s==:fixed ? 3 : s==:two_hinged ? 1 : s==:three_hinged ? 0 : throw(ArgumentError("Unknown arch support type."))
function Model(g,s,sections,loads;axial=true,hinge=g.L/2,springs=Spring[])
    doi(s)
    edge=0.0
    for p in sections
        p.a==edge && isfinite(p.b) && p.a<p.b<=g.L || throw(ArgumentError("Sections must cover [0,L] without gaps/overlaps."))
        all(v->isfinite(v)&&v>0,(p.E,p.A,p.I)) && p.law in (:constant,:secant) || throw(ArgumentError("Invalid E, A, I or section law."))
        edge=p.b
    end
    edge==g.L || throw(ArgumentError("Sections must cover the entire arch."))
    for l in loads
        all(isfinite,getfield(l,k) for k in fieldnames(typeof(l))) || throw(ArgumentError("Nonfinite load."))
        if l isa LineLoad
            0<=l.a<l.b<=g.L || throw(ArgumentError("Invalid distributed load interval."))
        else
            0<=l.x<=g.L || throw(ArgumentError("Point load/moment outside arch."))
        end
    end
    if s==:three_hinged
        0<hinge<g.L && abs(ordinate(g,hinge))>1e-10g.L || throw(ArgumentError("Internal hinge must be above/below the support line."))
        any(l->l isa Couple && l.x==hinge,loads) && throw(ArgumentError("A couple at the internal hinge requires a specified member side; move it off the hinge."))
    end
    for sp in springs
        0<=sp.x<=g.L && all(k->isfinite(k)&&k>=0,(sp.kx,sp.ky,sp.kr)) && sp.kx+sp.ky+sp.kr>0 || throw(ArgumentError("Invalid spring."))
        s==:three_hinged && sp.x==hinge && sp.kr>0 && throw(ArgumentError("Rotational spring at split hinge is ambiguous."))
    end
    Model(g,s,collect(sections),Load[loads...],axial,Float64(hinge),collect(springs))
end
function section_at(m,x;side=:right)
    j=findfirst(p->p.a<=x<p.b,m.sections)
    if side==:left
        j=findfirst(p->p.a<x<=p.b,m.sections)
    end
    p=m.sections[j===nothing ? (x==0 ? 1 : length(m.sections)) : j]
    c,_=tangent(m.geometry,x;side=side)
    I=p.law==:secant ? p.I/max(c,eps()) : p.I
    return (E=p.E,A=p.A,I=I,EI=p.E*I,EA=p.E*p.A)
end
function breakpoints(m)
    x=[0.0,m.geometry.L]
    append!(x,m.geometry.xs)
    for p in m.sections; append!(x,[p.a,p.b]); end
    for l in m.loads
        l isa LineLoad ? append!(x,[l.a,l.b]) : push!(x,l.x)
    end
    for sp in m.springs; push!(x,sp.x); end
    m.support==:three_hinged && push!(x,m.hinge)
    sort!(unique!(x))
end

function gauss_rule(n)
    beta=[i/sqrt(4i^2-1) for i in 1:n-1]
    e=eigen(SymTridiagonal(zeros(n),beta))
    return e.values,2 .* e.vectors[1,:].^2
end
const G8=gauss_rule(8)
const G16=gauss_rule(16)
function gauss(f,a,b,rule=G16)
    t,w=rule
    sum(w[i]*f((a+b)/2+(b-a)*t[i]/2) for i in eachindex(t))*(b-a)/2
end
function adaptive(f,a,b;rtol=1e-9,atol=0.0,depth=0)
    v=gauss(f,a,b); low=gauss(f,a,b,G8)
    norm(v-low)<=atol+rtol*max(norm(v),1e-18) && return v
    depth>=16 && throw(ArgumentError("Quadrature did not converge; refine geometry/section intervals."))
    c=(a+b)/2
    adaptive(f,a,c;rtol=rtol,atol=atol/2,depth=depth+1)+adaptive(f,c,b;rtol=rtol,atol=atol/2,depth=depth+1)
end
"""Integrate f(x) ds, splitting every load, geometry and property boundary."""
function integrate(m,f;a=0.0,b=m.geometry.L,rtol=1e-9,atol=0.0)
    a==b && return zero(f((a+b)/2))
    g=m.geometry
    cuts=sort!(unique!(vcat(a,[x for x in breakpoints(m) if a<x<b],b)))
    result=nothing
    for j in 1:length(cuts)-1
        lo,hi=cuts[j:j+1]
        value = if g.kind==:circular
            R=radius(g)
            t1=asin(clamp((lo-g.L/2)/R,-1,1)); t2=asin(clamp((hi-g.L/2)/R,-1,1))
            adaptive(t->f(g.L/2+R*sin(t))*R,t1,t2;rtol=rtol,atol=atol/(length(cuts)-1))
        else
            adaptive(x->f(x)/tangent(g,x)[1],lo,hi;rtol=rtol,atol=atol/(length(cuts)-1))
        end
        result=result===nothing ? value : result+value
    end
    result
end

# Primitives of y and x*y used for exact resultant moments of inclined loads.
function y_primitives(g,x;segment=1)
    if g.kind==:circular
        R=radius(g); u=x-g.L/2; h=sqrt(max(0.0,R^2-u^2))
        z=(u*h+R^2*asin(clamp(u/R,-1,1)))/2
        return (g.f-R)*x+z,(g.f-R)*x^2/2+g.L*z/2-h^3/3
    end
    if g.kind==:parabolic
        a,b,c=-4g.f/g.L^2,4g.f/g.L,0.0
    else
        a=0.0
        b=(g.ys[segment+1]-g.ys[segment])/(g.xs[segment+1]-g.xs[segment])
        c=g.ys[segment]-b*g.xs[segment]
    end
    return a*x^3/3+b*x^2/2+c*x,a*x^4/4+b*x^3/3+c*x^2/2
end
function line_resultant(g,l,a,b)
    b<=a && return zeros(3)
    bx=(l.qxb-l.qxa)/(l.b-l.a); by=(l.qyb-l.qya)/(l.b-l.a)
    ax=l.qxa-bx*l.a; ay=l.qya-by*l.a
    fx=ax*(b-a)+bx*(b^2-a^2)/2
    fy=ay*(b-a)+by*(b^2-a^2)/2
    yc=0.0
    cuts=sort!(unique!(vcat(a,[x for x in g.xs if a<x<b],b)))
    for j in 1:length(cuts)-1
        lo,hi=cuts[j:j+1]; seg=g.kind==:polyline ? polysegment(g,(lo+hi)/2) : 1
        ya,xa=y_primitives(g,lo;segment=seg); yb,xb=y_primitives(g,hi;segment=seg)
        yc+=ax*(yb-ya)+bx*(xb-xa)
    end
    [fx,fy,ay*(b^2-a^2)/2+by*(b^3-a^3)/3-yc]
end
function prefix_loads(m,x;side=:right)
    r=zeros(3); g=m.geometry
    for l in m.loads
        if l isa LineLoad
            r+=line_resultant(g,l,l.a,min(x,l.b))
        elseif l.x<x || (side==:right && l.x==x)
            if l isa PointForce
                r += [l.fx,l.fy,l.x*l.fy-ordinate(g,l.x)*l.fx]
            else
                r[3]+=l.moment
            end
        end
    end
    r
end
function response_from_left(m,R,x;side=:right)
    fx,fy,T=prefix_loads(m,x;side=side)
    H,V,M=R
    c,s=tangent(m.geometry,x;side=side); y=ordinate(m.geometry,x)
    H+=fx; V+=fy
    return (M=x*V-y*H-M-T,N=-(H*c+V*s),Q=V*c-H*s)
end
function unit_fields(m,x)
    c,s=tangent(m.geometry,x); y=ordinate(m.geometry,x)
    # Rows: M, N, Q. Columns: left HA, VA, MA (right/up/CCW).
    [-y x -1.0; -c -s 0.0; -s c 0.0]
end
function solve_force(m;rtol=1e-9)
    isempty(m.springs) || throw(ArgumentError("Use the stiffness solver for extra spring supports."))
    L=m.geometry.L
    fx,fy,T=prefix_loads(m,L)
    VA=-fy+T/L
    if m.support==:three_hinged
        R=[0.0,VA,0.0]
        R[1]=response_from_left(m,R,m.hinge).M/ordinate(m.geometry,m.hinge)
        F=zeros(0,0); D=Float64[]; X=Float64[]; B=zeros(3,0); center=(x=NaN,y=NaN)
    else
        centerweight=integrate(m,x->1/section_at(m,x).EI;rtol=rtol)
        xc=integrate(m,x->x/section_at(m,x).EI;rtol=rtol)/centerweight
        yc=integrate(m,x->ordinate(m.geometry,x)/section_at(m,x).EI;rtol=rtol)/centerweight
        center=(x=xc,y=yc)
        if m.support==:two_hinged
            R0=[0.0,VA,0.0]; B=reshape([1.0,0.0,0.0],3,1)
        else
            # Primary: free at A, fixed at B. Elastic-center redundants map
            # back to support A as MA = Mc + xc*V - yc*H.
            R0=zeros(3); B=[1.0 0.0 0.0;0.0 1.0 0.0;-yc xc 1.0]
        end
        k=size(B,2)
        integrand = function(x)
            p=section_at(m,x)
            W=Diagonal([1/p.EI,m.axial ? 1/p.EA : 0.0,0.0])
            U=unit_fields(m,x)*B
            r=response_from_left(m,R0,x)
            z=[r.M,r.N,r.Q]
            hcat(U'*W*U,U'*W*z)
        end
        FD=integrate(m,integrand;rtol=rtol)
        F=FD[:,1:k]; D=FD[:,end]
        scale=1 ./ sqrt.(diag(F))
        Fs=Symmetric((scale.*F).*scale')
        minimum(eigvals(Fs))>1e-12 || throw(ArgumentError("Singular/ill-conditioned flexibility matrix."))
        X=scale.*(cholesky(Fs)\(-scale.*D))
        R=R0+B*X
    end
    HB=-fx-R[1]; VB=-fy-R[2]; MB=-T-L*VB-R[3]
    reactions=[R;HB;VB;MB]
    solution=(model=m,reactions=reactions,F=F,D=D,X=X,basis=B,center=center,rtol=rtol)
    # Integrals of curvature and axial strain yield exact kinematic recovery.
    total=integrate(m,x->deformation_integrand(solution,x);rtol=rtol,atol=1e-12)
    u0=-ordinate(m.geometry,L)*total[1]+total[3]+total[4]
    v0=L*total[1]-total[2]+total[5]
    jump=m.support==:three_hinged ? -u0/ordinate(m.geometry,m.hinge) : 0.0
    theta0=m.support==:fixed ? 0.0 : -(v0+jump*(L-m.hinge))/L
    merge(solution,(theta0=theta0,hinge_jump=jump,totals=total))
end
force_response(s,x;side=:right)=response_from_left(s.model,s.reactions[1:3],x;side=side)
function deformation_integrand(s,x)
    r=force_response(s,x); p=section_at(s.model,x)
    c,t=tangent(s.model.geometry,x); y=ordinate(s.model.geometry,x)
    curvature=r.M/p.EI; strain=s.model.axial ? r.N/p.EA : 0.0
    [curvature,x*curvature,y*curvature,strain*c,strain*t]
end
function displacement(s,x,ints;side=:right)
    y=ordinate(s.model.geometry,x); B,Cx,Cy,U,V=ints
    after=x>s.model.hinge || (x==s.model.hinge && side==:right)
    jump=after ? s.hinge_jump : 0.0
    (u=U-s.theta0*y-y*B+Cy-jump*(y-ordinate(s.model.geometry,s.model.hinge)),
     v=V+s.theta0*x+x*B-Cx+jump*(x-s.model.hinge),theta=s.theta0+B+jump)
end
function force_samples(s;points_per_interval=31)
    xs=Float64[]; Ms=Float64[]; Ns=Float64[]; Qs=Float64[]; us=Float64[]; vs=Float64[]; ts=Float64[]
    cuts=breakpoints(s.model); ints=zeros(5); prev=0.0
    for j in 1:length(cuts)-1
        for (i,x) in enumerate(range(cuts[j],cuts[j+1],length=points_per_interval))
            if x>prev
                ints+=integrate(s.model,z->deformation_integrand(s,z);a=prev,b=x,rtol=s.rtol,atol=1e-12)
            end
            side=i==points_per_interval ? :left : :right
            r=force_response(s,x;side=side); d=displacement(s,x,ints;side=side)
            push!(xs,x);push!(Ms,r.M);push!(Ns,r.N);push!(Qs,r.Q)
            push!(us,d.u);push!(vs,d.v);push!(ts,d.theta)
            prev=x
        end
    end
    (x=xs,M=Ms,N=Ns,Q=Qs,u=us,v=vs,theta=ts)
end

function frame_matrix(EA,EI,L)
    k=zeros(6,6)
    k[[1,4],[1,4]]=EA/L.*[1.0 -1.0;-1.0 1.0]
    k[[2,3,5,6],[2,3,5,6]]=EI/L^3 .* [12.0 6L -12.0 6L;6L 4L^2 -6L 2L^2;-12.0 -6L 12.0 -6L;6L 2L^2 -6L 4L^2]
    k
end
function projected_load(m,a,b,c,s)
    q=zeros(4)
    for l in m.loads
        if l isa LineLoad && l.a<=a && b<=l.b
            qa=[l.qxa,l.qya]+(a-l.a)/(l.b-l.a).*[l.qxb-l.qxa,l.qyb-l.qya]
            qb=[l.qxa,l.qya]+(b-l.a)/(l.b-l.a).*[l.qxb-l.qxa,l.qyb-l.qya]
            q += c.*[c*qa[1]+s*qa[2],-s*qa[1]+c*qa[2],c*qb[1]+s*qb[2],-s*qb[1]+c*qb[2]]
        end
    end
    q
end
function equivalent_frame_load(q,L)
    gauss(0.0,L,G8) do x
        t=x/L
        qa=q[1]+(q[3]-q[1])*t; qt=q[2]+(q[4]-q[2])*t
        [qa*(1-t),qt*(1-3t^2+2t^3),qt*L*(t-2t^2+t^3),qa*t,qt*(3t^2-2t^3),qt*L*(-t^2+t^3)]
    end
end
function solve_stiffness(m;elements=80)
    m.axial || throw(ArgumentError("Frame comparison requires axial deformation enabled; bending-only force models use different assumptions."))
    elements>=2 || throw(ArgumentError("At least two frame elements required."))
    g=m.geometry
    base = if g.kind==:circular
        R=radius(g); a=asin(g.L/(2R))
        [g.L/2+R*sin(t) for t in range(-a,a,length=elements+1)]
    else
        collect(range(0,g.L,length=elements+1))
    end
    base[1]=0.0;base[end]=g.L
    mandatory=breakpoints(m)
    # Snap generated mesh positions to exact input events (avoids tiny elements).
    for i in eachindex(base)
        j=findfirst(x->abs(x-base[i])<=1e-12g.L,mandatory)
        j!==nothing && (base[i]=mandatory[j])
    end
    xs=sort!(unique!(vcat(base,mandatory))); ys=ordinate.(Ref(g),xs)
    n=length(xs); hinge=m.support==:three_hinged ? findfirst(==(m.hinge),xs) : nothing
    ndof=3n+(hinge===nothing ? 0 : 1)
    rows=Int[]; cols=Int[]; vals=Float64[]; F=zeros(ndof); es=NamedTuple[]
    for j in 1:n-1
        a,b=xs[j:j+1]; dx=b-a;dy=ys[j+1]-ys[j];L=hypot(dx,dy);c=dx/L;s=dy/L
        T=zeros(6,6); T[1:3,1:3]=[c s 0.0;-s c 0.0;0.0 0.0 1.0];T[4:6,4:6]=T[1:3,1:3]
        p=section_at(m,(a+b)/2);k=frame_matrix(p.EA,p.EI,L)
        q=projected_load(m,a,b,c,s);feq=equivalent_frame_load(q,L)
        dofs=[3j-2,3j-1,j==hinge ? ndof : 3j,3j+1,3j+2,3j+3]
        kg=T'*k*T; F[dofs]+=T'*feq
        for r in 1:6,t in 1:6
            push!(rows,dofs[r]);push!(cols,dofs[t]);push!(vals,kg[r,t])
        end
        push!(es,(a=a,b=b,L=L,c=c,s=s,T=T,k=k,q=q,feq=feq,dofs=dofs,EA=p.EA,EI=p.EI))
    end
    for l in m.loads
        if l isa PointForce
            j=searchsortedfirst(xs,l.x);F[3j-2]+=l.fx;F[3j-1]+=l.fy
        elseif l isa Couple
            j=searchsortedfirst(xs,l.x);F[3j]+=l.moment
        end
    end
    Kbeam=sparse(rows,cols,vals,ndof,ndof);K=copy(Kbeam)
    for sp in m.springs
        j=searchsortedfirst(xs,sp.x)
        for (dof,k) in zip(3j-2:3j,(sp.kx,sp.ky,sp.kr));K[dof,dof]+=k;end
    end
    fixed=[1,2,3n-2,3n-1]
    m.support==:fixed && append!(fixed,[3,3n])
    free=setdiff(1:ndof,fixed);d=zeros(ndof)
    A=K[free,free]; scale=1 ./sqrt.(diag(A));D=spdiagm(0=>scale)
    try
        d[free]=scale.*(cholesky(Symmetric(D*A*D))\(scale.*F[free]))
    catch err
        err isa PosDefException || rethrow()
        throw(ArgumentError("Frame stiffness is singular; check geometry and restraints."))
    end
    residual=Kbeam*d-F
    reactions=vcat(residual[1:3],residual[3n-2:3n])
    m.support!=:fixed && (reactions[[3,6]].=0.0)
    solved=[merge(e,(d=e.T*d[e.dofs],forces=e.k*(e.T*d[e.dofs])-e.feq)) for e in es]
    spr=[(x=sp.x,fx=-sp.kx*d[3searchsortedfirst(xs,sp.x)-2],fy=-sp.ky*d[3searchsortedfirst(xs,sp.x)-1],moment=-sp.kr*d[3searchsortedfirst(xs,sp.x)]) for sp in m.springs]
    (model=m,x=xs,y=ys,d=d,reactions=reactions,springs=spr,elements=solved,K=K,F=F,free=free,hinge=hinge)
end
function frame_response(e,t)
    fa,fv,fm=e.forces[1:3]; qa,qt=e.q[1:2]
    ga=(e.q[3]-qa)/e.L;gt=(e.q[4]-qt)/e.L
    N=-fa-qa*t-ga*t^2/2; Q=fv+qt*t+gt*t^2/2
    M=-fm+fv*t+qt*t^2/2+gt*t^3/6
    ul=e.d[1]+(-fa*t-qa*t^2/2-ga*t^3/6)/e.EA
    theta=e.d[3]+(-fm*t+fv*t^2/2+qt*t^3/6+gt*t^4/24)/e.EI
    vl=e.d[2]+e.d[3]*t+(-fm*t^2/2+fv*t^3/6+qt*t^4/24+gt*t^5/120)/e.EI
    (M=M,N=N,Q=Q,u=e.c*ul-e.s*vl,v=e.s*ul+e.c*vl,theta=theta)
end
function stiffness_samples(s;points_per_element=9)
    data=[Float64[] for _ in 1:7]
    for e in s.elements,t in range(0,e.L,length=points_per_element)
        r=frame_response(e,t)
        for (a,v) in zip(data,(e.a+e.c*t,r.M,r.N,r.Q,r.u,r.v,r.theta));push!(a,v);end
    end
    NamedTuple{(:x,:M,:N,:Q,:u,:v,:theta)}(Tuple(data))
end

function equilibrium(s)
    m=s.model;fx,fy,T=prefix_loads(m,m.geometry.L)
    if hasproperty(s,:K)
        n=length(s.x)
        fx=sum(s.F[1:3:3n]);fy=sum(s.F[2:3:3n])
        T=sum(s.x.*s.F[2:3:3n]-s.y.*s.F[1:3:3n])+sum(s.F[3:3:3n])
        s.hinge!==nothing && (T+=s.F[end])
    end
    H,V,M,Hb,Vb,Mb=s.reactions
    r=[H+Hb+fx,V+Vb+fy,M+Mb+m.geometry.L*Vb+T]
    if hasproperty(s,:springs)
        for sp in s.springs
            r += [sp.fx,sp.fy,sp.x*sp.fy-ordinate(m.geometry,sp.x)*sp.fx+sp.moment]
        end
    end
    r
end
function report(m,force,frame)
    io=IOBuffer();println(io,"ARCH ANALYSIS: $(m.support), DOI=$(doi(m.support)) (base end restraints)")
    println(io,"Right/up/anticlockwise positive; internal N tension positive, M sagging positive.")
    println(io,"Distributed loads per horizontal metre. SI internal units: N, m, Pa.")
    println(io,"Axial strain: $(m.axial); shear strain: omitted. Linear small-displacement elasticity.")
    for (name,s) in (("FORCE METHOD",force),("FRAME STIFFNESS",frame))
        s===nothing && continue
        println(io,"\n$name")
        for (label,value) in zip(("HA (kN)","VA (kN)","MA (kN-m)","HB (kN)","VB (kN)","MB (kN-m)"),s.reactions/1000)
            @printf(io,"%s = %.10g\n",label,value)
        end
        println(io,"Equilibrium residual [Fx, Fy, M] (N, N-m): ",equilibrium(s))
        if name=="FORCE METHOD"
            println(io,"Elastic center: ",s.center)
            println(io,"F (SI mixed force/moment coordinates):");show(io,"text/plain",s.F);println(io)
            println(io,"Delta0 = ",s.D,"; redundants = ",s.X)
            println(io,"Compatibility residual F*X+Delta0 = ",s.F*s.X+s.D)
            d=displacement(s,m.geometry.L,s.totals)
            println(io,"Right-end recovered (u,v,theta): ",d)
            println(io,"Left-end theta = ",s.theta0,"; internal-hinge rotation jump = ",s.hinge_jump)
            if m.support==:three_hinged
                println(io,"Hinge moment (N-m): ",force_response(s,m.hinge).M)
            end
        else
            println(io,"Elements = ",length(s.elements),"; free-DOF residual norm = ",norm((s.K*s.d-s.F)[s.free],Inf))
            println(io,"Spring reactions (N, N-m): ",s.springs)
            println(io,"\nNodal displacements: x(m), y(m), u(mm), v(mm), theta(rad)")
            for j in eachindex(s.x)
                @printf(io,"%.8g, %.8g, %.9g, %.9g, %.9g\n",s.x[j],s.y[j],1000s.d[3j-2],1000s.d[3j-1],s.d[3j])
            end
        end
    end
    if force!==nothing && frame!==nothing
        println(io,"\nFrame minus force reactions (kN, kN-m): ",(frame.reactions-force.reactions)/1000)
        println(io,"A polygonal frame approximates the smooth arch; refine the mesh to assess convergence.")
    end
    println(io,"\nSECTION EQUATIONS (exact equilibrium with solved numerical reaction constants)")
    println(io,"Let Fx(x), Fy(x), T(x) sum loads LEFT of the section, T about (0,0).")
    println(io,"Sx = HA + Fx(x); Sy = VA + Fy(x)")
    println(io,"M(x) = x*Sy - y(x)*Sx - MA - T(x)")
    println(io,"N(x) = -(Sx*cos(phi) + Sy*sin(phi))")
    println(io,"Q(x) = Sy*cos(phi) - Sx*sin(phi)")
    println(io,"For a distributed load, Fx=integral(qx dx), Fy=integral(qy dx), T=integral(x*qy-y*qx dx).")
    println(io,"Breakpoints: ",breakpoints(m))
    force===nothing && println(io,"With extra springs, add each spring reaction to the prefix sums after its position.")
    println(io,"\nGeometry: ",m.geometry.kind,"; L=",m.geometry.L,"; f=",m.geometry.f)
    println(io,"Sections (SI): ",m.sections)
    println(io,"Applied loads (SI): ",m.loads)
    for (name,samples) in (("Force",force===nothing ? nothing : force_samples(force)),("Frame",frame===nothing ? nothing : stiffness_samples(frame)))
        samples===nothing && continue
        println(io,"\n$name sampled extrema (refine sampling to locate precise extrema):")
        for key in (:M,:N,:Q,:u,:v,:theta)
            values=getproperty(samples,key);lo=argmin(values);hi=argmax(values)
            println(io,"$key: min=$(values[lo]) at x=$(samples.x[lo]); max=$(values[hi]) at x=$(samples.x[hi]) (SI)")
        end
    end
    String(take!(io))
end
function export_model(path,m,force,frame)
    g=m.geometry
    data=Dict{String,Any}("geometry"=>Dict("kind"=>string(g.kind),"L"=>g.L,"f"=>g.f,"xs"=>g.xs,"ys"=>g.ys),
        "support"=>string(m.support),"axial"=>m.axial,"hinge"=>m.hinge,
        "sections"=>[Dict("a"=>p.a,"b"=>p.b,"E"=>p.E,"A"=>p.A,"I"=>p.I,"law"=>string(p.law)) for p in m.sections],
        "loads"=>[merge(Dict("kind"=>l isa PointForce ? "point" : l isa Couple ? "moment" : "line"),Dict(string(k)=>getfield(l,k) for k in fieldnames(typeof(l)))) for l in m.loads])
    force!==nothing && (data["force_reactions"]=force.reactions)
    if frame!==nothing
        data["frame_reactions"]=frame.reactions; data["mesh_x"]=frame.x;data["mesh_y"]=frame.y;data["frame_d"]=frame.d
        data["springs"]=[Dict(string(k)=>getfield(sp,k) for k in fieldnames(Spring)) for sp in m.springs]
    end
    open(path,"w") do io;TOML.print(io,data);end
end

end # module
