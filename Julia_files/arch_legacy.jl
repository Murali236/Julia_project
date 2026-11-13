module ArchLegacy
# Original three-hinged geometry, reactions, and moving-point-load functions.
# Kept without top-level prompts for regression and compatibility.
# ================================================================
#                      JULIA ARCH SOLVER
#
# CURRENTLY SUPPORTED:
#
#       THREE-PINNED / THREE-HINGED ARCH
#
# NOT YET SUPPORTED:
#
#       TWO-PINNED ARCH
#       FIXED ARCH
#
# ================================================================


# ================================================================
# DATA STRUCTURES
# ================================================================

struct Node
    id::Int
    x::Float64
    y::Float64
    node_type::String
end


struct SupportInfo
    node::Int
    node_type::String

    horizontal::String
    vertical::String
    moment::String
end


# ================================================================
# PARABOLIC ARCH
#
#           4f
#   y = -------- x(L-x)
#           L²
#
# ================================================================

function generate_parabolic_arch(L, f, n_elements)

    nodes = Node[]

    # For a three-hinged arch the crown must be a node
    crown_node = div(n_elements, 2) + 1


    for i in 0:n_elements

        x = L * i / n_elements

        y = (4.0 * f / L^2) * x * (L - x)

        node_id = i + 1


        # --------------------------------------------------------
        # NODE TYPE
        # --------------------------------------------------------

        if node_id == 1

            node_type = "Left Pinned Support"

        elseif node_id == n_elements + 1

            node_type = "Right Pinned Support"

        elseif node_id == crown_node

            node_type = "Crown Hinge"

        else

            node_type = "Normal Node"

        end


        push!(
            nodes,
            Node(
                node_id,
                x,
                y,
                node_type
            )
        )

    end


    return nodes
end


# ================================================================
# CIRCULAR ARCH
#
# Radius:
#
#             L²     f
#       R = ------ + ---
#            8f      2
#
#
# Circle centre:
#
#       xc = L/2
#       yc = f - R
#
# ================================================================

function generate_circular_arch(L, f, n_elements)

    # Calculate radius
    R = L^2 / (8.0 * f) + f / 2.0


    println()

    println(
        "Calculated radius R = ",
        round(R, digits = 4)
    )


    # Circle centre

    xc = L / 2.0

    yc = f - R


    nodes = Node[]


    crown_node = div(n_elements, 2) + 1


    for i in 0:n_elements

        x = L * i / n_elements


        inside =
            R^2 -
            (x - xc)^2


        # Avoid numerical round-off error

        inside =
            max(
                inside,
                0.0
            )


        y =
            yc +
            sqrt(inside)


        node_id =
            i + 1


        # --------------------------------------------------------
        # NODE TYPE
        # --------------------------------------------------------

        if node_id == 1

            node_type = "Left Pinned Support"

        elseif node_id == n_elements + 1

            node_type = "Right Pinned Support"

        elseif node_id == crown_node

            node_type = "Crown Hinge"

        else

            node_type = "Normal Node"

        end


        push!(
            nodes,
            Node(
                node_id,
                x,
                y,
                node_type
            )
        )

    end


    return nodes, R
end


# ================================================================
# CIRCULAR ARCH USING L AND R
#
# If radius is given:
#
#       f = R - sqrt(R² - (L/2)²)
#
# ================================================================

function rise_from_radius(L, R)

    if R < L / 2.0

        error(
            """
            INVALID CIRCULAR ARCH GEOMETRY

            Radius R must satisfy:

            R >= L/2

            Given:
            L = $L
            R = $R

            Minimum R = $(L/2)
            """
        )

    end


    f =
        R -
        sqrt(
            R^2 -
            (L / 2.0)^2
        )


    return f
end


# ================================================================
# SUPPORT INFORMATION
#
# THREE-HINGED ARCH ONLY
#
# ================================================================

function generate_supports(nodes)

    supports = SupportInfo[]


    first_node = 1

    last_node = length(nodes)

    crown_node =
        div(
            length(nodes) + 1,
            2
        )


    # ============================================================
    # LEFT PINNED SUPPORT
    # ============================================================

    push!(
        supports,
        SupportInfo(
            first_node,
            "Pinned Support",
            "H1",
            "V1",
            "0"
        )
    )


    # ============================================================
    # INTERNAL CROWN HINGE
    #
    # Horizontal and vertical force can be transferred.
    #
    # Moment at crown:
    #
    #                   Mc = 0
    #
    # ============================================================

    push!(
        supports,
        SupportInfo(
            crown_node,
            "Internal Crown Hinge",
            "Hc",
            "Vc",
            "0"
        )
    )


    # ============================================================
    # RIGHT PINNED SUPPORT
    # ============================================================

    push!(
        supports,
        SupportInfo(
            last_node,
            "Pinned Support",
            "H$(last_node)",
            "V$(last_node)",
            "0"
        )
    )


    return supports
end


# ================================================================
# PRINT NODE TABLE
# ================================================================

function print_nodes(nodes)

    println()

    println(
        "======================================================================"
    )

    println(
        "                           NODE INFORMATION"
    )

    println(
        "======================================================================"
    )


    println(
        rpad("Node", 10),
        rpad("X", 15),
        rpad("Y", 15),
        "Node Type"
    )


    println("-"^75)


    for node in nodes

        println(
            rpad(
                string(node.id),
                10
            ),

            rpad(
                string(
                    round(
                        node.x,
                        digits = 4
                    )
                ),
                15
            ),

            rpad(
                string(
                    round(
                        node.y,
                        digits = 4
                    )
                ),
                15
            ),

            node.node_type
        )

    end

end


# ================================================================
# PRINT SUPPORT TABLE
# ================================================================

function print_supports(supports)

    println()

    println(
        "=============================================================================="
    )

    println(
        "                           SUPPORT INFORMATION"
    )

    println(
        "=============================================================================="
    )


    println(
        rpad("Node", 8),
        rpad("Type", 27),
        rpad("Horizontal", 14),
        rpad("Vertical", 14),
        "Moment"
    )


    println("-"^80)


    for s in supports

        println(
            rpad(
                string(s.node),
                8
            ),

            rpad(
                s.node_type,
                27
            ),

            rpad(
                s.horizontal,
                14
            ),

            rpad(
                s.vertical,
                14
            ),

            s.moment
        )

    end

end


abstract type ArchLoad end


struct PointLoad <: ArchLoad
    x::Float64
    y::Float64
    magnitude::Float64
    angle_deg::Float64
end


struct UDL <: ArchLoad
    x1::Float64
    y1::Float64

    x2::Float64
    y2::Float64

    intensity::Float64
    angle_deg::Float64
end


struct UVL <: ArchLoad
    x1::Float64
    y1::Float64

    x2::Float64
    y2::Float64

    w1::Float64
    w2::Float64

    angle_deg::Float64
end


struct AppliedMoment <: ArchLoad
    x::Float64
    y::Float64
    M::Float64
end



# ========================================================================
# ARCH Y-COORDINATE
# ========================================================================

function arch_y(x, geometry, L, f)

    if x < 0.0 || x > L

        error(
            "x-coordinate must lie between 0 and L."
        )

    end


    # --------------------------------------------------------------------
    # PARABOLIC ARCH
    # --------------------------------------------------------------------

    if geometry == 1

        return (
            4.0 *
            f /
            L^2 *
            x *
            (L - x)
        )


    # --------------------------------------------------------------------
    # CIRCULAR ARCH
    # --------------------------------------------------------------------

    elseif geometry == 2

        R =
            L^2 /
            (8.0 * f) +
            f / 2.0


        xc =
            L / 2.0


        yc =
            f - R


        inside =
            R^2 -
            (x - xc)^2


        inside =
            max(
                inside,
                0.0
            )


        return (
            yc +
            sqrt(inside)
        )


    else

        error(
            "Invalid arch geometry."
        )

    end

end



# ========================================================================
# CHECK WHETHER POINT IS ON ARCH
# ========================================================================

function point_on_arch(
    x,
    y,
    geometry,
    L,
    f
)

    if x < 0 || x > L

        return false

    end


    actual_y =
        arch_y(
            x,
            geometry,
            L,
            f
        )


    tolerance =
        1e-4 *
        max(
            L,
            f,
            1.0
        )


    return (
        abs(y - actual_y)
        <= tolerance
    )

end



# ========================================================================
# READ POINT ON ARCH
# ========================================================================

function read_arch_point(
    name,
    geometry,
    L,
    f
)

    while true

        println()

        print(
            "Enter x-coordinate of ",
            name,
            ": "
        )


        x =
            parse(
                Float64,
                readline()
            )


        if x < 0 || x > L

            println()

            println(
                "ERROR: x must lie between 0 and ",
                L
            )

            continue

        end


        calculated_y =
            arch_y(
                x,
                geometry,
                L,
                f
            )


        println(
            "Arch ordinate at x = ",
            round(
                x,
                digits = 4
            ),
            " is y = ",
            round(
                calculated_y,
                digits = 4
            )
        )


        print(
            "Enter y-coordinate: "
        )


        y =
            parse(
                Float64,
                readline()
            )


        if point_on_arch(
            x,
            y,
            geometry,
            L,
            f
        )

            println(
                "Point verified: lies on arch."
            )

            return x, y

        else

            println()

            println(
                "ERROR: Point does not lie on the arch."
            )

            println(
                "At x = ",
                x,
                ", expected y = ",
                round(
                    calculated_y,
                    digits = 4
                )
            )

        end

    end

end



# ========================================================================
# LOAD INPUT
# ========================================================================

function input_loads(
    geometry,
    L,
    f
)

    loads =
        ArchLoad[]


    println()

    println(
        "=============================================================="
    )

    println(
        "                         LOAD INPUT"
    )

    println(
        "=============================================================="
    )


    print(
        "\nEnter number of loads: "
    )


    number_of_loads =
        parse(
            Int,
            readline()
        )


    if number_of_loads < 0

        error(
            "Number of loads cannot be negative."
        )

    end



    for i in 1:number_of_loads

        println()

        println(
            "--------------------------------------------------------------"
        )

        println(
            "LOAD ",
            i
        )

        println(
            "--------------------------------------------------------------"
        )


        println()

        println(
            "1 -> Point Load"
        )

        println(
            "2 -> UDL"
        )

        println(
            "3 -> UVL"
        )

        println(
            "4 -> Applied Moment"
        )


        println()

        print(
            "Select load type: "
        )


        load_type =
            parse(
                Int,
                readline()
            )



        # ================================================================
        # POINT LOAD
        # ================================================================

        if load_type == 1

            x,
            y =
                read_arch_point(
                    "point load",
                    geometry,
                    L,
                    f
                )


            print(
                "Enter point load magnitude: "
            )


            P =
                parse(
                    Float64,
                    readline()
                )


            println()

            println(
                "Angle Convention:"
            )

            println(
                "0°   = Right"
            )

            println(
                "90°  = Up"
            )

            println(
                "-90° = Down"
            )

            println(
                "180° = Left"
            )


            print(
                "Enter load angle in degrees: "
            )


            angle =
                parse(
                    Float64,
                    readline()
                )


            push!(
                loads,

                PointLoad(
                    x,
                    y,
                    P,
                    angle
                )
            )



        # ================================================================
        # UDL
        # ================================================================

        elseif load_type == 2

            println()

            println(
                "Enter START point of UDL"
            )


            x1,
            y1 =
                read_arch_point(
                    "UDL start",
                    geometry,
                    L,
                    f
                )


            println()

            println(
                "Enter END point of UDL"
            )


            x2,
            y2 =
                read_arch_point(
                    "UDL end",
                    geometry,
                    L,
                    f
                )


            if x2 <= x1

                error(
                    "UDL end must lie to the right of its start."
                )

            end


            print(
                "Enter UDL intensity: "
            )


            w =
                parse(
                    Float64,
                    readline()
                )


            print(
                "Enter UDL angle in degrees: "
            )


            angle =
                parse(
                    Float64,
                    readline()
                )


            push!(
                loads,

                UDL(
                    x1,
                    y1,
                    x2,
                    y2,
                    w,
                    angle
                )
            )



        # ================================================================
        # UVL
        # ================================================================

        elseif load_type == 3

            println()

            println(
                "Enter START point of UVL"
            )


            x1,
            y1 =
                read_arch_point(
                    "UVL start",
                    geometry,
                    L,
                    f
                )


            println()

            println(
                "Enter END point of UVL"
            )


            x2,
            y2 =
                read_arch_point(
                    "UVL end",
                    geometry,
                    L,
                    f
                )


            if x2 <= x1

                error(
                    "UVL end must lie to the right of its start."
                )

            end


            print(
                "Enter starting intensity w1: "
            )


            w1 =
                parse(
                    Float64,
                    readline()
                )


            print(
                "Enter ending intensity w2: "
            )


            w2 =
                parse(
                    Float64,
                    readline()
                )


            print(
                "Enter UVL angle in degrees: "
            )


            angle =
                parse(
                    Float64,
                    readline()
                )


            push!(
                loads,

                UVL(
                    x1,
                    y1,
                    x2,
                    y2,
                    w1,
                    w2,
                    angle
                )
            )



        # ================================================================
        # APPLIED MOMENT
        # ================================================================

        elseif load_type == 4

            x,
            y =
                read_arch_point(
                    "applied moment",
                    geometry,
                    L,
                    f
                )


            println()

            println(
                "Moment sign convention:"
            )

            println(
                "Anticlockwise = Positive"
            )

            println(
                "Clockwise     = Negative"
            )


            print(
                "Enter applied moment: "
            )


            M =
                parse(
                    Float64,
                    readline()
                )


            push!(
                loads,

                AppliedMoment(
                    x,
                    y,
                    M
                )
            )


        else

            error(
                "Invalid load type."
            )

        end

    end


    return loads

end



# ========================================================================
# POINT LOAD CONTRIBUTION
# ========================================================================

function load_contribution(
    load::PointLoad,
    geometry,
    L,
    f,
    xmin,
    xmax,
    xref,
    yref
)

    tolerance =
        1e-10


    if load.x < xmin - tolerance ||
       load.x > xmax + tolerance

        return (
            0.0,
            0.0,
            0.0
        )

    end


    θ =
        deg2rad(
            load.angle_deg
        )


    Fx =
        load.magnitude *
        cos(θ)


    Fy =
        load.magnitude *
        sin(θ)


    # Moment:
    #
    # M = rx*Fy - ry*Fx

    M =
        (load.x - xref) * Fy -
        (load.y - yref) * Fx


    return Fx, Fy, M

end



# ========================================================================
# APPLIED MOMENT CONTRIBUTION
# ========================================================================

function load_contribution(
    load::AppliedMoment,
    geometry,
    L,
    f,
    xmin,
    xmax,
    xref,
    yref
)

    if load.x < xmin ||
       load.x > xmax

        return (
            0.0,
            0.0,
            0.0
        )

    end


    return (
        0.0,
        0.0,
        load.M
    )

end



# ========================================================================
# UDL CONTRIBUTION
#
# UDL is interpreted per unit HORIZONTAL projected length.
#
# Numerical integration is used because this also correctly accounts
# for horizontal components of inclined distributed loads.
# ========================================================================

function load_contribution(
    load::UDL,
    geometry,
    L,
    f,
    xmin,
    xmax,
    xref,
    yref
)

    a =
        max(
            xmin,
            load.x1
        )


    b =
        min(
            xmax,
            load.x2
        )


    if b <= a

        return (
            0.0,
            0.0,
            0.0
        )

    end


    θ =
        deg2rad(
            load.angle_deg
        )


    n =
        1000


    dx =
        (b - a) /
        n


    Fx_total =
        0.0


    Fy_total =
        0.0


    M_total =
        0.0


    for i in 1:n

        x =
            a +
            (i - 0.5) *
            dx


        y =
            arch_y(
                x,
                geometry,
                L,
                f
            )


        dP =
            load.intensity *
            dx


        dFx =
            dP *
            cos(θ)


        dFy =
            dP *
            sin(θ)


        dM =
            (x - xref) * dFy -
            (y - yref) * dFx


        Fx_total += dFx

        Fy_total += dFy

        M_total += dM

    end


    return (
        Fx_total,
        Fy_total,
        M_total
    )

end



# ========================================================================
# UVL CONTRIBUTION
# ========================================================================

function load_contribution(
    load::UVL,
    geometry,
    L,
    f,
    xmin,
    xmax,
    xref,
    yref
)

    a =
        max(
            xmin,
            load.x1
        )


    b =
        min(
            xmax,
            load.x2
        )


    if b <= a

        return (
            0.0,
            0.0,
            0.0
        )

    end


    θ =
        deg2rad(
            load.angle_deg
        )


    n =
        1000


    dx =
        (b - a) /
        n


    Fx_total =
        0.0


    Fy_total =
        0.0


    M_total =
        0.0


    for i in 1:n

        x =
            a +
            (i - 0.5) *
            dx


        y =
            arch_y(
                x,
                geometry,
                L,
                f
            )


        ratio =
            (x - load.x1) /
            (load.x2 - load.x1)


        w =
            load.w1 +
            ratio *
            (
                load.w2 -
                load.w1
            )


        dP =
            w *
            dx


        dFx =
            dP *
            cos(θ)


        dFy =
            dP *
            sin(θ)


        dM =
            (x - xref) * dFy -
            (y - yref) * dFx


        Fx_total += dFx

        Fy_total += dFy

        M_total += dM

    end


    return (
        Fx_total,
        Fy_total,
        M_total
    )

end



# ========================================================================
# TOTAL LOAD CONTRIBUTION
# ========================================================================

function total_load_contribution(
    loads,
    geometry,
    L,
    f;
    xmin = 0.0,
    xmax = L,
    xref = 0.0,
    yref = 0.0
)

    Fx =
        0.0


    Fy =
        0.0


    M =
        0.0


    for load in loads

        fx,
        fy,
        moment =
            load_contribution(
                load,
                geometry,
                L,
                f,
                xmin,
                xmax,
                xref,
                yref
            )


        Fx += fx

        Fy += fy

        M += moment

    end


    return (
        Fx,
        Fy,
        M
    )

end



# ========================================================================
# THREE-HINGED ARCH REACTION SOLVER
# ========================================================================

function solve_reactions(
    loads,
    geometry,
    L,
    f
)

    # --------------------------------------------------------------------
    # SUPPORT A
    # --------------------------------------------------------------------

    xA =
        0.0

    yA =
        0.0


    # --------------------------------------------------------------------
    # SUPPORT B
    # --------------------------------------------------------------------

    xB =
        L

    yB =
        0.0


    # --------------------------------------------------------------------
    # CROWN C
    # --------------------------------------------------------------------

    xC =
        L / 2.0


    yC =
        arch_y(
            xC,
            geometry,
            L,
            f
        )


    # ====================================================================
    # TOTAL LOADS
    # ====================================================================

    sumFx,
    sumFy,
    sumMA =
        total_load_contribution(
            loads,
            geometry,
            L,
            f,

            xmin = 0.0,

            xmax = L,

            xref = xA,

            yref = yA
        )


    # ====================================================================
    # EQUATION 1
    #
    # ΣMA = 0
    #
    # VB L + M(loads about A) = 0
    #
    # ====================================================================

    VB =
        -sumMA /
        L


    # ====================================================================
    # EQUATION 2
    #
    # ΣFy = 0
    #
    # VA + VB + ΣFy(loads) = 0
    #
    # ====================================================================

    VA =
        -sumFy -
        VB


    # ====================================================================
    # LOAD MOMENT ABOUT C
    #
    # LEFT HALF ONLY
    # ====================================================================

    leftFx,
    leftFy,
    leftMC =
        total_load_contribution(
            loads,
            geometry,
            L,
            f,

            xmin = 0.0,

            xmax = xC,

            xref = xC,

            yref = yC
        )


    # ====================================================================
    # EQUATION 3
    #
    # ΣMC(left) = 0
    #
    #
    # HC*yC - VA*xC + M(load,left about C) = 0
    #
    # Here HA is the horizontal reaction at A.
    #
    #
    # HA*yC - VA*xC + Mleft = 0
    #
    #
    # Therefore:
    #
    #                 VA*xC - Mleft
    #       HA = -------------------------
    #                       yC
    #
    # ====================================================================

    HA =
        (
            VA * xC -
            leftMC
        ) /
        yC


    # ====================================================================
    # EQUATION 4
    #
    # ΣFx = 0
    #
    # HA + HB + ΣFx(loads) = 0
    #
    # ====================================================================

    HB =
        -sumFx -
        HA


    return (
        HA = HA,
        VA = VA,
        HB = HB,
        VB = VB,

        totalFx = sumFx,
        totalFy = sumFy,
        totalMA = sumMA,

        leftMC = leftMC,

        xC = xC,
        yC = yC
    )

end



# ========================================================================
# PRINT EQUILIBRIUM EQUATIONS
# ========================================================================

function print_equilibrium_equations(
    reaction
)

    println()

    println(
        "======================================================================"
    )

    println(
        "                       EQUILIBRIUM EQUATIONS"
    )

    println(
        "======================================================================"
    )


    println()

    println(
        "Equation 1: ΣFx = 0"
    )

    println()

    println(
        "HA + HB + (",
        round(
            reaction.totalFx,
            digits = 6
        ),
        ") = 0"
    )


    println()

    println(
        "Equation 2: ΣFy = 0"
    )

    println()

    println(
        "VA + VB + (",
        round(
            reaction.totalFy,
            digits = 6
        ),
        ") = 0"
    )


    println()

    println(
        "Equation 3: ΣMA = 0"
    )

    println()

    println(
        "VB * L + (",
        round(
            reaction.totalMA,
            digits = 6
        ),
        ") = 0"
    )


    println()

    println(
        "Equation 4: ΣMC(left) = 0"
    )

    println()

    println(
        "HA * ",
        round(
            reaction.yC,
            digits = 6
        ),
        " - VA * ",
        round(
            reaction.xC,
            digits = 6
        ),
        " + (",
        round(
            reaction.leftMC,
            digits = 6
        ),
        ") = 0"
    )

end



# ========================================================================
# PRINT CALCULATED REACTIONS
# ========================================================================

function print_reactions(
    reaction
)

    println()

    println(
        "======================================================================"
    )

    println(
        "                         SUPPORT REACTIONS"
    )

    println(
        "======================================================================"
    )


    println()

    println(
        "LEFT SUPPORT A"
    )


    println(
        "Horizontal Reaction HA = ",
        round(
            reaction.HA,
            digits = 6
        )
    )


    println(
        "Vertical Reaction VA   = ",
        round(
            reaction.VA,
            digits = 6
        )
    )


    println(
        "Moment MA              = 0"
    )


    println()

    println(
        "RIGHT SUPPORT B"
    )


    println(
        "Horizontal Reaction HB = ",
        round(
            reaction.HB,
            digits = 6
        )
    )


    println(
        "Vertical Reaction VB   = ",
        round(
            reaction.VB,
            digits = 6
        )
    )


    println(
        "Moment MB              = 0"
    )

end



# ========================================================================
# EQUILIBRIUM CHECK
# ========================================================================

function check_equilibrium(
    reaction,
    L
)

    Fx_check =
        reaction.HA +
        reaction.HB +
        reaction.totalFx


    Fy_check =
        reaction.VA +
        reaction.VB +
        reaction.totalFy


    MA_check =
        reaction.VB *
        L +
        reaction.totalMA


    MC_check =
        reaction.HA *
        reaction.yC -
        reaction.VA *
        reaction.xC +
        reaction.leftMC


    println()

    println(
        "======================================================================"
    )

    println(
        "                         EQUILIBRIUM CHECK"
    )

    println(
        "======================================================================"
    )


    println(
        "ΣFx = ",
        Fx_check
    )


    println(
        "ΣFy = ",
        Fy_check
    )


    println(
        "ΣMA = ",
        MA_check
    )


    println(
        "ΣMC = ",
        MC_check
    )


    tolerance =
        1e-6


    if abs(Fx_check) < tolerance &&
       abs(Fy_check) < tolerance &&
       abs(MA_check) < tolerance &&
       abs(MC_check) < tolerance

        println()

        println(
            "Equilibrium satisfied successfully."
        )

    else

        println()

        println(
            "WARNING: Equilibrium residual detected."
        )

    end

end



# ========================================================================
# POINT LOAD REACTION FUNCTIONS
#
# This section provides reactions as functions of the load position x.
#
# Example:
#
#             VA = f(x)
#             VB = f(x)
#             HA = f(x)
#             HB = f(x)
#
# This is meaningful when one point load moves along the arch.
#
# ========================================================================

function point_load_reaction_functions(
    P,
    angle_deg,
    geometry,
    L,
    f
)

    θ =
        deg2rad(
            angle_deg
        )


    Fx =
        P *
        cos(θ)


    Fy =
        P *
        sin(θ)


    xC =
        L / 2.0


    yC =
        f


    # --------------------------------------------------------------------
    # VERTICAL REACTION AT B
    # --------------------------------------------------------------------

    function VB_function(x)

        y =
            arch_y(
                x,
                geometry,
                L,
                f
            )


        load_moment_A =
            x * Fy -
            y * Fx


        return (
            -load_moment_A /
            L
        )

    end


    # --------------------------------------------------------------------
    # VERTICAL REACTION AT A
    # --------------------------------------------------------------------

    function VA_function(x)

        VB =
            VB_function(x)


        return (
            -Fy -
            VB
        )

    end


    # --------------------------------------------------------------------
    # HORIZONTAL REACTION AT A
    # --------------------------------------------------------------------

    function HA_function(x)

        y =
            arch_y(
                x,
                geometry,
                L,
                f
            )


        VA =
            VA_function(x)


        # --------------------------------------------------------------
        # Load lies on LEFT side of crown
        # --------------------------------------------------------------

        if x <= xC

            MloadC =
                (x - xC) * Fy -
                (y - yC) * Fx


            return (
                (
                    VA * xC -
                    MloadC
                ) /
                yC
            )


        # --------------------------------------------------------------
        # Load lies on RIGHT side of crown
        # --------------------------------------------------------------

        else

            return (
                VA *
                xC /
                yC
            )

        end

    end


    # --------------------------------------------------------------------
    # HORIZONTAL REACTION AT B
    # --------------------------------------------------------------------

    function HB_function(x)

        HA =
            HA_function(x)


        return (
            -Fx -
            HA
        )

    end


    return (
        HA = HA_function,
        VA = VA_function,
        HB = HB_function,
        VB = VB_function
    )

end



# ========================================================================
# PRINT POINT LOAD REACTION FUNCTION INFORMATION
# ========================================================================

function print_point_reaction_functions(
    load::PointLoad,
    geometry,
    L,
    f
)

    println()

    println(
        "======================================================================"
    )

    println(
        "                  REACTION FORCE FUNCTIONS"
    )

    println(
        "======================================================================"
    )


    println()

    println(
        "Treating the point-load position x as a variable:"
    )


    println()

    println(
        "HA = HA(x)"
    )


    println(
        "VA = VA(x)"
    )


    println(
        "HB = HB(x)"
    )


    println(
        "VB = VB(x)"
    )


    println()

    println(
        "where the arch ordinate is:"
    )


    if geometry == 1

        println()

        println(
            "y(x) = (4f/L²)x(L-x)"
        )

    else

        println()

        println(
            "y(x) = f - R + sqrt(R² - (x-L/2)²)"
        )

    end


    θ =
        deg2rad(
            load.angle_deg
        )


    Fx =
        load.magnitude *
        cos(θ)


    Fy =
        load.magnitude *
        sin(θ)


    println()

    println(
        "Load components:"
    )


    println(
        "Fx = P cos(theta) = ",
        round(
            Fx,
            digits = 6
        )
    )


    println(
        "Fy = P sin(theta) = ",
        round(
            Fy,
            digits = 6
        )
    )


    println()

    println(
        "The reaction functions are:"
    )


    println()

    println(
        "VB(x) = -(x*Fy - y(x)*Fx)/L"
    )


    println()

    println(
        "VA(x) = -Fy - VB(x)"
    )


    println()

    println(
        "For x <= L/2:"
    )


    println(
        "HA(x) = [(L/2)*VA(x) - ((x-L/2)*Fy - (y(x)-f)*Fx)] / f"
    )


    println()

    println(
        "For x > L/2:"
    )


    println(
        "HA(x) = (L/2)*VA(x)/f"
    )


    println()

    println(
        "HB(x) = -Fx - HA(x)"
    )

end




end # module
