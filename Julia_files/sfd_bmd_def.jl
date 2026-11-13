using LinearAlgebra
using Plots
using Printf
include(joinpath(@__DIR__, "cli_support.jl"))
using .AnalysisCLI

include(joinpath(@__DIR__, "beam_stiffness.jl"))

# ================================================================
# BEAM ANALYSIS PROGRAM
#
# Calculates:
#   1. Support reactions
#   2. Shear Force Diagram (SFD)
#   3. Bending Moment Diagram (BMD)
#   4. Slope
#   5. Deflection
#
# Supports:
#   pin / roller / fixed / vertical spring; prescribed settlements
#
# Analysis:
#   Direct stiffness method for determinate and indeterminate bending.
#   Piecewise constant E and I; axial deformation is not modeled.
#
# Geometry:
#   Horizontal beam; node distances are measured from the left end.
#   Nodes without supports or loads remain part of the continuous beam.
#
# Loads:
#   point load / UDL / UVL / applied moment
#
# Units used for input:
#   Length                 -> m
#   Point load             -> kN
#   Distributed load       -> kN/m
#   Applied moment         -> kN-m
#   Young's modulus        -> GPa
#   Second moment of area  -> m^4
#
# Sign convention:
#   + vertical force = upward
#   + applied/reaction external moment = anticlockwise
#   BMD = sagging positive
#
# Output:
#   SFD.jpg
#   BMD.jpg
#   Slope.jpg
#   Deflection.jpg
#   Beam_Analysis_Combined.jpg
#   Beam_Analysis_Equations.jpg
#   Beam_Analysis_Equations.txt
# ================================================================


# ================================================================
# LEGACY MACAULAY HELPERS (retained for comparison; main uses stiffness)
# ================================================================

function macaulay(x, a, n)
    return x < a ? 0.0 : (x - a)^n
end


function count_reactions(supports)
    n = 0

    for support in supports
        support.HorizontalReaction !== nothing && (n += 1)
        support.VerticalReaction !== nothing && (n += 1)
        support.MomentReaction !== nothing && (n += 1)
    end

    return n
end


function check_determinacy(supports)
    n = count_reactions(supports)

    println("\nTotal number of reaction unknowns = $n")

    if n == 3
        println("The beam is statically determinate by reaction count.")
        return true

    elseif n > 3
        println("\n==========================================")
        println("WARNING")
        println("==========================================")
        println("The beam is statically indeterminate for this program.")
        println("Please change the support conditions.")
        return false

    else
        println("\nThe structure may be unstable.")
        println("Please check the support conditions.")
        return false
    end
end


# ================================================================
# LOAD RESULTANTS
# ================================================================

function uvl_equivalent_load(w1, w2, x1, x2)
    L = x2 - x1
    W = (w1 + w2) * L / 2

    if abs(W) < 1e-12
        return 0.0, x1
    end

    xbar_local =
        L * (w1 + 2w2) /
        (3 * (w1 + w2))

    return W, x1 + xbar_local
end


function calculate_external_loading(loads)
    total_vertical_load = 0.0
    total_external_moment = 0.0

    for load in loads

        if load.Type == "Point Load"
            P = load.Magnitude
            x = load.Location

            total_vertical_load -= P
            total_external_moment -= P * x

        elseif load.Type == "UDL"
            w = load.Intensity
            x1 = load.Start
            x2 = load.End

            W = w * (x2 - x1)
            xbar = (x1 + x2) / 2

            total_vertical_load -= W
            total_external_moment -= W * xbar

        elseif load.Type == "UVL"
            W, xbar = uvl_equivalent_load(
                load.StartIntensity,
                load.EndIntensity,
                load.Start,
                load.End
            )

            total_vertical_load -= W
            total_external_moment -= W * xbar

        elseif load.Type == "Moment"
            total_external_moment += load.Magnitude
        end
    end

    return total_vertical_load, total_external_moment
end


# ================================================================
# SUPPORT REACTIONS
# ================================================================

function solve_reactions(supports, node_data, loads)

    total_vertical_load,
    total_external_moment =
        calculate_external_loading(loads)

    println("\n==========================================")
    println("EQUIVALENT EXTERNAL LOADING")
    println("==========================================")

    @printf(
        "Total vertical external force = %.4f kN\n",
        total_vertical_load
    )

    @printf(
        "Total external moment about beam start = %.4f kN-m\n",
        total_external_moment
    )

    reaction_unknowns = []

    for (support_index, support) in enumerate(supports)

        node_id = support.Node
        support_x = node_data[node_id].x

        if support.HorizontalReaction !== nothing
            push!(
                reaction_unknowns,
                (
                    SupportIndex = support_index,
                    Node = node_id,
                    Type = :H,
                    Location = support_x
                )
            )
        end

        if support.VerticalReaction !== nothing
            push!(
                reaction_unknowns,
                (
                    SupportIndex = support_index,
                    Node = node_id,
                    Type = :V,
                    Location = support_x
                )
            )
        end

        if support.MomentReaction !== nothing
            push!(
                reaction_unknowns,
                (
                    SupportIndex = support_index,
                    Node = node_id,
                    Type = :M,
                    Location = support_x
                )
            )
        end
    end

    if length(reaction_unknowns) != 3
        error("Exactly 3 reaction unknowns are required.")
    end

    # Equilibrium system:
    # Row 1 -> ΣFx = 0
    # Row 2 -> ΣFy = 0
    # Row 3 -> ΣM about x=0 = 0

    A = zeros(3, 3)
    B = zeros(3)

    for (j, reaction) in enumerate(reaction_unknowns)

        if reaction.Type == :H
            A[1, j] = 1.0

        elseif reaction.Type == :V
            A[2, j] = 1.0
            A[3, j] = reaction.Location

        elseif reaction.Type == :M
            A[3, j] = 1.0
        end
    end

    B[1] = 0.0
    B[2] = -total_vertical_load
    B[3] = -total_external_moment

    if abs(det(A)) < 1e-10
        error(
            "Support arrangement is unstable or equilibrium equations are dependent."
        )
    end

    reaction_values = A \ B

    println("\n==========================================")
    println("CALCULATED SUPPORT REACTIONS")
    println("==========================================")

    for (i, reaction) in enumerate(reaction_unknowns)
        value = reaction_values[i]

        if reaction.Type == :H
            @printf("H%d = %.4f kN\n", reaction.Node, value)

        elseif reaction.Type == :V
            @printf("V%d = %.4f kN\n", reaction.Node, value)

        elseif reaction.Type == :M
            @printf("M%d = %.4f kN-m\n", reaction.Node, value)
        end
    end

    new_supports = []

    for (support_index, support) in enumerate(supports)

        H_value = nothing
        V_value = nothing
        M_value = nothing

        for (j, reaction) in enumerate(reaction_unknowns)

            if reaction.SupportIndex == support_index

                if reaction.Type == :H
                    H_value = reaction_values[j]

                elseif reaction.Type == :V
                    V_value = reaction_values[j]

                elseif reaction.Type == :M
                    M_value = reaction_values[j]
                end
            end
        end

        push!(
            new_supports,
            (
                Node = support.Node,
                Type = support.Type,
                HorizontalReaction = H_value,
                VerticalReaction = V_value,
                MomentReaction = M_value
            )
        )
    end

    return new_supports
end


# ================================================================
# SHEAR FORCE
# ================================================================

function shear_force(x, supports, loads, node_data)

    V = 0.0

    # Support reactions
    for support in supports

        if support.VerticalReaction !== nothing
            a = node_data[support.Node].x

            V +=
                support.VerticalReaction *
                macaulay(x, a, 0)
        end
    end

    # Applied loads
    for load in loads

        if load.Type == "Point Load"

            V -=
                load.Magnitude *
                macaulay(x, load.Location, 0)

        elseif load.Type == "UDL"

            w = load.Intensity
            a = load.Start
            b = load.End

            V -= w * macaulay(x, a, 1)
            V += w * macaulay(x, b, 1)

        elseif load.Type == "UVL"

            w1 = load.StartIntensity
            w2 = load.EndIntensity
            a = load.Start
            b = load.End
            L = b - a
            k = (w2 - w1) / L

            V -= w1 * macaulay(x, a, 1)
            V -= (k / 2) * macaulay(x, a, 2)

            V += w2 * macaulay(x, b, 1)
            V += (k / 2) * macaulay(x, b, 2)
        end
    end

    return V
end


# ================================================================
# BENDING MOMENT
# ================================================================

function bending_moment(x, supports, loads, node_data)

    M = 0.0

    # Support reactions
    for support in supports

        a = node_data[support.Node].x

        if support.VerticalReaction !== nothing
            M +=
                support.VerticalReaction *
                macaulay(x, a, 1)
        end

        if support.MomentReaction !== nothing
            M -=
                support.MomentReaction *
                macaulay(x, a, 0)
        end
    end

    # Applied loads
    for load in loads

        if load.Type == "Point Load"

            M -=
                load.Magnitude *
                macaulay(x, load.Location, 1)

        elseif load.Type == "UDL"

            w = load.Intensity
            a = load.Start
            b = load.End

            M -=
                (w / 2) *
                macaulay(x, a, 2)

            M +=
                (w / 2) *
                macaulay(x, b, 2)

        elseif load.Type == "UVL"

            w1 = load.StartIntensity
            w2 = load.EndIntensity
            a = load.Start
            b = load.End

            L = b - a
            k = (w2 - w1) / L

            M -=
                (w1 / 2) *
                macaulay(x, a, 2)

            M -=
                (k / 6) *
                macaulay(x, a, 3)

            M +=
                (w2 / 2) *
                macaulay(x, b, 2)

            M +=
                (k / 6) *
                macaulay(x, b, 3)

        elseif load.Type == "Moment"

            M -=
                load.Magnitude *
                macaulay(x, load.Location, 0)
        end
    end

    return M
end


# ================================================================
# MACAULAY EQUATION TERMS
# ================================================================

function moment_terms(supports, loads, node_data)

    # Each item is:
    # (coefficient in kN-m related Macaulay expression,
    #  location a,
    #  exponent n)

    terms = Tuple{Float64, Float64, Int}[]

    for support in supports

        a = node_data[support.Node].x

        if support.VerticalReaction !== nothing
            push!(
                terms,
                (
                    Float64(support.VerticalReaction),
                    Float64(a),
                    1
                )
            )
        end

        if support.MomentReaction !== nothing
            push!(
                terms,
                (
                    -Float64(support.MomentReaction),
                    Float64(a),
                    0
                )
            )
        end
    end

    for load in loads

        if load.Type == "Point Load"

            push!(
                terms,
                (
                    -Float64(load.Magnitude),
                    Float64(load.Location),
                    1
                )
            )

        elseif load.Type == "UDL"

            w = Float64(load.Intensity)
            a = Float64(load.Start)
            b = Float64(load.End)

            push!(terms, (-w / 2, a, 2))
            push!(terms, ( w / 2, b, 2))

        elseif load.Type == "UVL"

            w1 = Float64(load.StartIntensity)
            w2 = Float64(load.EndIntensity)
            a = Float64(load.Start)
            b = Float64(load.End)

            k = (w2 - w1) / (b - a)

            push!(terms, (-w1 / 2, a, 2))
            push!(terms, (-k / 6,  a, 3))
            push!(terms, ( w2 / 2, b, 2))
            push!(terms, ( k / 6,  b, 3))

        elseif load.Type == "Moment"

            push!(
                terms,
                (
                    -Float64(load.Magnitude),
                    Float64(load.Location),
                    0
                )
            )
        end
    end

    return terms
end


function shear_equation_string(supports, loads, node_data)

    terms = String[]

    for support in supports

        if support.VerticalReaction !== nothing
            R = support.VerticalReaction
            a = node_data[support.Node].x

            push!(
                terms,
                @sprintf("%+.6g<x-%.6g>^0", R, a)
            )
        end
    end

    for load in loads

        if load.Type == "Point Load"

            push!(
                terms,
                @sprintf(
                    "%+.6g<x-%.6g>^0",
                    -load.Magnitude,
                    load.Location
                )
            )

        elseif load.Type == "UDL"

            w = load.Intensity
            a = load.Start
            b = load.End

            push!(terms, @sprintf("%+.6g<x-%.6g>^1", -w, a))
            push!(terms, @sprintf("%+.6g<x-%.6g>^1",  w, b))

        elseif load.Type == "UVL"

            w1 = load.StartIntensity
            w2 = load.EndIntensity
            a = load.Start
            b = load.End
            k = (w2 - w1) / (b - a)

            push!(terms, @sprintf("%+.6g<x-%.6g>^1", -w1, a))
            push!(terms, @sprintf("%+.6g<x-%.6g>^2", -k/2, a))
            push!(terms, @sprintf("%+.6g<x-%.6g>^1",  w2, b))
            push!(terms, @sprintf("%+.6g<x-%.6g>^2",  k/2, b))
        end
    end

    return "V(x) = " * join(terms, " ")
end


function moment_equation_string(supports, loads, node_data)

    terms = moment_terms(supports, loads, node_data)

    txt = String[]

    for (c, a, n) in terms
        push!(
            txt,
            @sprintf("%+.6g<x-%.6g>^%d", c, a, n)
        )
    end

    return "M(x) = " * join(txt, " ")
end


# ================================================================
# SLOPE / DEFLECTION
# ================================================================
#
# Euler-Bernoulli relation:
#
#       E I y''(x) = M(x)
#
# Here the Macaulay moment equation is integrated analytically.
# M is entered in kN-m, therefore 1000 converts it to N-m.
# ================================================================

function integrated_moment_once(x, terms)

    value = 0.0

    for (c, a, n) in terms
        value +=
            c /
            (n + 1) *
            macaulay(x, a, n + 1)
    end

    return value
end


function integrated_moment_twice(x, terms)

    value = 0.0

    for (c, a, n) in terms
        value +=
            c /
            ((n + 1) * (n + 2)) *
            macaulay(x, a, n + 2)
    end

    return value
end


function solve_integration_constants(
    supports,
    node_data,
    terms,
    E,
    I
)

    # Base terms without C1 and C2.
    #
    # theta_base = 1000/(EI) * integral(M dx)
    # y_base     = 1000/(EI) * integral(integral(M dx) dx)

    function theta_base(x)
        return 1000.0 *
               integrated_moment_once(x, terms) /
               (E * I)
    end

    function y_base(x)
        return 1000.0 *
               integrated_moment_twice(x, terms) /
               (E * I)
    end

    # Unknowns:
    # theta(x) = theta_base(x) + C1
    # y(x)     = y_base(x) + C1*x + C2

    A = zeros(2, 2)
    b = zeros(2)

    equations_added = 0

    # Fixed support supplies:
    # theta = 0
    # y = 0
    for support in supports

        if support.Type == "fixed"

            x = node_data[support.Node].x

            equations_added += 1
            A[equations_added, :] .= [1.0, 0.0]
            b[equations_added] = -theta_base(x)

            equations_added += 1
            A[equations_added, :] .= [x, 1.0]
            b[equations_added] = -y_base(x)

            break
        end
    end

    # If no fixed support was found, use vertical displacement = 0
    # at two pin/roller supports.
    if equations_added == 0

        for support in supports

            if support.Type == "pin" ||
               support.Type == "roller"

                x = node_data[support.Node].x

                equations_added += 1

                A[equations_added, :] .= [x, 1.0]
                b[equations_added] = -y_base(x)

                if equations_added == 2
                    break
                end
            end
        end
    end

    if equations_added < 2
        error(
            "Unable to determine the two integration constants from the support boundary conditions."
        )
    end

    if abs(det(A)) < 1e-14
        error(
            "Boundary-condition equations for slope/deflection are dependent."
        )
    end

    C = A \ b

    return C[1], C[2]
end


function slope_value(x, terms, E, I, C1)

    return 1000.0 *
           integrated_moment_once(x, terms) /
           (E * I) +
           C1
end


function deflection_value(x, terms, E, I, C1, C2)

    return 1000.0 *
           integrated_moment_twice(x, terms) /
           (E * I) +
           C1 * x +
           C2
end


function slope_equation_string(terms, E, I, C1)

    txt = String[]

    for (c, a, n) in terms

        coeff =
            1000.0 * c /
            ((n + 1) * E * I)

        push!(
            txt,
            @sprintf(
                "%+.6e<x-%.6g>^%d",
                coeff,
                a,
                n + 1
            )
        )
    end

    push!(
        txt,
        @sprintf("%+.6e", C1)
    )

    return "theta(x) = " * join(txt, " ")
end


function deflection_equation_string(terms, E, I, C1, C2)

    txt = String[]

    for (c, a, n) in terms

        coeff =
            1000.0 * c /
            ((n + 1) * (n + 2) * E * I)

        push!(
            txt,
            @sprintf(
                "%+.6e<x-%.6g>^%d",
                coeff,
                a,
                n + 2
            )
        )
    end

    push!(
        txt,
        @sprintf("%+.6e*x", C1)
    )

    push!(
        txt,
        @sprintf("%+.6e", C2)
    )

    return "y(x) = " * join(txt, " ")
end


# ================================================================
# TEXT WRAPPING FOR EQUATION IMAGE
# ================================================================

function wrap_text(s::String, maxchars::Int = 95)

    words = split(s)
    lines = String[]
    current = ""

    for word in words

        trial =
            isempty(current) ?
            word :
            current * " " * word

        if length(trial) <= maxchars
            current = trial
        else
            push!(lines, current)
            current = word
        end
    end

    !isempty(current) && push!(lines, current)

    return join(lines, "\n")
end


function save_equations_image(
    equations,
    output_folder
)

    eqtext =
        join(
            [
                wrap_text(equations.sfd),
                "",
                wrap_text(equations.bmd),
                "",
                wrap_text(equations.slope),
                "",
                wrap_text(equations.deflection)
            ],
            "\n"
        )

    p = plot(
        xlim = (0, 1),
        ylim = (0, 1),
        axis = false,
        ticks = false,
        legend = false,
        size = (1800, 1100),
        title = "Beam Analysis Equations"
    )

    annotate!(
        p,
        0.02,
        0.95,
        text(
            eqtext,
            11,
            :left,
            :top
        )
    )

    save_plot_as_jpg(
        p,
        joinpath(
            output_folder,
            "Beam_Analysis_Equations.jpg"
        )
    )

    return p
end


# ================================================================
# INPUT HELPERS
# ================================================================

function read_positive_float(prompt_text)
    while true
        value = read_float(prompt_text)
        value > 0 && return value
        println("Please enter a positive numeric value.")
    end
end


function read_beam_nodes(beam_length, number_of_nodes; input = stdin, output = stdout)
    isfinite(beam_length) && beam_length > 0 ||
        throw(ArgumentError("Beam length must be finite and positive."))
    number_of_nodes >= 2 ||
        throw(ArgumentError("At least 2 nodes are required."))

    node_data = NamedTuple{(:ID, :x), Tuple{Int, Float64}}[]

    println(output, "\nEnter one horizontal distance for each node, from left to right.")
    println(output, "Measure every distance from the LEFT END of the beam (m).")
    println(output, "These are distances from the same origin, not lengths between nodes.")
    println(output, "Example for a 6 m beam: 0, 3, 6 (one value per prompt).")
    println(output, "A node without a support or load is an ordinary point on the continuous beam.")

    for i in 1:number_of_nodes
        while true
            print(output, "Distance of Node $i from the left end (m): ")
            eof(input) && throw(EOFError())
            x = tryparse(Float64, strip(readline(input)))

            if x === nothing || !isfinite(x)
                println(output, "Please enter one finite numeric distance.")
            elseif x < 0 || x > beam_length
                println(output, "Distance must lie between 0 and $beam_length m.")
            elseif !isempty(node_data) && x <= node_data[end].x
                println(output, "Distance must be greater than the previous node's distance ($(node_data[end].x) m).")
            else
                push!(node_data, (ID = i, x = x))
                break
            end
        end
    end

    return node_data
end


function read_nonnegative_int(prompt_text)
    while true
        print(prompt_text)
        eof(stdin) && throw(EOFError())
        value = tryparse(Int, strip(readline()))
        value !== nothing && value >= 0 && return value
        println("Please enter a non-negative integer.")
    end
end


function read_float(prompt_text)
    while true
        print(prompt_text)
        eof(stdin) && throw(EOFError())
        value = tryparse(Float64, strip(readline()))
        value !== nothing && isfinite(value) && return value
        println("Please enter a finite numeric value.")
    end
end


# Accepts entries such as:
#   10
#   10 downward
#   10, downward
#   10 +
#   10, +
#
# For vertical loads:
#   downward / +  -> positive magnitude returned
#   upward   / -  -> negative magnitude returned
function read_vertical_load(prompt_text)
    while true
        print(prompt_text)
        eof(stdin) && throw(EOFError())
        parts = split(replace(lowercase(strip(readline())), "," => " "))
        if 1 <= length(parts) <= 2
            value = tryparse(Float64, parts[1])
            if value !== nothing && isfinite(value)
                length(parts) == 1 && return value
                parts[2] in ("up", "upward", "-", "negative") && return -abs(value)
                parts[2] in ("down", "downward", "+", "positive") && return abs(value)
            end
        end
        println("Enter a finite load: 10, -10, 10 downward, or 10 upward.")
    end
end


# E and I apply from each change location to the next change or beam end.
function read_beam_sections(beam_length, E, I)
    count = read_nonnegative_int("Number of changes in E or I along the beam (0 for uniform): ")
    sections = NamedTuple[]
    start = 0.0
    for i in 1:count
        x = read_float("Distance from left end of section change $i (m): ")
        while !(start < x < beam_length)
            println("Section changes must increase and lie strictly inside the beam.")
            x = read_float("Enter section change distance again (m): ")
        end
        push!(sections, (Start=start, End=x, E=E, I=I))
        E = read_positive_float("E from this change onward (GPa): ")*1e9
        I = read_positive_float("I from this change onward (m^4): ")
        start = x
    end
    push!(sections, (Start=start, End=beam_length, E=E, I=I))
    return sections
end


function read_beam_supports(number_of_nodes)
    println("\nAssign supports only where present; other nodes stay continuous.")
    println("This model solves vertical bending (v and theta), not axial response.")
    count = read_nonnegative_int("Enter number of supports: ")
    while !(1 <= count <= number_of_nodes)
        println("Enter between 1 and $number_of_nodes supports.")
        count = read_nonnegative_int("Enter number of supports again: ")
    end
    supports = NamedTuple[]
    used = Set{Int}()
    for i in 1:count
        println("\nSupport $i")
        node = read_nonnegative_int("Enter original Node ID where support is provided: ")
        while !(1 <= node <= number_of_nodes) || node in used
            println("Choose a valid node that does not already have a support.")
            node = read_nonnegative_int("Enter Node ID again: ")
        end
        push!(used,node)
        kind = ""
        while !(kind in ("pin", "roller", "fixed", "spring"))
            print("Enter support type (pin / roller / fixed / spring): ")
            eof(stdin) && throw(EOFError())
            kind = lowercase(strip(readline()))
        end
        stiffness = kind == "spring" ? 1000read_positive_float("Vertical spring stiffness (kN/m): ") : 0.0
        prompt = kind == "spring" ? "Spring base displacement" : "Prescribed support displacement"
        settlement = read_float("$prompt (mm, upward positive; enter 0 for none): ")/1000
        push!(supports,(Node=node,Type=kind,Settlement=settlement,Stiffness=stiffness))
    end
    return supports
end


function save_stiffness_equations_image(solution, output_folder)
    summary = BeamStiffness.equation_summary(solution)
    lines = split(rstrip(summary), '\n')
    # Size grows with the element count, so coefficients are never clipped.
    height = max(700, 32length(lines)+120)
    p = plot(xlim=(0,1),ylim=(0,1),axis=false,ticks=false,legend=false,
             size=(2100,height),title="Piecewise Beam Equations - Direct Stiffness")
    for (i,line) in enumerate(lines)
        annotate!(p,0.01,1-(i-0.5)/length(lines),text(line,11,:left))
    end
    save_plot_as_jpg(p,joinpath(output_folder,"Beam_Analysis_Equations.jpg"))
    return p
end


# ================================================================
# SAVE PLOTS AS JPG
# ================================================================
#
# Plots.jl/GR does not save directly to .jpg.
# This helper:
#   1. saves the plot temporarily as PNG
#   2. converts PNG -> JPG
#
# On macOS it uses the built-in `sips` command.
# ================================================================

function save_plot_as_jpg(plot_object, jpg_path)

    png_path =
        replace(
            jpg_path,
            r"\.jpg$" => ".png"
        )

    # Save temporary PNG using Plots.jl
    savefig(
        plot_object,
        png_path
    )

    # Convert PNG -> JPG on macOS
    try
        run(
            `sips -s format jpeg $png_path --out $jpg_path`
        )

        # Remove temporary PNG after successful conversion
        if isfile(png_path)
            rm(png_path)
        end

    catch err

        println(
            "\nWARNING: JPG conversion failed."
        )

        println(
            "The PNG file has been kept instead:"
        )

        println(png_path)

        println(
            "Conversion error: ",
            err
        )
    end
end


# ================================================================
# MAIN PROGRAM
# ================================================================

function main(; show_plots=show_plot_windows())

    println("==================================================")
    println(" SFD, BMD, SLOPE AND DEFLECTION ANALYSIS PROGRAM")
    println("==================================================")

    # ------------------------------------------------------------
    # Beam length
    # ------------------------------------------------------------

    beam_length =
        read_positive_float(
            "Enter total length of beam (m): "
        )

    # ------------------------------------------------------------
    # Number of nodes
    # ------------------------------------------------------------

    number_of_nodes =
        read_nonnegative_int(
            "Enter number of nodes: "
        )

    while number_of_nodes < 2
        println("At least 2 nodes are required.")

        number_of_nodes =
            read_nonnegative_int(
                "Enter number of nodes again: "
            )
    end

    # ------------------------------------------------------------
    # Horizontal node distances
    # ------------------------------------------------------------

    node_data = read_beam_nodes(beam_length, number_of_nodes)

    println("\n------------------------------------------")
    println("NODE INFORMATION")
    println("------------------------------------------")

    for node in node_data
        println(
            "Node ID = ",
            node.ID,
            "   Distance from left end = ",
            node.x,
            " m"
        )
    end

    # ------------------------------------------------------------
    # Material / section properties
    # ------------------------------------------------------------

    println("\n==========================================")
    println("MATERIAL AND SECTION PROPERTIES")
    println("==========================================")

    E_GPa =
        read_positive_float(
            "Enter Young's modulus E (GPa): "
        )

    I =
        read_positive_float(
            "Enter second moment of area I (m^4): "
        )

    E = E_GPa * 1e9

    @printf("E = %.6g Pa\n", E)
    @printf("I = %.6g m^4\n", I)
    @printf("EI = %.6g N-m^2\n", E * I)

    sections = read_beam_sections(beam_length, E, I)
    supports = read_beam_supports(number_of_nodes)

    # ------------------------------------------------------------
    # Loads
    # ------------------------------------------------------------

    println("\n==========================================")
    println("LOAD INFORMATION")
    println("==========================================")

    number_of_loads =
        read_nonnegative_int(
            "Enter number of loads acting on the beam: "
        )

    loads = []

    load_type_map =
        Dict(
            "1" => "point load",
            "2" => "udl",
            "3" => "uvl",
            "4" => "moment"
        )

    for i in 1:number_of_loads

        println("\n------------------------------------------")
        println("LOAD $i")
        println("------------------------------------------")
        println("1. Point Load")
        println("2. UDL")
        println("3. UVL")
        println("4. Moment")

        print(
            "\nEnter load type (1/2/3/4 or name): "
        )

        load_type =
            lowercase(
                strip(
                    required_line()
                )
            )

        if haskey(load_type_map, load_type)
            load_type =
                load_type_map[load_type]
        end

        while !(
            load_type in
            [
                "point load",
                "udl",
                "uvl",
                "moment"
            ]
        )

            println("Invalid load type!")

            print(
                "Enter 1/2/3/4 or point load/udl/uvl/moment: "
            )

            load_type =
                lowercase(
                    strip(
                        required_line()
                    )
                )

            if haskey(load_type_map, load_type)
                load_type =
                    load_type_map[load_type]
            end
        end

        if load_type == "point load"

            P_signed =
                read_vertical_load(
                    "Enter point load (kN) [examples: 10, 10 downward, 10 +, 10 upward]: "
                )

            # Existing beam equations use positive magnitude for a downward load.
            # Therefore an upward load is represented by a negative magnitude.
            P = P_signed

            x =
                read_float(
                    "Enter load location x (m): "
                )

            while x < 0 || x > beam_length
                println(
                    "Load location must lie within the beam."
                )
                x =
                    read_float(
                        "Enter load location again (m): "
                    )
            end

            push!(
                loads,
                (
                    Type = "Point Load",
                    Magnitude = P,
                    Location = x
                )
            )

        elseif load_type == "udl"

            w =
                read_float(
                    "Enter UDL intensity (kN/m, downward positive; negative for upward): "
                )

            x1 =
                read_float(
                    "Enter UDL start location (m): "
                )

            x2 =
                read_float(
                    "Enter UDL end location (m): "
                )

            while (
                x1 < 0 ||
                x2 > beam_length ||
                x2 <= x1
            )

                println(
                    "Require 0 <= start < end <= beam length."
                )

                x1 =
                    read_float(
                        "Enter UDL start location again (m): "
                    )

                x2 =
                    read_float(
                        "Enter UDL end location again (m): "
                    )
            end

            push!(
                loads,
                (
                    Type = "UDL",
                    Intensity = w,
                    Start = x1,
                    End = x2
                )
            )

        elseif load_type == "uvl"

            w1 =
                read_float(
                    "Enter UVL start intensity (kN/m, downward positive): "
                )

            w2 =
                read_float(
                    "Enter UVL end intensity (kN/m, downward positive): "
                )

            x1 =
                read_float(
                    "Enter UVL start location (m): "
                )

            x2 =
                read_float(
                    "Enter UVL end location (m): "
                )

            while (
                x1 < 0 ||
                x2 > beam_length ||
                x2 <= x1
            )

                println(
                    "Require 0 <= start < end <= beam length."
                )

                x1 =
                    read_float(
                        "Enter UVL start location again (m): "
                    )

                x2 =
                    read_float(
                        "Enter UVL end location again (m): "
                    )
            end

            push!(
                loads,
                (
                    Type = "UVL",
                    StartIntensity = w1,
                    EndIntensity = w2,
                    Start = x1,
                    End = x2
                )
            )

        elseif load_type == "moment"

            println(
                "Positive applied moment = anticlockwise."
            )

            M =
                read_float(
                    "Enter applied moment (kN-m): "
                )

            x =
                read_float(
                    "Enter moment location x (m): "
                )

            while x < 0 || x > beam_length
                println(
                    "Moment location must lie within the beam."
                )
                x =
                    read_float(
                        "Enter moment location again (m): "
                    )
            end

            push!(
                loads,
                (
                    Type = "Moment",
                    Magnitude = M,
                    Location = x
                )
            )
        end
    end

    # Nodes at all load/section boundaries are inserted automatically.
    # Ordinary nodes share v and theta, so they do not create hinges.
    solution = BeamStiffness.solve_beam(beam_length,node_data,supports,loads; E=E,I=I,sections=sections)
    BeamStiffness.beam_checks(solution).passed || error("Beam verification failed; results were not saved.")
    samples = BeamStiffness.sample_beam(solution)
    report = BeamStiffness.beam_report(solution,samples)
    println(report)
    x_values = samples.x
    V_values = samples.V
    M_values = samples.M
    slope_values = samples.theta
    deflection_mm = samples.v_mm

    # ------------------------------------------------------------
    # Output folder
    # ------------------------------------------------------------

    output_folder =
        joinpath(
            pwd(),
            "Beam_Analysis_Results"
        )

    mkpath(output_folder)

    # ------------------------------------------------------------
    # SFD
    # ------------------------------------------------------------

    SFD =
        plot(
            x_values,
            V_values,
            xlabel = "Distance along beam (m)",
            ylabel = "Shear Force (kN)",
            title = "Shear Force Diagram (SFD)",
            linewidth = 2,
            legend = false,
            size = (1200, 700)
        )

    hline!(SFD, [0.0], linewidth = 1)

    save_plot_as_jpg(
        SFD,
        joinpath(
            output_folder,
            "SFD.jpg"
        )
    )

    # ------------------------------------------------------------
    # BMD
    # ------------------------------------------------------------

    BMD =
        plot(
            x_values,
            M_values,
            xlabel = "Distance along beam (m)",
            ylabel = "Bending Moment (kN-m)",
            title = "Bending Moment Diagram (BMD)",
            linewidth = 2,
            legend = false,
            size = (1200, 700)
        )

    hline!(BMD, [0.0], linewidth = 1)

    save_plot_as_jpg(
        BMD,
        joinpath(
            output_folder,
            "BMD.jpg"
        )
    )

    # ------------------------------------------------------------
    # Slope
    # ------------------------------------------------------------

    SLOPE =
        plot(
            x_values,
            slope_values,
            xlabel = "Distance along beam (m)",
            ylabel = "Slope (rad)",
            title = "Slope Diagram",
            linewidth = 2,
            legend = false,
            size = (1200, 700)
        )

    hline!(SLOPE, [0.0], linewidth = 1)

    save_plot_as_jpg(
        SLOPE,
        joinpath(
            output_folder,
            "Slope.jpg"
        )
    )

    # ------------------------------------------------------------
    # Deflection
    # ------------------------------------------------------------

    DEFLECTION =
        plot(
            x_values,
            deflection_mm,
            xlabel = "Distance along beam (m)",
            ylabel = "Deflection (mm)",
            title = "Deflection Diagram",
            linewidth = 2,
            legend = false,
            size = (1200, 700)
        )

    hline!(DEFLECTION, [0.0], linewidth = 1)

    save_plot_as_jpg(
        DEFLECTION,
        joinpath(
            output_folder,
            "Deflection.jpg"
        )
    )

    # ------------------------------------------------------------
    # Combined four-diagram image
    # ------------------------------------------------------------

    combined =
        plot(
            SFD,
            BMD,
            SLOPE,
            DEFLECTION,
            layout = (4, 1),
            size = (1500, 2200)
        )

    save_plot_as_jpg(
        combined,
        joinpath(
            output_folder,
            "Beam_Analysis_Combined.jpg"
        )
    )

    # ------------------------------------------------------------
    # Equations file + equation JPG
    # ------------------------------------------------------------

    equation_file = joinpath(output_folder,"Beam_Analysis_Equations.txt")
    write(equation_file,report)
    equation_plot = save_stiffness_equations_image(solution,output_folder)

    # ------------------------------------------------------------
    # Numerical summary
    # ------------------------------------------------------------

    max_abs_V =
        maximum(
            abs.(
                V_values
            )
        )

    max_abs_M =
        maximum(
            abs.(
                M_values
            )
        )

    max_abs_slope =
        maximum(
            abs.(
                slope_values
            )
        )

    max_abs_deflection =
        maximum(
            abs.(
                deflection_mm
            )
        )

    println("\n==========================================")
    println("MAXIMUM ABSOLUTE VALUES")
    println("==========================================")

    @printf(
        "Maximum |V|          = %.6f kN\n",
        max_abs_V
    )

    @printf(
        "Maximum |M|          = %.6f kN-m\n",
        max_abs_M
    )

    @printf(
        "Maximum |slope|      = %.8e rad\n",
        max_abs_slope
    )

    @printf(
        "Maximum |deflection| = %.8f mm\n",
        max_abs_deflection
    )

    # ------------------------------------------------------------
    # Display all plots
    # ------------------------------------------------------------

    if show_plots
        display(SFD)
        display(BMD)
        display(SLOPE)
        display(DEFLECTION)
        display(combined)
        display(equation_plot)
    end

    println("\n==========================================")
    println("FILES SAVED")
    println("==========================================")

    println(
        "Results folder: ",
        abspath(output_folder)
    )

    println("1. SFD.jpg")
    println("2. BMD.jpg")
    println("3. Slope.jpg")
    println("4. Deflection.jpg")
    println("5. Beam_Analysis_Combined.jpg")
    println("6. Beam_Analysis_Equations.jpg")
    println("7. Beam_Analysis_Equations.txt")

    println("\n==========================================")
    println("ANALYSIS COMPLETED")
    println("==========================================")
end


# ================================================================
# RUN PROGRAM
# ================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    exit(run_cli(main))
end
