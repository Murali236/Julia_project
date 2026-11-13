"""
Phase 1 homogeneous, linear elastic, open thin-wall solver.
Coordinates and thickness: mm; forces: N; q: N/mm; stress: N/mm².
All geometry is wall centreline geometry. Positive q follows node i -> node j.
Positive torque is counterclockwise: Mz = xs*Vy - ys*Vx.
"""
module ShearSolver

using LinearAlgebra
export Section, Segment, ClosedCellError, section_properties, shear_flow,
       solve_section, channel_section, angle_section, tee_section, i_section,
       z_section, flow_at, principal_components, validation_report

include("geometry.jl")
include("properties.jl")
include("library.jl")
include("shearflow.jl")
include("shearcentre.jl")

end
