sample(name)=JSON3.read(read(joinpath(@__DIR__,"../../samples/$name.json"),String),Dict{String,Any})
@testset "Shear-centre web adapter" begin
    d=sample("shear-channel"); r=AnalysisEngine.analyze("shear-centre",d)
    @test r.results.shear.centre.x ≈ -30.68181818181818
    @test r.results.shear.centre.y ≈ 100
    @test r.results.shear.centroid.x ≈ 22.5
    @test r.results.metrics[4].value ≈ 10.1010101010101
    @test all(c.value<1e-8 for c in r.results.checks)
    @test JSON3.read(JSON3.write(r)).analysisType=="shear-centre"
    for (shape,x,y) in [("i",0.,100.),("z",0.,100.),("tee",0.,200.),("angle",0.,0.)]
        d["section"]=shape; q=AnalysisEngine.analyze("shear-centre",d)
        @test q.results.shear.centre.x ≈ x atol=1e-8
        @test q.results.shear.centre.y ≈ y atol=1e-8
    end
    d=sample("shear-channel");d["Vx"]=0.;d["Vy"]=0.
    @test AnalysisEngine.analyze("shear-centre",d).results.metrics[4].value==0
    for (k,v) in [("tw",0),("b",true),("section","closed"),("Vx",Inf),("unsupported",1)]
        d=sample("shear-channel");d[k]=v
        @test_throws ArgumentError AnalysisEngine.analyze("shear-centre",d)
    end
end
@testset "Buckling web adapter / Euler references" begin
    d=sample("buckling-pinned"); expected=pi^2*200e3*(100*60^3/12)/3000^2/1000
    for (support,factor) in [("pinned_pinned",1.),("fixed_free",.25),("fixed_pinned",(4.493409457909064/pi)^2),("fixed_fixed",4.)]
        d["support"]=support;r=AnalysisEngine.analyze("buckling",d)
        @test r.results.metrics[1].value ≈ expected*factor rtol=1e-4
        @test r.results.checks[1].value<1e-6
        @test maximum(abs,r.results.buckling.mode) ≈ 1 atol=1e-3
        @test abs(r.results.buckling.mode[1])<1e-8
        support!="fixed_free" && @test abs(r.results.buckling.mode[end])<1e-8
        @test length(JSON3.write(r))>0
    end
    d=sample("buckling-pinned"); d["axis"]="x"
    @test AnalysisEngine.analyze("buckling",d).results.metrics[1].value ≈ expected*(100/60)^2 rtol=1e-5
    for shape in ("circle","i"), material in ("elastic","epp","bilinear","ramberg_osgood")
        d=sample("buckling-pinned");d["section"]=shape;d["material"]=material
        @test isfinite(AnalysisEngine.analyze("buckling",d).results.metrics[4].value)
    end
    for (k,v) in [("elements",101),("elements",4.5),("length",0),("axis","z"),("hardeningRatio",1)]
        d=sample("buckling-pinned");d[k]=v
        @test_throws ArgumentError AnalysisEngine.analyze("buckling",d)
    end
end
@testset "Arch web adapter / equilibrium and funicular benchmark" begin
    d=sample("arch-parabolic");r=AnalysisEngine.analyze("arch",d)
    # Parabolic three-hinged arch, uniform load: H=wL²/8f, V=wL/2, M=0.
    @test r.results.metrics[1].value ≈ 125
    @test r.results.metrics[2].value<1e-8
    @test r.results.tables[1].rows[1][3] ≈ 100
    @test r.results.tables[1].rows[2][3] ≈ 100
    @test all(abs(c.value)<1e-8 for c in r.results.checks)
    @test abs(r.results.arch.v[end])<1e-8
    @test length(JSON3.write(r))>0
    for profile in ("parabolic","circular"), support in ("three_hinged","two_hinged","fixed")
        d=sample("arch-parabolic");d["geometry"]=profile;d["support"]=support
        d["loads"]=[Dict("id"=>"p","type"=>"point","x"=>7.,"fx"=>2.,"fy"=>-10.),Dict("id"=>"m","type"=>"moment","x"=>6.,"moment"=>8.),Dict("id"=>"v","type"=>"uvl","start"=>1.,"end"=>15.,"qx"=>0.,"qy"=>0.,"qxEnd"=>1.,"qyEnd"=>-4.)]
        r=AnalysisEngine.analyze("arch",d)
        @test all(abs(c.value)<1e-7 for c in r.results.checks)
        @test abs(r.results.arch.u[end])<1e-7
        @test abs(r.results.arch.v[end])<1e-7
        @test all(all(isfinite,p.values) for p in r.plots)
    end
    d=sample("arch-parabolic");d["axial"]=false
    @test maximum(abs,AnalysisEngine.analyze("arch",d).results.arch.v)<1e-8
    d=sample("arch-parabolic");d["support"]="two_hinged";d["length"]=6;d["hinge"]=10;d["loads"]=[]
    @test AnalysisEngine.analyze("arch",d).results.metrics[1].value==0
    for (k,v) in [("hinge",0),("rise",0),("axial",1),("support","roller")]
        d=sample("arch-parabolic");d[k]=v
        @test_throws ArgumentError AnalysisEngine.analyze("arch",d)
    end
    d=sample("arch-parabolic");d["loads"][1]["end"]=30
    @test_throws ArgumentError AnalysisEngine.analyze("arch",d)
end
