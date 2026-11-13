using Plots
using Printf
include(joinpath(@__DIR__, "cli_support.jl"))
using .AnalysisCLI
include(joinpath(@__DIR__, "buckling_core.jl"))
using .BucklingCore
include(joinpath(@__DIR__, "buckling_plots.jl"))

# ================================================================
#                   EULER BUCKLING ANALYSIS
#
# Supported sections:
#
#   1. Rectangle
#   2. Circle
#   3. I Section
#   4. T Section
#   5. L Section
#   6. C / Channel Section
#
# The program calculates:
#
#   Area
#   Centroid
#   Ix
#   Iy
#   Radius of gyration
#   Effective length
#   Slenderness ratio
#   Euler critical load
#   Critical stress
#   Factor of safety
#
# ================================================================


# ================================================================
# INPUT FUNCTIONS
# ================================================================

function read_positive(prompt)
    while true
        print(prompt)
        eof(stdin) && throw(EOFError())

        try
            value = parse(Float64, readline())

            if isfinite(value) && value > 0
                return value
            else
                println("Value must be greater than zero.")
            end

        catch
            println("Invalid input. Please enter a number.")
        end
    end
end


function read_integer(prompt, minvalue, maxvalue)
    while true
        print(prompt)
        eof(stdin) && throw(EOFError())

        try
            value = parse(Int, readline())

            if minvalue <= value <= maxvalue
                return value
            else
                println("Please enter a value between $minvalue and $maxvalue.")
            end

        catch
            println("Invalid input.")
        end
    end
end


# ================================================================
# RECTANGLE DATA STRUCTURE
#
# Used for calculating composite sections such as:
#
# I
# T
# L
# C
#
# x, y = lower-left corner of rectangle
#
# ================================================================

# ================================================================
# SECTION INPUT
# ================================================================

function get_section_properties(; geometry=false)

    println()
    println("================================================")
    println("              SELECT CROSS SECTION")
    println("================================================")
    println()
    println("1. Rectangle")
    println("2. Circle")
    println("3. I Section")
    println("4. T Section")
    println("5. L Section")
    println("6. C / Channel Section")
    println()

    choice = read_integer(
        "Enter section type (1-6): ",
        1,
        6
    )


    # ============================================================
    # RECTANGLE
    # ============================================================

    if choice == 1

        println()
        println("RECTANGULAR SECTION")
        println("-------------------")

        b = read_positive("Enter width b (m): ")
        h = read_positive("Enter height h (m): ")


        A = b * h

        Ix = b * h^3 / 12

        Iy = h * b^3 / 12

        xbar = b / 2
        ybar = h / 2

        section_name = "Rectangle"
        parts = [RectPart(b, h, 0.0, 0.0)]


    # ============================================================
    # CIRCLE
    # ============================================================

    elseif choice == 2

        println()
        println("CIRCULAR SECTION")
        println("----------------")

        D = read_positive("Enter diameter D (m): ")


        A = π * D^2 / 4

        Ix = π * D^4 / 64

        Iy = Ix

        xbar = D / 2
        ybar = D / 2

        section_name = "Circle"


    # ============================================================
    # I SECTION
    #
    #
    #       <------ B ------>
    #       ┌───────────────┐
    #       │               │ tf
    #       └───────┬───────┘
    #               │
    #               │ tw
    #               │
    #       ┌───────┴───────┐
    #       │               │ tf
    #       └───────────────┘
    #
    # Total height = H
    #
    # ============================================================

    elseif choice == 3

        println()
        println("I SECTION")
        println("---------")

        B  = read_positive("Enter flange width B (m): ")
        H  = read_positive("Enter total height H (m): ")
        tf = read_positive("Enter flange thickness tf (m): ")
        tw = read_positive("Enter web thickness tw (m): ")


        if 2 * tf >= H
            error("Flange thickness is too large.")
        end

        if tw > B
            error("Web thickness cannot exceed flange width.")
        end


        web_height = H - 2 * tf


        parts = [

            # Bottom flange
            RectPart(B, tf, 0.0, 0.0),

            # Web
            RectPart(
                tw,
                web_height,
                (B - tw) / 2,
                tf
            ),

            # Top flange
            RectPart(
                B,
                tf,
                0.0,
                H - tf
            )
        ]


        A, xbar, ybar, Ix, Iy =
            composite_properties(parts)

        section_name = "I Section"


    # ============================================================
    # T SECTION
    #
    #
    #       ┌───────────────┐
    #       │    FLANGE     │
    #       └───────┬───────┘
    #               │
    #               │ WEB
    #               │
    #
    # ============================================================

    elseif choice == 4

        println()
        println("T SECTION")
        println("---------")

        B  = read_positive("Enter flange width B (m): ")
        H  = read_positive("Enter total height H (m): ")
        tf = read_positive("Enter flange thickness tf (m): ")
        tw = read_positive("Enter web thickness tw (m): ")


        if tf >= H
            error("Flange thickness must be smaller than total height.")
        end

        if tw > B
            error("Web thickness cannot exceed flange width.")
        end


        web_height = H - tf


        parts = [

            # Web
            RectPart(
                tw,
                web_height,
                (B - tw) / 2,
                0.0
            ),

            # Top flange
            RectPart(
                B,
                tf,
                0.0,
                H - tf
            )
        ]


        A, xbar, ybar, Ix, Iy =
            composite_properties(parts)

        section_name = "T Section"


    # ============================================================
    # L SECTION
    #
    #
    #       │
    #       │
    #       │
    #       │
    #       └──────────
    #
    # Equal or unequal legs can be entered.
    #
    # ============================================================

    elseif choice == 5

        println()
        println("L SECTION")
        println("---------")

        H = read_positive("Enter vertical leg height H (m): ")

        B = read_positive(
            "Enter horizontal leg width B (m): "
        )

        tv = read_positive(
            "Enter vertical leg thickness tv (m): "
        )

        th = read_positive(
            "Enter horizontal leg thickness th (m): "
        )


        if tv >= B
            error("Vertical leg thickness must be smaller than width.")
        end

        if th >= H
            error("Horizontal leg thickness must be smaller than height.")
        end


        # Non-overlapping rectangles

        parts = [

            # Vertical leg
            RectPart(
                tv,
                H,
                0.0,
                0.0
            ),

            # Horizontal leg excluding overlap
            RectPart(
                B - tv,
                th,
                tv,
                0.0
            )
        ]


        A, xbar, ybar, Ix, Iy =
            composite_properties(parts)

        section_name = "L Section"


    # ============================================================
    # C / CHANNEL SECTION
    #
    #
    #       ┌──────────────
    #       │
    #       │
    #       │
    #       └──────────────
    #
    # ============================================================

    elseif choice == 6

        println()
        println("C / CHANNEL SECTION")
        println("-------------------")

        B = read_positive(
            "Enter flange width B (m): "
        )

        H = read_positive(
            "Enter total height H (m): "
        )

        tf = read_positive(
            "Enter flange thickness tf (m): "
        )

        tw = read_positive(
            "Enter web thickness tw (m): "
        )


        if 2 * tf >= H
            error("Flange thickness is too large.")
        end

        if tw >= B
            error("Web thickness must be smaller than flange width.")
        end


        web_height = H - 2 * tf


        parts = [

            # Web
            RectPart(
                tw,
                web_height,
                0.0,
                tf
            ),

            # Bottom flange
            RectPart(
                B,
                tf,
                0.0,
                0.0
            ),

            # Top flange
            RectPart(
                B,
                tf,
                0.0,
                H - tf
            )
        ]


        A, xbar, ybar, Ix, Iy =
            composite_properties(parts)

        section_name = "C / Channel Section"
    end


    if geometry
        return choice == 2 ? section_properties(D) : section_properties(parts; name=section_name)
    end
    return section_name, A, xbar, ybar, Ix, Iy
end


# ================================================================
# SUPPORT CONDITION
# ================================================================

function get_support_condition()

    println()
    println("================================================")
    println("            COLUMN SUPPORT CONDITION")
    println("================================================")
    println()

    println("1. Pinned - Pinned")
    println("2. Fixed - Free")
    println("3. Fixed - Pinned")
    println("4. Fixed - Fixed")
    println("5. Enter custom effective-length factor K")
    println()


    choice = read_integer(
        "Select support condition (1-5): ",
        1,
        5
    )


    if choice == 1

        K = 1.0

        support_name = "Pinned - Pinned"


    elseif choice == 2

        K = 2.0

        support_name = "Fixed - Free"


    elseif choice == 3

        K = 0.699

        support_name = "Fixed - Pinned"


    elseif choice == 4

        K = 0.5

        support_name = "Fixed - Fixed"


    else

        K = read_positive(
            "Enter effective-length factor K: "
        )

        support_name = "Custom"
    end


    return K, support_name
end


# ================================================================
# MAIN PROGRAM
# ================================================================

function main()

println()
println("================================================")
println("           EULER COLUMN BUCKLING")
println("================================================")


# ================================================================
# GENERAL COLUMN INPUTS
# ================================================================

println()
println("COLUMN PROPERTIES")
println("-----------------")

L = read_positive(
    "Enter actual column length L (m): "
)

E_GPa = read_positive(
    "Enter Young's modulus E (GPa): "
)

P_kN = read_positive(
    "Enter applied axial load P (kN): "
)


# Convert units

E = E_GPa * 1e9

P = P_kN * 1000


# ================================================================
# SECTION PROPERTIES
# ================================================================

section = get_section_properties(; geometry=true)
section_name, A, xbar, ybar, Ix, Iy = section.name, section.A, section.xbar, section.ybar, section.Ix, section.Iy


# ================================================================
# SUPPORT CONDITION
# ================================================================

K, support_name = get_support_condition()


# ================================================================
# SELECT BUCKLING AXIS
# ================================================================

println()
println("================================================")
println("              BUCKLING AXIS")
println("================================================")
println()

println("1. x-x axis")
println("2. y-y axis")
println("3. Automatically use weaker axis")
println()


axis_choice = read_integer(
    "Select buckling axis (1-3): ",
    1,
    3
)


if axis_choice == 1

    I = Ix

    buckling_axis = "x-x"


elseif axis_choice == 2

    I = Iy

    buckling_axis = "y-y"


else

    if Ix <= Iy

        I = Ix

        buckling_axis = "x-x (weaker axis)"

    else

        I = Iy

        buckling_axis = "y-y (weaker axis)"

    end

end


# ================================================================
# SECTION PROPERTIES
# ================================================================

println("\nANALYSIS TYPE")
println("1. Original Euler analysis")
println("2. Elastic FEM + Euler comparison")
println("3. Level 1 tangent-modulus + elastic FEM")
println("4. Level 2 fiber FEM + Level 1 + elastic FEM")
analysis = read_integer("Select analysis (1-4): ",1,4)
fe = nothing; material = nothing; nonlinear = nothing; model = nothing; elastic_path = nothing
bc = :pinned_pinned; n = 16
axis = axis_choice == 1 || (axis_choice == 3 && Ix <= Iy) ? :x : :y
if section_name == "L Section"
    println("NOTE: x/y are centroidal coordinate axes, not principal axes; analysis is constrained to the selected plane.")
end
if analysis >= 2
    supports = [:pinned_pinned,:fixed_free,:fixed_pinned,:fixed_fixed]
    names = ["Pinned - Pinned","Fixed - Free","Fixed - Pinned","Fixed - Fixed"]
    if support_name == "Custom"
        println("Custom K is retained for closed-form results. FEM needs physical restraints.")
        println("1. Pinned-pinned  2. Fixed-free  3. Fixed-pinned  4. Fixed-fixed")
        bc = supports[read_integer("FEM restraint model (1-4): ",1,4)]
    else
        bc = supports[findfirst(==(support_name),names)]
    end
    n = read_integer("Number of beam elements (2-200; suggested 16): ",2,200)
    fe = solve_eigen(E*I,L,n,bc)
end
if analysis >= 3
    sy = read_positive("Yield / 0.2% proof stress (MPa): ")*1e6
    println("1. Elastic-perfectly plastic  2. Bilinear hardening  3. Ramberg-Osgood")
    mc = read_integer("Material law (1-3): ",1,3)
    ratio = 0.01; exponent = 6.0
    if mc == 2
        ratio = read_positive("Post-yield tangent / E (greater than 0, less than 1): ")
        while ratio >= 1
            println("Hardening ratio must be less than 1.")
            ratio = read_positive("Post-yield tangent / E: ")
        end
    elseif mc == 3
        exponent = read_positive("Ramberg-Osgood exponent n (greater than 1; suggested 6): ")
        while exponent <= 1
            exponent = read_positive("Exponent must be greater than 1: ")
        end
        println("RO: ε=σ/E+0.002(σ/σy)^n; isotropic hardening, elastic unloading.")
    end
    material = Material(E,sy;model=[:epp,:bilinear,:ramberg_osgood][mc],ratio,exponent)
end
if analysis == 4
    layers = read_integer("Fiber layers per rectangle / radial bands (2-100; suggested 24): ",2,100)
    println("1. Default L/1000  2. L/500  3. Perfectly straight  4. Custom amplitude")
    ic = read_integer("Initial imperfection (1-4): ",1,4)
    imperfection = ic==1 ? L/1000 : ic==2 ? L/500 : ic==3 ? 0.0 : read_positive("Imperfection amplitude (mm): ")/1000
    println("Imperfection follows the first FEM mode, satisfying the selected restraints.")
    println("1. No residual stress  2. Self-equilibrated parabolic residual stress")
    rc = read_integer("Residual stress (1-2): ",1,2)
    residual_fraction = rc==1 ? 0.0 : read_positive("Peak residual stress / σy (less than 1): ")
    while residual_fraction >= 1
        residual_fraction = read_positive("Fraction must be less than 1: ")
    end
    model = ColumnModel(section,material,L,n,bc;axis,imperfection,layers,residual_fraction)
    println("1. Newton load control  2. Riks arc length (traces past peak)")
    solver = read_integer("Nonlinear solver (1-2): ",1,2)
    if solver==1
        increment = read_positive("Load increment / min(Py, Pe) (suggested 0.025): ")
        target = read_positive("Target load / min(Py, Pe) (suggested 1.1): ")
        nonlinear = load_control(model;step_fraction=increment,max_fraction=target)
    else
        ds = read_positive("Dimensionless arc step (suggested 0.0005): ")
        nonlinear = riks_solver(model;ds,maxsteps=600)
    end
    em = Material(E,sy;model=:elastic)
    ec = ColumnModel(section,em,L,n,bc;axis,imperfection,layers,residual_fraction)
    elastic_path = riks_solver(ec;ds=0.0005,maxsteps=600)
end

rx = sqrt(Ix / A)

ry = sqrt(Iy / A)

r = sqrt(I / A)


# ================================================================
# EFFECTIVE LENGTH
# ================================================================

Le = K * L


# ================================================================
# SLENDERNESS RATIO
# ================================================================

λx = Le / rx

λy = Le / ry

λ = Le / r


# ================================================================
# EULER CRITICAL LOAD
#
#             π² E I
# Pcr = -----------------
#              Le²
#
# ================================================================

Pcr = π^2 * E * I / Le^2


# ================================================================
# CRITICAL STRESS
#
#           Pcr
# σcr = -----------
#            A
#
# ================================================================

σcr = Pcr / A


# ================================================================
# APPLIED STRESS
# ================================================================

σapplied = P / A


# ================================================================
# FACTOR OF SAFETY
# ================================================================

FS = Pcr / P


# ================================================================
# DISPLAY RESULTS
# ================================================================

println()
println()
println("================================================")
println("             BUCKLING ANALYSIS RESULTS")
println("================================================")

println()

@printf(
    "Section Type              : %s\n",
    section_name
)

@printf(
    "Support Condition         : %s\n",
    support_name
)

@printf(
    "Effective Length Factor K : %.4f\n",
    K
)

@printf(
    "Buckling Axis             : %s\n",
    buckling_axis
)

println()
println("---------------- SECTION PROPERTIES ----------------")

@printf(
    "Cross-sectional Area A    = %.8f m²\n",
    A
)

@printf(
    "Centroid x̄               = %.6f m\n",
    xbar
)

@printf(
    "Centroid ȳ               = %.6f m\n",
    ybar
)

@printf(
    "Ix                        = %.8e m⁴\n",
    Ix
)

@printf(
    "Iy                        = %.8e m⁴\n",
    Iy
)

@printf(
    "Governing I               = %.8e m⁴\n",
    I
)

println()
println("---------------- RADIUS OF GYRATION ----------------")

@printf(
    "rx                        = %.6f m\n",
    rx
)

@printf(
    "ry                        = %.6f m\n",
    ry
)

@printf(
    "Governing r               = %.6f m\n",
    r
)

println()
println("---------------- COLUMN PROPERTIES ----------------")

@printf(
    "Actual Length L           = %.4f m\n",
    L
)

@printf(
    "Effective Length Le       = %.4f m\n",
    Le
)

@printf(
    "Slenderness λx            = %.3f\n",
    λx
)

@printf(
    "Slenderness λy            = %.3f\n",
    λy
)

@printf(
    "Governing Slenderness λ   = %.3f\n",
    λ
)

println()
println("---------------- BUCKLING RESULTS ----------------")

@printf(
    "Young's Modulus E         = %.3f GPa\n",
    E / 1e9
)

@printf(
    "Applied Load P            = %.3f kN\n",
    P / 1000
)

@printf(
    "Applied Stress            = %.3f MPa\n",
    σapplied / 1e6
)

@printf(
    "Euler Critical Load Pcr   = %.3f kN\n",
    Pcr / 1000
)

@printf(
    "Critical Stress σcr       = %.3f MPa\n",
    σcr / 1e6
)

@printf(
    "Factor of Safety          = %.3f\n",
    FS
)


# ================================================================
# BUCKLING ASSESSMENT
# ================================================================

println()
println("---------------- ASSESSMENT ----------------")

tolerance = 1e-6 * Pcr


if P < Pcr - tolerance

    println("STATUS : SAFE AGAINST EULER BUCKLING")

    println(
        "Applied load is below the Euler critical load."
    )


elseif abs(P - Pcr) <= tolerance

    println("STATUS : CRITICAL")

    println(
        "Applied load is approximately equal to the Euler critical load."
    )


else

    println("STATUS : BUCKLING FAILURE")

    println(
        "Applied load exceeds the Euler critical load."
    )

end


if !isnothing(fe)
    println("\n---------------- ELASTIC FEM ----------------")
    @printf("Elastic FEM Pcr           = %.6f kN\n",fe.Pcr/1000)
    @printf("Closed-form Euler Pcr     = %.6f kN\n",Pcr/1000)
    @printf("FEM vs Euler difference   = %+.6f %%\n",100*(fe.Pcr/Pcr-1))
    support_name == "Custom" && println("NOTE: custom K and the selected FEM restraints may describe different columns.")
end
if !isnothing(material)
    # Physical FEM effective slenderness for Levels 1/2; custom K remains legacy-only.
    λfem = π*sqrt(E*A/fe.Pcr)
    level1 = tangent_buckling(material,λfem)
    Py = material.sy*A
    println("\n---------------- INELASTIC RESULTS ----------------")
    @printf("Yield / proof load Py     = %.6f kN\n",Py/1000)
    @printf("Level 1 critical stress   = %.6f MPa (%s)\n",level1.stress/1e6,string(level1.status))
    @printf("Euler validity limit λc   = %.4f\n",π*sqrt(E/material.sy))
    governing = min(Py,level1.stress*A)
    failure = governing >= Py*(1-1e-8) ? "yielding (nominal Py cap)" : level1.status==:elastic ? "elastic buckling" : "inelastic buckling"
    if !isnothing(nonlinear)
        @printf("Level 2 sampled Pmax      = %.6f kN\n",nonlinear.Pmax/1000)
        println("Continuation status       = ",nonlinear.status)
        println("Instability evidence      = ",nonlinear.event)
        if isfinite(nonlinear.critical)
            @printf("Level 2 critical estimate = %.6f kN\n",nonlinear.critical/1000)
            @printf("Event adjacent loads      = %.6f, %.6f kN\n",nonlinear.bracket[1]/1000,nonlinear.bracket[2]/1000)
            governing=min(Py,nonlinear.critical)
            plastic=maximum(maximum(p.yielded) for p in nonlinear.points)>0
            failure=governing>=Py*(1-1e-8) ? "yielding (nominal Py cap)" : plastic ? "inelastic buckling" : "elastic buckling"
        else
            governing=NaN; failure="not established: no instability event on computed path"
            println("Sampled Pmax is only a converged load, NOT a detected critical load.")
        end
        last=nonlinear.points[end]
        @printf("Final load                = %.6f kN\n",last.P/1000)
        @printf("Final midspan deflection  = %.6f mm\n",last.mid*1000)
        @printf("Final maximum deflection  = %.6f mm\n",maximum(abs,sample_shape(model,last.q).w)*1000)
        @printf("Final axial end movement  = %.6f mm\n",last.axial*1000)
        plastlength=sum(BucklingCore.GAUSS_W[g]*L/n for e in 1:n for g in 1:4 if last.yielded[e,g]>0;init=0.0)
        @printf("Length with plastic fibers≈ %.6f m (quadrature estimate)\n",plastlength)
        @printf("Max plastic area fraction = %.3f %%\n",100maximum(last.yielded))
        @printf("Max equilibrium residual  = %.3e (scaled)\n",maximum(p.residual for p in nonlinear.points))
    end
    println("Governing failure mode    = ",failure)
    if isfinite(governing)
        @printf("Governing load            = %.6f kN\n",governing/1000)
        @printf("Governing factor of safety= %.6f\n",governing/P)
    else
        println("Governing factor of safety= not established")
    end
    BucklingPlots.save_extended_plots(model,nonlinear,elastic_path,material,λfem)
end

# ================================================================
# PLOT 1
#
# NORMALIZED BUCKLING SHAPE
# ================================================================

x = range(
    0,
    L,
    length=300
)


# Normalized illustrative first mode
#
# The actual modal shape depends upon boundary conditions.
# This shape is primarily for visualisation.

if abs(K - 1.0) < 1e-6

    # Pinned-pinned
    y = sin.(π .* x ./ L)

elseif abs(K - 2.0) < 1e-6

    # Fixed-free approximate mode
    y = 1 .- cos.(π .* x ./ (2 * L))

elseif abs(K - 0.5) < 1e-6

    # Fixed-fixed illustrative mode
    y = 1 .- cos.(2 .* π .* x ./ L)

else

    # General illustrative shape
    y = sin.(π .* x ./ L)

end


if !isnothing(fe)
    # Hermite interpolation of the computed eigenvector, including rotations.
    y = [begin
        e=min(floor(Int,xi/(L/n))+1,n)
        ξ=(xi-(e-1)*L/n)/(L/n)
        sum(hermite(ξ,L/n)[1].*fe.mode[2*e-1:2*e+2])
    end for xi in x]
end

p1 = plot(
    x,
    y,

    linewidth=3,

    xlabel="Column Length (m)",

    ylabel="Normalized Lateral Deflection",

    title="First Buckling Mode - $section_name",

    label="Buckling Shape",

    grid=true
)


savefig(
    p1,
    "buckling_shape.png"
)


# ================================================================
# PLOT 2
#
# CRITICAL LOAD VS COLUMN LENGTH
# ================================================================

minimum_length =
    max(0.1, 0.25 * L)

maximum_length =
    2.0 * L


lengths = range(
    minimum_length,
    maximum_length,
    length=200
)


critical_loads = [

    π^2 * E * I /
    (K * Li)^2 /
    1000

    for Li in lengths
]


p2 = plot(

    lengths,

    critical_loads,

    linewidth=3,

    xlabel="Column Length (m)",

    ylabel="Euler Critical Load (kN)",

    title="Critical Load vs Column Length",

    label="Pcr",

    grid=true
)


# Mark the current column

scatter!(
    p2,

    [L],

    [Pcr / 1000],

    markersize=7,

    label="Current Column"
)


savefig(
    p2,
    "critical_load_vs_length.png"
)


# ================================================================
# PLOT 3
#
# CRITICAL STRESS VS SLENDERNESS
#
# Euler relation:
#
#             π² E
# σcr = ----------------
#              λ²
#
# ================================================================

λ_start = max(
    10.0,
    0.25 * λ
)

λ_end = max(
    200.0,
    2.0 * λ
)


slenderness = range(
    λ_start,
    λ_end,
    length=300
)


critical_stress = [

    π^2 * E /
    λi^2 /
    1e6

    for λi in slenderness
]


p3 = plot(

    slenderness,

    critical_stress,

    linewidth=3,

    xlabel="Slenderness Ratio λ",

    ylabel="Euler Critical Stress (MPa)",

    title="Critical Stress vs Slenderness Ratio",

    label="Euler Curve",

    grid=true
)


scatter!(
    p3,

    [λ],

    [σcr / 1e6],

    markersize=7,

    label="Current Column"
)


savefig(
    p3,
    "critical_stress_vs_slenderness.png"
)


# ================================================================
# FINAL MESSAGE
# ================================================================

println()
println("================================================")
println("                  PLOTS SAVED")
println("================================================")

println(
    "1. buckling_shape.png"
)

println(
    "2. critical_load_vs_length.png"
)

println(
    "3. critical_stress_vs_slenderness.png"
)

println()
if analysis >= 3
    println("4. inelastic_stress_vs_slenderness.png")
end
if analysis == 4
    println("5. load_vs_midspan_deflection.png")
    println("6. final_deflected_shape.png")
end
println("Analysis completed; inspect continuation status and instability evidence above.")
end # main

if abspath(PROGRAM_FILE) == @__FILE__
    exit(run_cli(main))
end
