using Test, LinearAlgebra
include(joinpath(@__DIR__,"..","arch_analysis.jl"))
include(joinpath(@__DIR__,"..","arch_legacy.jl"))
using .ArchAnalysis
const OUT=get(ENV,"ARCH_TEST_OUTPUT",mktempdir())
mkpath(OUT)
sec(L;E=200e9,A=0.1,I=0.001,law=:constant)=[Section(0,L,E,A,I;law=law)]
udl(L,w=10000.0)=LineLoad(0,L,0,-w,0,-w)
function checked_force(m)
    s=solve_force(m)
    @test norm(ArchAnalysis.equilibrium(s),Inf)<1e-6
    @test norm(s.F*s.X+s.D)<1e-8
    d=ArchAnalysis.displacement(s,m.geometry.L,s.totals)
    @test abs(d.u)<1e-8
    @test abs(d.v)<1e-8
    m.support==:fixed && (@test abs(d.theta)<1e-8)
    s
end
function checked_frame(m;n=80,name=nothing)
    s=solve_stiffness(m;elements=n)
    @test norm(ArchAnalysis.equilibrium(s),Inf)<0.02
    @test norm((s.K*s.d-s.F)[s.free],Inf)<0.01
    for e in s.elements[1:max(1,div(length(s.elements),7)):end]
        r=frame_response(e,e.L)
        @test r.N ≈ e.forces[4] atol=1e-5
        @test r.Q ≈ -e.forces[5] atol=1e-5
        @test r.M ≈ e.forces[6] atol=1e-5
        @test r.u ≈ e.c*e.d[4]-e.s*e.d[5] atol=1e-9
        @test r.v ≈ e.s*e.d[4]+e.c*e.d[5] atol=1e-9
        @test r.theta ≈ e.d[6] atol=1e-9
    end
    if name!==nothing
        f=isempty(m.springs) ? solve_force(m) : nothing
        export_model(joinpath(OUT,name*".toml"),m,f,s)
    end
    s
end

@testset "Geometry, DOI and validation" begin
    @test doi.([:three_hinged,:two_hinged,:fixed])==[0,1,3]
    for kind in (:parabolic,:circular)
        g=Geometry(kind,20,4)
        @test ordinate(g,0)≈0 atol=1e-12
        @test ordinate(g,20)≈0 atol=1e-12
        @test ordinate(g,10)≈4
        @test tangent(g,10)==(1.0,0.0)
        m=Model(g,:two_hinged,sec(20),[])
        @test integrate(m,x->1.0)>20
    end
    @test_throws ArgumentError Geometry(:circular,20,11)
    @test_throws ArgumentError Geometry(:parabolic,0,1)
    g=Geometry(:parabolic,20,4)
    @test_throws ArgumentError Model(g,:two_hinged,sec(19),[])
    @test_throws ArgumentError Model(g,:two_hinged,sec(20),[PointForce(21,0,-1)])
    @test_throws ArgumentError Model(g,:three_hinged,sec(20),[Couple(10,100)])
    @test_throws ArgumentError Model(g,:two_hinged,sec(20),[udl(20,Inf)])
end

@testset "Three-hinged preservation, local forces and deformation" begin
    for kind in (:parabolic,:circular)
        g=Geometry(kind,20,4)
        loads=[PointForce(7,10000,-25000),LineLoad(2,18,1000,-2000,2000,-5000),Couple(13,7000)]
        m=Model(g,:three_hinged,sec(20),loads)
        f=checked_force(m)
        @test abs(force_response(f,10).M)<1e-8
        old=[ArchLegacy.PointLoad(7,ordinate(g,7),hypot(10000,25000),atand(-25000,10000)),
             ArchLegacy.UDL(2,ordinate(g,2),18,ordinate(g,18),3000,-90),
             ArchLegacy.AppliedMoment(13,ordinate(g,13),7000)]
        # Separate exact input match to original midpoint integration implementation.
        lm=[PointForce(7,10000,-25000),LineLoad(2,18,0,-3000,0,-3000),Couple(13,7000)]
        compare=solve_force(Model(g,:three_hinged,sec(20),lm))
        legacy=ArchLegacy.solve_reactions(old,kind==:parabolic ? 1 : 2,20.,4.)
        @test compare.reactions[[1,2,4,5]] ≈ [legacy.HA,legacy.VA,legacy.HB,legacy.VB] rtol=1e-8
        frame=checked_frame(m;name="three_"*string(kind))
        @test norm(frame.reactions-f.reactions)/norm(f.reactions)<5e-4
        h=frame.hinge
        @test abs(frame.elements[h-1].forces[6])<1e-5
        @test abs(frame.elements[h].forces[3])<1e-5
    end
    m=Model(Geometry(:parabolic,20,4),:three_hinged,sec(20),[udl(20)])
    f=checked_force(m)
    @test f.reactions[1]≈10000*20^2/(8*4)
    @test maximum(abs(force_response(f,x).M) for x in 0:0.25:20)<1e-8
    @test force_response(f,10).N≈-125000
    @test force_response(f,10).Q≈0 atol=1e-8
end

@testset "Textbook dx-weighted example and shallow approximation" begin
    # College Unit 3, pages 9-11; dx-weighting reproduced exactly with I=I0 sec(phi).
    L,f=30.,6.
    m=Model(Geometry(:parabolic,L,f),:two_hinged,sec(L;law=:secant),[PointForce(7.5,0,-60000),PointForce(15,0,-60000)];axial=false)
    s=checked_force(m)
    @test s.reactions[1]/1000≈100.341796875
    @test s.reactions[2:3]≈[75000,0]
    @test force_response(s,7.5).M/1000≈110.9619140625
    @test force_response(s,15).M/1000≈72.94921875
    export_model(joinpath(OUT,"textbook.toml"),m,s,nothing)
    # The quoted axial-shortening formula is a shallow-arch approximation,
    # not the exact finite-rise compatibility including N0*n/EA.
    L,f,A,I=100.,1.,1.,0.001
    s=checked_force(Model(Geometry(:parabolic,L,f),:two_hinged,sec(L;A=A,I=I),[udl(L)]))
    approx=10000L^2/(8f)/(1+15I/(8A*f^2))
    @test s.reactions[1]≈approx rtol=1e-5
    for kind in (:two_hinged,:fixed)
        m=Model(Geometry(:parabolic,20,4),kind,sec(20),[udl(20)];axial=false)
        s=checked_force(m)
        @test s.reactions[1]≈125000
        @test maximum(abs(force_response(s,x).M) for x in 0:0.5:20)<1e-7
    end
    # Semicircular full-UDL bending-only textbook solution: H=4wR/(3pi).
    R=10.;m=Model(Geometry(:circular,2R,R),:two_hinged,sec(2R),[udl(2R)];axial=false)
    s=checked_force(m)
    @test s.reactions[1]≈4*10000R/(3pi) rtol=1e-9
end

@testset "Indeterminate force-frame convergence and elastic center" begin
    for kind in (:two_hinged,:fixed)
        m=Model(Geometry(:parabolic,20,4),kind,sec(20),[udl(20),PointForce(6,0,-15000),Couple(15,12000)])
        f=checked_force(m)
        errors=Float64[]
        for n in (20,40,80)
            k=checked_frame(m;n=n,name=n==80 ? string(kind) : nothing)
            push!(errors,norm(k.reactions-f.reactions))
        end
        @test errors[3]<errors[2]<errors[1]
        @test errors[3]/norm(f.reactions)<0.002
        if kind==:fixed
            @test f.center.x≈10
            @test abs(f.F[1,2])<1e-12
        end
        println("Convergence $kind: reaction error norms (N/N-m) = ",errors)
    end
    # Asymmetric stiffness retains H/V coupling even in elastic-center coordinates.
    g=Geometry(:circular,20,6)
    sections=[Section(0,8,200e9,0.1,0.001),Section(8,20,150e9,0.07,0.0004)]
    m=Model(g,:fixed,sections,[PointForce(3,10000,-8000),LineLoad(5,17,500,-3000,-1500,-6000)])
    f=checked_force(m)
    @test abs(f.F[1,2])>1e-9
    @test abs(f.F[1,3])<1e-12
    @test abs(f.F[2,3])<1e-12
    k=checked_frame(m;n=100,name="variable_circular")
    @test norm(k.reactions-f.reactions)/norm(f.reactions)<0.002
    # Full semicircle endpoint tangents must not make arc-length integration singular.
    m=Model(Geometry(:circular,20,10),:fixed,sec(20),[udl(20)])
    f=checked_force(m)
    @test all(isfinite,f.reactions)
end

@testset "Jumps, polyline geometry, springs, zero loads" begin
    g=Geometry(:parabolic,20,4)
    m=Model(g,:two_hinged,sec(20),[PointForce(7,12000,-9000),Couple(7,5000)])
    f=checked_force(m);left=force_response(f,7;side=:left);right=force_response(f,7)
    c,s=tangent(g,7)
    @test right.M-left.M≈-5000
    @test right.N-left.N≈-(12000c-9000s)
    @test right.Q-left.Q≈-9000c-12000s
    g=Geometry(:polyline,20,5;xs=[0.,5.,11.,20.],ys=[0.,3.,5.,0.])
    m=Model(g,:fixed,sec(20),[LineLoad(2,19,1000,-3000,-500,2000),PointForce(8,-5000,-20000)])
    f=checked_force(m);k=checked_frame(m;n=20,name="polyline")
    @test k.reactions≈f.reactions rtol=1e-7 atol=1e-5
    m=Model(g,:two_hinged,sec(20),[udl(20)];springs=[Spring(7,50000,1e6,5000)])
    @test_throws ArgumentError solve_force(m)
    k=checked_frame(m;n=20,name="spring")
    @test k.springs[1].fy>0
    for kind in (:three_hinged,:two_hinged,:fixed)
        m=Model(Geometry(:parabolic,20,4),kind,sec(20),[])
        f=checked_force(m);k=checked_frame(m;n=10)
        @test maximum(abs,f.reactions)==0
        @test maximum(abs,k.d)==0
    end
end
println("Exported independent-verification fixtures to ",OUT)
