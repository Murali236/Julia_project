using Test, JSON3
include("../src/AnalysisEngine.jl")
const SAMPLE=joinpath(@__DIR__,"../../samples/central-point-load.json")
model()=JSON3.read(read(SAMPLE,String),Dict{String,Any})
@testset "API adapter / analytical benchmarks" begin
    d=model(); r=AnalysisEngine.analyze("beam",d)
    @test r.status=="completed"
    @test r.results.checks.passed
    @test [x.vertical for x in r.results.reactions]≈[5,5]
    @test r.results.extrema[2].maximum.value≈15
    @test r.results.extrema[3].minimum.value≈-28.125
    @test r.results.extrema[3].minimum.x≈3
    @test length(filter(e->e.x==3,r.results.evaluation))==2
    @test occursin("EI",r.results.equations)
    @test JSON3.read(JSON3.write(r)).analysisId==r.analysisId
    d["loads"]=[Dict("type"=>"udl","magnitude"=>10.0,"start"=>0.0,"end"=>6.0)]
    r=AnalysisEngine.analyze("beam",d)
    @test r.results.extrema[2].maximum.value≈45
    @test r.results.extrema[3].minimum.value≈-105.46875
    d=model(); d["supports"]=[Dict("type"=>"fixed","x"=>0)]; d["loads"][1]["x"]=6
    r=AnalysisEngine.analyze("deflection",d)
    @test r.results.extrema[3].minimum.value≈-450
    @test r.results.reactions[1].moment≈60
    d=model(); d["length"]=12
    push!(d["supports"],Dict("id"=>"c","type"=>"roller","x"=>12))
    d["loads"]=[Dict("type"=>"udl","magnitude"=>10,"start"=>0,"end"=>12)]
    r=AnalysisEngine.analyze("beam",d)
    @test [x.vertical for x in r.results.reactions]≈[22.5,75,22.5]
    @test r.results.extrema[2].minimum.value≈-45
    @test r.results.checks.passed
end
@testset "Unit conversion and input contracts" begin
    d=model(); d["length"]=6000;d["units"]["length"]="mm";d["units"]["force"]="N"
    d["supports"][2]["x"]=6000;d["loads"][1]["x"]=3000;d["loads"][1]["magnitude"]=10000;d["evaluationPoints"]=[3000]
    r=AnalysisEngine.analyze("beam",d)
    @test r.results.extrema[2].maximum.value≈15
    @test r.results.extrema[3].minimum.value≈-28.125
    d["loads"]=[Dict("type"=>"udl","magnitude"=>10,"start"=>0,"end"=>6000)]
    @test AnalysisEngine.analyze("beam",d).results.extrema[2].maximum.value≈45
    for mutate in [d->d["units"]["length"]="ft",d->d["length"]=0,d->d["I"]=-1,
                   d->d["loads"][1]["x"]=7,d->d["supports"]=[],d->d["schemaVersion"]=2,
                   d->d["loads"][1]["angle"]=45,d->d["supports"][2]["x"]=0,
                   d->d["E"]=true,d->d["supports"][1]["type"]="free"]
        d=model(); mutate(d)
        @test_throws ArgumentError AnalysisEngine.analyze("beam",d)
    end
    d=model();d["supports"]=[d["supports"][1]]
    @test_throws ArgumentError AnalysisEngine.analyze("beam",d)
    @test_throws ArgumentError AnalysisEngine.analyze("arch",model())
    d=model();for key in ("nodes","sections","evaluationPoints");delete!(d,key);end
    @test all(isempty(AnalysisEngine.analyze("beam",d).inputSummary[key]) for key in ("nodes","sections","evaluationPoints"))
    d=model();d["loads"]=[Dict("type"=>"uvl","magnitude"=>0,"start"=>0,"end"=>6)]
    @test_throws ArgumentError AnalysisEngine.analyze("beam",d)
end
include("legacy_beam_tests.jl")
include("extended_tests.jl")
