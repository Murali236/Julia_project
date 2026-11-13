module AnalysisEngine
using Dates, UUIDs
include("UnitConversion.jl")
include("InputValidation.jl")
include("Modules/BeamAnalysis.jl")
include("Modules/ExtendedAnalysis.jl")
export analyze
function analyze(kind,input)
    kind in ("beam","deflection","shear-centre","buckling","arch") || throw(ArgumentError("Unknown analysis module."))
    beam=kind in ("beam","deflection")
    start=time_ns(); result=beam ? BeamAnalysis.analyze(input) : ExtendedAnalysis.analyze(kind,input)
    normalized=beam ? merge(Dict("nodes"=>Any[],"sections"=>Any[],"evaluationPoints"=>Any[]),input) : input
    return (analysisId=string(uuid4()),analysisType=kind,status="completed",inputSummary=normalized,
            solverMethod=result.solverMethod,results=result.results,plots=result.plots,warnings=result.warnings,
            units=kind=="shear-centre" ? (length="mm",force="N",area="mm²",inertia="mm⁴",flow="N/mm",stress="MPa") :
                  kind=="buckling" ? (length="m",sectionLength="mm",force="kN",stress="MPa",inertia="mm⁴",mode="normalized") :
                  (length="m",force="kN",moment="kN·m",deflection="mm",slope="rad",residualForce="N",residualMoment="N·m"),
            computationMetadata=(softwareVersion="0.1.0",juliaVersion=string(VERSION),
                computedAt=Dates.format(now(UTC),dateformat"yyyy-mm-ddTHH:MM:SS.sss")*"Z",
                elapsedMs=(time_ns()-start)/1e6,meshElements=result.meshElements,
                signConvention=beam ? "Downward applied force/intensity positive; upward displacement/reaction positive; external moments and rotation counterclockwise positive; internal bending moment sagging positive." : result.signConvention))
end
end
