using Test
using LinearAlgebra
include(joinpath(@__DIR__, "..", "src", "Legacy", "beam_stiffness.jl"))
using .BeamStiffness

const E = 200e9
const I = 8e-6
const EI = E*I
nodes(xs...) = [(ID=i,x=Float64(x)) for (i,x) in enumerate(xs)]
support(n,kind; settlement=0.0,k=0.0) = (Node=n,Type=kind,Settlement=settlement,Stiffness=k)
udl(w,a,b) = (Type="UDL",Intensity=w,Start=a,End=b)
uvl(wa,wb,a,b) = (Type="UVL",StartIntensity=wa,EndIntensity=wb,Start=a,End=b)
point(p,x) = (Type="Point Load",Magnitude=p,Location=x)
moment(m,x) = (Type="Moment",Magnitude=m,Location=x)
solve(L,n,s,l;kwargs...) = solve_beam(L,n,s,l;E=E,I=I,kwargs...)
function response(s,x; side=:right)
    indices = findall(e -> e.Start <= x <= e.End,s.elements)
    e = s.elements[side == :right ? last(indices) : first(indices)]
    return element_response(e,x-e.Start)
end

@testset "Stiffness and equivalent loads" begin
    k = element_stiffness(EI,6.0)
    @test issymmetric(k)
    @test norm(k*[1,0,1,0]) < 1e-8
    @test norm(k*[0,1,6,1]) < 1e-8
    @test fixed_end_load(10000,10000,6) ≈ [30000,30000,30000,-30000]
    @test fixed_end_load(0,10000,6) ≈ [9000,12000,21000,-18000]
end

@testset "Determinate regression and empty nodes" begin
    L,P,w = 6.0,10000.0,10000.0
    s = solve(L,nodes(0,L),[support(1,"pin"),support(2,"roller")],[point(P/1000,L/2)])
    @test s.x == [0,3,6] # load position is inserted without asking the user
    @test [r.Vertical for r in s.reactions] ≈ [P/2,P/2]
    @test response(s,3).M ≈ P*L/4
    @test response(s,3).v ≈ -P*L^3/(48EI)
    @test beam_checks(s).passed
    extra = solve(L,nodes(0,2,L),[support(1,"pin"),support(3,"roller")],[point(P/1000,3)])
    for x in range(0,L,length=25), field in (:V,:M,:theta,:v)
        @test isapprox(getproperty(response(s,x),field),getproperty(response(extra,x),field);atol=1e-7,rtol=1e-9)
    end
    @test beam_checks(extra).passed
    s = solve(L,nodes(0,L),[support(1,"pin"),support(2,"roller")],[udl(w/1000,0,L)])
    @test response(s,L/2).v ≈ -5w*L^4/(384EI)
    @test response(s,L/2).M ≈ w*L^2/8
    @test beam_checks(s).passed
    s = solve(L,nodes(0,L),[support(1,"fixed")],[point(P/1000,L)])
    @test response(s,L).v ≈ -P*L^3/(3EI)
    @test response(s,L).theta ≈ -P*L^2/(2EI)
    @test s.reactions[1].Moment ≈ P*L
    @test beam_checks(s).passed
    # End nodes are also added automatically for an overhanging beam.
    s = solve(L,nodes(1,5),[support(1,"pin"),support(2,"roller")],[udl(10,0,L)])
    @test s.x == [0,1,5,6]
    @test [r.Vertical for r in s.reactions] ≈ [30000,30000]
    @test response(s,1).M ≈ -5000
    @test beam_checks(s).passed
end

@testset "Fixed-fixed UDL and point load" begin
    L,w,P = 6.0,10000.0,12000.0
    supports = [support(1,"fixed"),support(2,"fixed")]
    s = solve(L,nodes(0,L),supports,[udl(w/1000,0,L)])
    @test [r.Vertical for r in s.reactions] ≈ [w*L/2,w*L/2]
    @test [r.Moment for r in s.reactions] ≈ [w*L^2/12,-w*L^2/12]
    @test response(s,L/2).v ≈ -w*L^4/(384EI)
    @test response(s,L/2).M ≈ w*L^2/24
    @test beam_checks(s).passed
    samples = sample_beam(s;points_per_element=2)
    @test minimum(samples.v_mm) ≈ -1000w*L^4/(384EI) # exact, not mesh sampled
    @test samples.zero_shear ≈ [L/2]
    s = solve(L,nodes(0,L),supports,[point(P/1000,L/2)])
    @test [r.Moment for r in s.reactions] ≈ [P*L/8,-P*L/8]
    @test response(s,L/2).v ≈ -P*L^3/(192EI)
    @test beam_checks(s).passed
end

@testset "Propped cantilever and two-span continuous beam" begin
    L,w = 6.0,10000.0
    s = solve(L,nodes(0,L),[support(1,"fixed"),support(2,"roller")],[udl(w/1000,0,L)])
    @test [r.Vertical for r in s.reactions] ≈ [5w*L/8,3w*L/8]
    @test s.reactions[1].Moment ≈ w*L^2/8
    @test beam_checks(s).passed
    x = 2.3
    expected = -w*x^2*(6L^2-4L*x+x^2)/(24EI)+(3w*L/8)*x^2*(3L-x)/(6EI)
    @test response(s,x).v ≈ expected
    s = solve(2L,nodes(0,L,2L),[support(1,"pin"),support(2,"roller"),support(3,"roller")],[udl(w/1000,0,2L)])
    @test [r.Vertical for r in s.reactions] ≈ [3w*L/8,5w*L/4,3w*L/8]
    @test response(s,L).M ≈ -w*L^2/8
    @test response(s,L;side=:left).M ≈ response(s,L).M
    @test sample_beam(s).zero_shear ≈ [3L/8,2L-3L/8]
    @test beam_checks(s).passed
end

@testset "Varying EI and automatic section nodes" begin
    L,a,P,w = 6.0,2.0,10000.0,10000.0
    sections = [(Start=0.0,End=a,E=E,I=I),(Start=a,End=L,E=2E,I=I)]
    s = solve(L,nodes(0,L),[support(1,"fixed")],[point(P/1000,L)];sections=sections)
    @test s.x == [0,a,L]
    expected_v = -P*((L^3-(L-a)^3)/(3EI)+(L-a)^3/(6EI))
    expected_theta = -P*((L^2-(L-a)^2)/(2EI)+(L-a)^2/(4EI))
    @test response(s,L).v ≈ expected_v
    @test response(s,L).theta ≈ expected_theta
    @test response(s,a).M ≈ response(s,a;side=:left).M
    @test beam_checks(s).passed
    s = solve(L,nodes(0,L),[support(1,"fixed"),support(2,"roller")],[udl(w/1000,0,L)];sections=sections)
    integral3 = (L^4-(L-a)^4)/(4EI)+(L-a)^4/(8EI)
    integral2 = (L^3-(L-a)^3)/(3EI)+(L-a)^3/(6EI)
    @test s.reactions[2].Vertical ≈ w/2*integral3/integral2
    @test beam_checks(s).passed
end

@testset "Settlements and springs" begin
    L,delta,k,P = 6.0,-0.01,50000.0,10000.0
    s = solve(L,nodes(0,L),[support(1,"pin"),support(2,"roller";settlement=delta)],[])
    @test response(s,3).v ≈ delta/2
    @test response(s,3).theta ≈ delta/L
    @test abs(response(s,3).M) < 1e-7
    @test beam_checks(s).passed
    s = solve(L,nodes(0,L),[support(1,"fixed"),support(2,"fixed";settlement=delta)],[])
    expected = element_stiffness(EI,L)*[0,0,delta,0]
    @test s.reactions[1].Vertical ≈ expected[1]
    @test s.reactions[1].Moment ≈ expected[2]
    @test s.reactions[2].Vertical ≈ expected[3]
    @test s.reactions[2].Moment ≈ expected[4]
    @test beam_checks(s).passed
    s = solve(L,nodes(0,L),[support(1,"fixed"),support(2,"spring";k=k)],[point(P/1000,L)])
    tip = -P/(3EI/L^3+k)
    @test response(s,L).v ≈ tip
    @test s.reactions[2].Vertical ≈ -k*tip
    @test beam_checks(s).passed
    s = solve(L,nodes(0,L),[support(1,"fixed"),support(2,"spring";k=k,settlement=delta)],[])
    @test response(s,L).v ≈ k*delta/(3EI/L^3+k)
    @test s.reactions[2].Vertical ≈ k*(delta-response(s,L).v)
    @test beam_checks(s).passed
    s = solve(L,nodes(0,L),[support(1,"spring";k=k),support(2,"spring";k=k)],[udl(10,0,L)])
    @test [r.Vertical for r in s.reactions] ≈ [30000,30000]
    @test s.d[1] ≈ -30000/k
    @test beam_checks(s).passed
end

@testset "UVL, overlaps, applied moments, and jumps" begin
    L,w = 6.0,10000.0
    supports = [support(1,"pin"),support(2,"roller")]
    s = solve(L,nodes(0,L),supports,[uvl(0,w/1000,0,L)])
    @test [r.Vertical for r in s.reactions] ≈ [w*L/6,w*L/3]
    @test response(s,L/2).M ≈ w*L^2/16
    @test sample_beam(s).zero_shear ≈ [L/sqrt(3)]
    @test beam_checks(s).passed
    # Equal/opposite intensities have zero resultant force but a nonzero couple.
    s = solve(L,nodes(0,L),supports,[uvl(10,-10,0,L)])
    @test [r.Vertical for r in s.reactions] ≈ [10000,-10000]
    @test beam_checks(s).passed
    s = solve(L,nodes(0,L),[support(1,"fixed")],[moment(10,L)])
    @test response(s,L).v ≈ 10000L^2/(2EI)
    @test response(s,L).theta ≈ 10000L/EI
    @test s.reactions[1].Moment ≈ -10000
    @test beam_checks(s).passed
    s = solve(L,nodes(0,L),supports,[point(8,2),moment(5,2),udl(4,1,4),uvl(-2,3,3,5)])
    @test s.x == [0,1,2,3,4,5,6]
    left,right = response(s,2;side=:left),response(s,2)
    @test right.V-left.V ≈ -8000
    @test right.M-left.M ≈ -5000
    @test right.v ≈ left.v
    @test right.theta ≈ left.theta
    @test beam_checks(s).passed
    # Nodal loads applied at a constrained node must still enter its reaction.
    s = solve(L,nodes(0,L),[support(1,"fixed")],[point(8,0),moment(5,0)])
    @test s.reactions[1].Vertical ≈ 8000
    @test s.reactions[1].Moment ≈ -5000
    @test maximum(abs,s.d) == 0
    @test beam_checks(s).passed
end

@testset "Invalid and unstable models" begin
    n = nodes(0,6)
    @test_throws ArgumentError solve(6,n,[],[])
    @test_throws ArgumentError solve(6,n,[support(1,"pin")],[])
    @test_throws ArgumentError solve(6,n,[support(1,"spring";k=1000)],[])
    @test_throws ArgumentError solve(6,n,[support(1,"spring";k=-1)],[])
    @test_throws ArgumentError solve(6,n,[support(1,"fixed")],[point(1,7)])
    @test_throws ArgumentError solve(6,n,[support(1,"fixed")],[udl(1,3,2)])
    @test_throws ArgumentError solve(6,n,[support(1,"fixed")],[moment(Inf,3)])
    @test_throws ArgumentError solve(6,n,[support(1,"fixed"),support(1,"roller")],[])
    @test_throws ArgumentError solve(6,n,[support(1,"fixed")],[];sections=[(Start=0,End=5,E=E,I=I)])
    @test_throws ArgumentError solve(6,n,[support(1,"fixed")],[];sections=[(Start=0,End=6,E=-E,I=I)])
    s = solve(6,n,[support(1,"pin"),support(2,"roller")],[])
    @test maximum(abs,s.d) == 0
    @test beam_checks(s).passed
    @test occursin("VERIFICATION: PASS",beam_report(s))
    @test sample_beam(s).zero_shear_intervals == [(0.0,6.0)]
end
