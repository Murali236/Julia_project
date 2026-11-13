# Compatibility entry point for editor Code Runner configurations.
# The original determinate-only script is preserved in legacy/beam_legacy.jl.bak.
include(joinpath(@__DIR__, "sfd_bmd_def.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    exit(run_cli(main))
end
