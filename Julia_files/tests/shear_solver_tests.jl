using Test, LinearAlgebra
include(joinpath(@__DIR__,"..","shear_centre.jl"))

const sections = [channel_section(75,200,6), channel_section(75,200,6,12),
    angle_section(75,75,6), angle_section(90,120,5), tee_section(75,200,6,12),
    i_section(75,200,6,12), z_section(75,200,6,12)]

@testset "Closed forms and exact properties" begin
    @test all(last, validation_report())
    p=section_properties(sections[2])
    @test p.A ≈ 3000
    @test p.xc ≈ 22.5
    @test p.yc ≈ 100
    @test p.Ixx ≈ 22e6
    @test p.Iyy ≈ 1_856_250
    @test p.Ixy ≈ 0 atol=1e-10
    r=solve_section(sections[2])
    @test r.centre.x ≈ -30.68181818181818
    @test r.centre.xs ≈ -53.18181818181818
    @test abs(section_properties(sections[end]).Ixy)>1e6
    ir=solve_section(sections[6])
    @test hypot(ir.centre.xs,ir.centre.ys)<1e-9*200
    web=ir.unit_y.walls[3]
    @test web.integral_q ≈ 1
    @test ir.unit_y.walls[1].q_mid ≈ -ir.unit_y.walls[2].q_mid
    @test ir.unit_y.walls[4].q_mid ≈ -ir.unit_y.walls[5].q_mid
    # Diagonal wall own inertia, checked against independent raw polygon-line moments.
    tri=Section(Dict(1=>(0,0),2=>(4,3),3=>(9,3)),[(1,2,2),(2,3,1)])
    tp=section_properties(tri)
    @test tp.A ≈ 15
    @test tp.Ixy ≈ (10*4*3/3+5*6.5*3)-tp.A*tp.xc*tp.yc
end

@testset "Forces, continuity, exact torque, linearity and true stress maximum" begin
    for s in sections, (vx,vy) in [(1.,0.),(0.,1.),(1500.,-2300.),(-7.,9.),(0.,0.)]
        r=solve_section(s;Vx=vx,Vy=vy)
        f=r.applied
        @test [f.Fx,f.Fy] ≈ [vx,vy] atol=1e-9
        @test f.Mz ≈ r.centre.xs*vy-r.centre.ys*vx atol=1e-8
        @test f.continuity_residual < 1e-9
        balance=Dict(id=>0.0 for id in keys(s.nodes))
        for (k,w) in enumerate(f.walls)
            balance[w.i]-=w.q_start; balance[w.j]+=w.q_end
            @test collect(w.coefficients) ≈ vx.*collect(r.unit_x.walls[k].coefficients)+vy.*collect(r.unit_y.walls[k].coefficients) atol=1e-10
            peak=maximum(abs(flow_at(w,x))/w.t for x in range(0,w.L;length=1001))
            @test w.tau_max >= peak-1e-10
            @test w.tau_max ≈ peak rtol=1e-5 atol=1e-10
        end
        @test maximum(abs,values(balance))<1e-9
    end
    # An unsymmetric transverse load has an interior peak away from midpoint.
    f=shear_flow(sections[2],2000.,10000.)
    @test any(w.tau_max > max(abs(w.q_start),abs(w.q_mid),abs(w.q_end))/w.t+1e-5 for w in f.walls)
end

@testset "Rotation, translation, principal axes, orientation and graph order" begin
    angle=.731
    R=[cos(angle) -sin(angle);sin(angle) cos(angle)]
    shift=[1234.,-567.]
    for section in sections
        old=solve_section(section;Vx=31.,Vy=-47.)
        nodes=Dict(k=>Tuple(R*collect(v)+shift) for (k,v) in section.nodes)
        transformed=Section(nodes,section.segments)
        force=R*[31.,-47.]
        new=solve_section(transformed;Vx=force[1],Vy=force[2])
        @test [new.centre.x,new.centre.y] ≈ R*[old.centre.x,old.centre.y]+shift atol=1e-9
        @test [new.centre.xs,new.centre.ys] ≈ R*[old.centre.xs,old.centre.ys] atol=1e-9
        @test new.properties.A ≈ old.properties.A
        @test new.properties.I1 ≈ old.properties.I1
        @test new.properties.I2 ≈ old.properties.I2
        p=old.properties; np=new.properties
        moment=[p.Iyy p.Ixy;p.Ixy p.Ixx]
        @test [np.Iyy np.Ixy;np.Ixy np.Ixx] ≈ R*moment*R'
        pm=p.rotation*moment*p.rotation'
        @test pm[1,2] ≈ 0 atol=1e-8
        @test pm[2,2] ≈ p.I1
        @test pm[1,1] ≈ p.I2
        for (w,rot) in zip(old.applied.walls,new.applied.walls)
            @test collect(w.coefficients) ≈ collect(rot.coefficients) atol=1e-10
        end
        reversed=Section(section.nodes,[(w.j,w.i,w.t) for w in section.segments])
        rev=solve_section(reversed;Vx=31.,Vy=-47.)
        @test [rev.centre.x,rev.centre.y] ≈ [old.centre.x,old.centre.y] atol=1e-9
        for (a,b) in zip(old.applied.walls,rev.applied.walls), fraction in (0.,.3,1.)
            @test flow_at(a,a.L*fraction) ≈ -flow_at(b,b.L*(1-fraction)) atol=1e-10
        end
        # Relabel nodes and reorder edges to change the traversal root.
        remap=Dict(k=>100-k for k in keys(section.nodes))
        shuffled=Section(Dict(remap[k]=>v for (k,v) in section.nodes),
            [(remap[w.i],remap[w.j],w.t) for w in reverse(section.segments)])
        sh=solve_section(shuffled)
        @test [sh.centre.x,sh.centre.y] ≈ [old.centre.x,old.centre.y] atol=1e-9
    end
    # A general branched tree, with more than three arms at a junction.
    star=Section(Dict(1=>(0,0),2=>(3,1),3=>(-2,3),4=>(-4,-2),5=>(2,-4)),
                 [(1,2,.2),(3,1,.4),(1,4,.3),(5,1,.5)])
    r=solve_section(star;Vx=-15,Vy=33)
    @test [r.applied.Fx,r.applied.Fy] ≈ [-15,33]
    @test [r.centre.x,r.centre.y] ≈ [0,0] atol=1e-10
end

@testset "Invalid geometry and unsupported topology" begin
    nodes=Dict(1=>(0,0),2=>(1,0),3=>(1,1),4=>(0,1))
    @test_throws ClosedCellError Section(nodes,[(1,2,1),(2,3,1),(3,4,1),(4,1,1)])
    @test_throws ArgumentError Section(nodes,[(1,2,1),(3,4,1)])
    @test_throws ArgumentError Section(nodes,[(1,2,0)])
    @test_throws ArgumentError Section(nodes,[(1,2,NaN)])
    @test_throws ArgumentError Section(nodes,[(1,5,1)])
    @test_throws ArgumentError Section(nodes,[(1,2,1),(2,1,1)])
    @test_throws ArgumentError Section(Dict(1=>(0,0),2=>(0,0)),[(1,2,1)])
    @test_throws ArgumentError Section(Dict(1=>(0,0),2=>(Inf,0)),[(1,2,1)])
    @test_throws ArgumentError Section(Dict(1=>(0,0),2=>(1,0)),[(1,2,1)];G=-1)
    @test_throws ArgumentError section_properties(Section(Dict(1=>(0,0),2=>(1,0)),[(1,2,1)]))
    @test_throws ArgumentError channel_section(-1,200,6)
    @test_throws ArgumentError shear_flow(sections[1],Inf,0)
    @test_throws ArgumentError flow_at(shear_flow(sections[1],1,0).walls[1],-1)
    @test_throws ArgumentError Section(nodes,[(1,3,1),(3,2,1),(2,4,1)]) # unconnected crossing
    @test_throws ArgumentError Section(Dict(1=>(0,0),2=>(2,0),3=>(1,0)),[(1,2,1),(2,3,1)])
    @test_throws ArgumentError main(["--vx","NaN"])
    @test_throws ArgumentError main(["--example","file.json"])
end

@testset "Solid shortcuts and safe include" begin
    @test rectangular_section(10,20)[1:6] == (200,5,10,10*20^3/12,20*10^3/12,0)
    @test circular_section(10)[7:11] == (10,10,0,0,0)
    @test_throws ArgumentError circular_section(Inf)
end

if "--io" in ARGS
    @testset "JSON round trip" begin
        pushfirst!(LOAD_PATH,joinpath(@__DIR__,"..","shear_solver"))
        try
            section,vx,vy=load_section_json(joinpath(@__DIR__,"..","examples","shear_channel.json"))
            @test (vx,vy)==(2500.,10000.)
            @test section.E==200000
            mktempdir() do dir
                result=solve_section(section;Vx=vx,Vy=vy)
                path=save_results_json(joinpath(dir,"results.json"),result)
                data=Base.invokelatest(() -> JSON.parsefile(path; dicttype=Dict{String,Any}))
                @test data["shear_centre"]["absolute"] ≈ [-30.68181818181818,100]
                @test data["load_cases"]["applied"]["resultant"] ≈ [vx,vy]
                @test data["units"]["tau"]=="N/mm^2"
                geometry_path=joinpath(dir,"section.json")
                write(geometry_path,Base.invokelatest(() -> JSON.json(data["section"])))
                restored,_,_=load_section_json(geometry_path)
                @test restored.nodes==section.nodes
                @test solve_section(restored).centre.x ≈ result.centre.x
            end
        finally
            popfirst!(LOAD_PATH)
        end
    end
end
