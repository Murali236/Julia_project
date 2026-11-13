using Test, LinearAlgebra, Printf
include(joinpath(@__DIR__,"..","buckling_core.jl"))
using .BucklingCore

@testset "Nonlinear controls reject invalid values before solving" begin
    # Invalid controls must fail even on the analytical uniform-yield shortcut.
    s = section_properties([RectPart(.1,.15,0.,0.)])
    c = ColumnModel(s,Material(200e9,250e6),.3,4,:pinned_pinned;imperfection=0.)
    for bad in (0.,-1.,NaN,Inf)
        @test_throws ArgumentError load_control(c;step_fraction=bad)
        @test_throws ArgumentError load_control(c;max_fraction=bad)
        @test_throws ArgumentError load_control(c;tol=bad)
        @test_throws ArgumentError riks_solver(c;ds=bad)
        @test_throws ArgumentError riks_solver(c;alpha=bad)
        @test_throws ArgumentError riks_solver(c;max_fraction=bad)
        @test_throws ArgumentError riks_solver(c;max_deflection=bad)
        @test_throws ArgumentError riks_solver(c;tol=bad)
    end
    for bad in (0,-1,1.5,Inf)
        @test_throws ArgumentError load_control(c;maxsteps=bad)
        @test_throws ArgumentError riks_solver(c;maxsteps=bad)
        @test_throws ArgumentError newton_raphson_step(c,zeros(10),BucklingCore.initial_states(c),0.;maxiter=bad)
    end
    @test_throws ArgumentError newton_raphson_step(c,zeros(10),BucklingCore.initial_states(c),Inf)
end
const S=section_properties([RectPart(0.10,0.15,0.,0.)];name="Rectangle")
const E=200e9
const SY=250e6
const M=Material(E,SY)
const PE=π^2*E*S.Iy/3^2
@testset "Section formulas and fiber integration" begin
    sections=[S,section_properties(.1),
        section_properties([RectPart(.2,.02,0.,0.),RectPart(.01,.26,.095,.02),RectPart(.2,.02,0.,.28)]),
        section_properties([RectPart(.01,.28,.095,0.),RectPart(.2,.02,0.,.28)]),
        section_properties([RectPart(.02,.2,0.,0.),RectPart(.13,.02,.02,0.)]),
        section_properties([RectPart(.02,.26,0.,.02),RectPart(.15,.02,0.,0.),RectPart(.15,.02,0.,.28)])]
    @test S.A≈.015
    @test S.Iy≈1.25e-5
    @test SY*S.A≈3750000
    for s in sections, axis in (:x,:y)
        f=fiber_mesh(s,axis;layers=8,sectors=16)
        @test sum(x.area for x in f)≈s.A
        @test abs(sum(x.area*x.y for x in f))<1e-14
        @test sum(x.area*x.y^2 for x in f)≈(axis==:x ? s.Ix : s.Iy)
    end
    @test_throws ArgumentError section_properties(-.1)
    @test_throws ArgumentError Material(E,SY;ratio=1.)
    @test_throws ArgumentError solve_eigen(E*S.Iy,3.,16,:custom)
end
@testset "Elastic eigenproblem and restraints" begin
    for (bc,k) in [(:pinned_pinned,1.),(:fixed_free,2.),(:fixed_pinned,.699),(:fixed_fixed,.5)]
        f=solve_eigen(E*S.Iy,3.,16,bc)
        exact=π^2*E*S.Iy/(3k)^2
        @test abs(f.Pcr/exact-1)<.005
        @test norm((f.K*f.mode-f.Pcr*f.G*f.mode)[f.free])/norm((f.K*f.mode)[f.free])<1e-7
        @test all(iszero,f.mode[setdiff(1:length(f.mode),f.free)])
        @printf("SUPPORT %-16s Pcr=%12.6f kN difference=%+.6f%%\n",bc,f.Pcr/1000,100*(f.Pcr/exact-1))
    end
    @test solve_eigen(E*S.Iy,3.,16,:pinned_pinned;Pref=12345.).Pcr≈PE rtol=1e-5
end
@testset "Constitutive laws, unloading, tangent curves" begin
    for model in (:epp,:bilinear,:ramberg_osgood)
        m=Material(E,SY;model)
        f=[Fiber(1.,0.)]; old=[FiberState()]
        strain=.004
        r=section_response(f,m,strain,0.,old)
        @test r.states[1].accumulated>0
        h=1e-8
        rp=section_response(f,m,strain+h,0.,old)
        rm=section_response(f,m,strain-h,0.,old)
        @test (rp.N-rm.N)/(2h)≈r.EA rtol=1e-5 atol=1.
        unload=section_response(f,m,strain-1e-5,0.,r.states)
        @test unload.EA≈E
        @test unload.states==r.states
        @test old[1].plastic==0
    end
    @test tangent_buckling(M,10.).stress==SY
    @test tangent_buckling(M,200.).stress≈π^2*E/200^2
    @test tangent_buckling(Material(E,1e15),100.).stress≈π^2*E/100^2
    mr=Material(E,SY;model=:ramberg_osgood)
    for λ in (10.,50.,100.,300.)
        σ=tangent_buckling(mr,λ).stress
        @test σ≈π^2*material_tangent(mr,σ)/λ^2 rtol=1e-10
    end
end
@testset "Nonlinear consistent tangents, residual equilibrium and rollback" begin
    c=ColumnModel(S,M,3.,4,:pinned_pinned;layers=12,residual_fraction=.2)
    @test abs(sum(c.fibers[i].area*c.residual[i] for i in eachindex(c.fibers)))<1e-7
    @test abs(sum(c.fibers[i].area*c.fibers[i].y*c.residual[i] for i in eachindex(c.fibers)))<1e-7
    old=BucklingCore.initial_states(c); q=0.003*c.imperfection/maximum(abs,c.imperfection)
    r=nonlinear_response(c,q,.65PE,old)
    v=sin.(collect(1:length(q))); v[setdiff(1:length(q),c.free)].=0
    h=1e-8
    rp=nonlinear_response(c,q+h*v,.65PE,old)
    rm=nonlinear_response(c,q-h*v,.65PE,old)
    @test norm((rp.F-rm.F)/(2h)-r.KT*v)/norm(r.KT*v)<1e-5
    hp=1.
    rp=nonlinear_response(c,q,.65PE+hp,old)
    rm=nonlinear_response(c,q,.65PE-hp,old)
    @test norm((rp.F-rm.F)/(2hp)-r.dFdP)/norm(r.dFdP)<1e-5
    failed=newton_raphson_step(c,q,old,.9PE;maxiter=1)
    @test !failed.converged
    @test all(s.plastic==0 for e in old for g in e for s in g)
    ce=ColumnModel(S,Material(E,SY;model=:elastic),3.,8,:pinned_pinned;layers=8)
    path=load_control(ce;max_fraction=.5)
    @test path.status==:target_reached
    @test path.points[end].mid≈.006 rtol=1e-5
    @test isnan(path.critical) # target reached does not imply buckling
end
@testset "Mesh, continuation and step sensitivity" begin
    peaks=Float64[]
    for n in (4,8,16,32)
        c=ColumnModel(S,M,3.,n,:pinned_pinned;layers=24)
        p=riks_solver(c;ds=.0005,maxsteps=400)
        @test p.event==:limit_point
        @test p.status==:postpeak_traced
        @test p.points[end].P<.81p.Pmax
        @test maximum(x.residual for x in p.points)<1e-7
        @test PE*.6<p.critical<PE
        push!(peaks,p.Pmax)
        fe=solve_eigen(E*S.Iy,3.,n,:pinned_pinned)
        @printf("MESH N=%2d elastic=%12.6f kN peak=%12.6f kN points=%d\n",n,fe.Pcr/1000,p.Pmax/1000,length(p.points))
    end
    @test abs(peaks[end]/peaks[end-1]-1)<.01
    c=ColumnModel(S,M,3.,16,:pinned_pinned;layers=24)
    for ds in (.001,.00025)
        p=riks_solver(c;ds,maxsteps=600)
        @test abs(p.Pmax/peaks[3]-1)<.005
        @printf("ARC STEP ds=%.5f peak=%.6f kN\n",ds,p.Pmax/1000)
    end
    for dp in (.05,.025,.0125)
        p=load_control(c;step_fraction=dp,max_fraction=.7)
        @test p.status==:target_reached
        @test maximum(x.residual for x in p.points)<1e-7
        @printf("LOAD STEP fraction=%.4f P=%.6f kN wmid=%.9f mm\n",dp,p.Pmax/1000,p.points[end].mid*1000)
    end
end
@testset "Imperfection and material/length limits" begin
    peaks=Float64[]
    for amp in (.003,.006,0.)
        c=ColumnModel(S,M,3.,16,:pinned_pinned;imperfection=amp,layers=24)
        p=riks_solver(c;ds=.0005,maxsteps=500)
        push!(peaks,p.critical)
        @test isfinite(p.critical)
        @printf("IMPERFECTION e0=%.3f mm critical=%.6f kN event=%s status=%s\n",amp*1000,p.critical/1000,p.event,p.status)
        amp==0 && (@test maximum(abs(x.mid) for x in p.points)<1e-12)
    end
    @test peaks[2]<peaks[1]<peaks[3]
    @test peaks[3]≈PE rtol=.001
    c=ColumnModel(S,Material(E,1e15),3.,16,:pinned_pinned;imperfection=0.,layers=12)
    p=load_control(c;step_fraction=.04,max_fraction=1.1)
    @test p.critical≈PE rtol=.001
    @printf("HIGH YIELD straight critical=%.6f kN Euler=%.6f kN\n",p.critical/1000,PE/1000)
    for (L,amp) in ((.3,.3/1000),(12.,12/1000))
        c=ColumnModel(S,M,L,16,:pinned_pinned;imperfection=amp,layers=24)
        p=riks_solver(c;ds=.0005,maxsteps=700,max_deflection=.15L)
        pe=π^2*E*S.Iy/L^2; py=SY*S.A
        @test p.event!=:none
        if L<1
            @test .95py<p.Pmax<=py
        else
            @test .90pe<p.Pmax<pe
        end
        @printf("LIMIT L=%.3f m Pmax=%.6f kN Py=%.6f kN Euler=%.6f kN event=%s\n",L,p.Pmax/1000,py/1000,pe/1000,p.event)
    end
end
@testset "Additional hardening, restraint and elastic-limit regressions" begin
    for model in (:bilinear,:ramberg_osgood)
        c=ColumnModel(S,Material(E,SY;model),3.,8,:pinned_pinned;layers=12)
        p=riks_solver(c;ds=.0005,maxsteps=500)
        @test p.event==:limit_point
        @test maximum(x.residual for x in p.points)<1e-7
        @printf("MATERIAL %s peak=%.6f kN\n",model,p.Pmax/1000)
    end
    for bc in (:fixed_free,:fixed_pinned,:fixed_fixed)
        c=ColumnModel(S,M,3.,8,bc;layers=12)
        p=riks_solver(c;ds=.0005,maxsteps=500)
        @test p.event==:limit_point
        @test maximum(x.residual for x in p.points)<1e-7
        @printf("NONLINEAR SUPPORT %s peak=%.6f kN\n",bc,p.Pmax/1000)
    end
    c1=ColumnModel(S,Material(E,1e15),3.,8,:pinned_pinned;layers=12)
    c2=ColumnModel(S,Material(E,1e15;model=:elastic),3.,8,:pinned_pinned;layers=12)
    p1=riks_solver(c1;maxsteps=300); p2=riks_solver(c2;maxsteps=300)
    @test p1.status==p2.status==:deformation_limit
    @test p1.Pmax≈p2.Pmax rtol=1e-12
    @test p1.points[end].mid≈p2.points[end].mid rtol=1e-12
    @test isnan(p1.critical) # imperfect elastic asymptote is not a finite peak
    @printf("HIGH YIELD imperfect vs elastic Pmax ratio=%.12f; no finite peak\n",p1.Pmax/p2.Pmax)
    # Newton non-convergence by itself MUST NOT become a critical load.
    c=ColumnModel(S,M,3.,8,:pinned_pinned;layers=12)
    p=load_control(c;max_fraction=1.1)
    @test p.status==:unresolved_nonconvergence
    @test p.event==:none
    @test isnan(p.critical)
    # A yielded section's material and geometric tangent must remain consistent.
    old=BucklingCore.initial_states(c); q=5*c.imperfection
    r=nonlinear_response(c,q,.65PE,old)
    @test maximum(r.yielded)>0
    v=cos.(collect(1:length(q))); v[setdiff(1:length(q),c.free)].=0
    h=1e-9
    rp=nonlinear_response(c,q+h*v,.65PE,old); rm=nonlinear_response(c,q-h*v,.65PE,old)
    @test norm((rp.F-rm.F)/(2h)-r.KT*v)/norm(r.KT*v)<1e-5
    fiberpeaks=Float64[]
    for layers in (12,24,48)
        c=ColumnModel(S,M,3.,16,:pinned_pinned;layers)
        p=riks_solver(c;ds=.00025,maxsteps=600)
        push!(fiberpeaks,p.Pmax)
        @printf("FIBERS layers=%d peak=%.6f kN\n",layers,p.Pmax/1000)
    end
    @test abs(fiberpeaks[end]/fiberpeaks[end-1]-1)<.005
end
@testset "Perfect stocky EPP axial yielding" begin
    c=ColumnModel(S,M,.3,8,:pinned_pinned;imperfection=0.,layers=12)
    for p in (load_control(c),riks_solver(c))
        @test p.status==:yield_capacity_reached
        @test p.event==:axial_yielding
        @test p.critical==SY*S.A
        @test p.Pmax==SY*S.A
        @test all(iszero,x.mid for x in p.points)
    end
    p=load_control(c;max_fraction=.5)
    @test p.status==:target_reached
    @test isnan(p.critical)
    @printf("PERFECT STOCKY axial yield=%.6f kN; Newton and Riks closure PASS\n",SY*S.A/1000)
end
