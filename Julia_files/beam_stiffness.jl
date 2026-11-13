module BeamStiffness

using LinearAlgebra
using Printf

export solve_beam, element_stiffness, fixed_end_load, element_response,
       sample_beam, beam_checks, beam_report, equation_summary

# Public inputs: m, Pa, m^4, kN, kN/m, kN-m. Spring stiffness is N/m.
# All assembly and element calculations use N and m internally.
# v is upward, theta and external moments are counterclockwise positive.
# Distributed intensity w is DOWNWARD positive; internal M is sagging positive.

function element_stiffness(EI, L)
    isfinite(EI) && EI > 0 && isfinite(L) && L > 0 ||
        throw(ArgumentError("EI and element length must be finite and positive."))
    return EI / L^3 .* [12.0 6L -12.0 6L;
                       6L 4L^2 -6L 2L^2;
                       -12.0 -6L 12.0 -6L;
                       6L 2L^2 -6L 4L^2]
end

"""Fixed-end reactions for a linear downward load, from wa to wb (N/m)."""
function fixed_end_load(wa, wb, L)
    # Integral of cubic Hermite shape functions times w(x).
    # With wa=wb=w this is [wL/2, wL^2/12, wL/2, -wL^2/12].
    return [L*(7wa + 3wb)/20, L^2*(3wa + 2wb)/60,
            L*(3wa + 7wb)/20, -L^2*(2wa + 3wb)/60]
end

function validate_model(L, nodes, supports, loads, sections)
    isfinite(L) && L > 0 || throw(ArgumentError("Invalid beam length."))
    for (i, node) in enumerate(nodes)
        node.ID == i || throw(ArgumentError("Input node IDs must be consecutive from 1."))
        isfinite(node.x) && 0 <= node.x <= L ||
            throw(ArgumentError("Node distances must lie within the beam."))
    end
    length(unique(n.x for n in nodes)) == length(nodes) ||
        throw(ArgumentError("Duplicate input node distances are not allowed."))
    isempty(sections) && throw(ArgumentError("At least one section is required."))
    edge = 0.0
    for s in sections
        s.Start == edge && isfinite(s.End) && s.Start < s.End <= L ||
            throw(ArgumentError("Sections must cover the beam in order, without gaps or overlaps."))
        isfinite(s.E) && s.E > 0 && isfinite(s.I) && s.I > 0 && isfinite(s.E*s.I) ||
            throw(ArgumentError("Every section requires finite positive E and I."))
        edge = s.End
    end
    edge == L || throw(ArgumentError("Sections must cover the entire beam."))
    used = Set{Int}()
    for s in supports
        1 <= s.Node <= length(nodes) || throw(ArgumentError("Invalid support node."))
        s.Node in used && throw(ArgumentError("Only one support may be assigned per input node."))
        push!(used, s.Node)
        s.Type in ("fixed", "pin", "roller", "spring") ||
            throw(ArgumentError("Unknown support type: $(s.Type)"))
        isfinite(get(s, :Settlement, 0.0)) || throw(ArgumentError("Nonfinite settlement."))
        if s.Type == "spring"
            k = get(s, :Stiffness, 0.0)
            isfinite(k) && k > 0 || throw(ArgumentError("Spring stiffness must be positive and finite."))
        end
    end
    for load in loads
        if load.Type in ("Point Load", "Moment")
            isfinite(load.Location) && 0 <= load.Location <= L && isfinite(load.Magnitude) ||
                throw(ArgumentError("Invalid point load or moment."))
        elseif load.Type in ("UDL", "UVL")
            isfinite(load.Start) && isfinite(load.End) && 0 <= load.Start < load.End <= L ||
                throw(ArgumentError("Invalid distributed load interval."))
            intensities = load.Type == "UDL" ? (load.Intensity,) :
                (load.StartIntensity, load.EndIntensity)
            all(isfinite, intensities) || throw(ArgumentError("Nonfinite load intensity."))
        else
            throw(ArgumentError("Unknown load type: $(load.Type)"))
        end
    end
end

"""
Solve a continuous Euler-Bernoulli beam, including determinate beams.
Sections are ordered (Start, End, E, I) records covering [0, beam_length].
Supports use original input node IDs; automatic mesh nodes do not change them.
Settlement is prescribed v (m), or spring base displacement (m), upward positive.
"""
function solve_beam(beam_length, node_data, supports, loads;
                    E, I, sections=[(Start=0.0, End=beam_length, E=E, I=I)])
    validate_model(beam_length, node_data, supports, loads, sections)
    xs = Float64[0, beam_length]
    append!(xs, [n.x for n in node_data])
    for s in sections
        append!(xs, [s.Start, s.End])
    end
    for load in loads
        if load.Type in ("Point Load", "Moment")
            push!(xs, load.Location)
        else
            append!(xs, [load.Start, load.End])
        end
    end
    sort!(unique!(xs))
    index = Dict(x => i for (i,x) in enumerate(xs))
    ndof = 2length(xs)
    Kbeam = zeros(ndof, ndof)
    Fload = zeros(ndof)
    elements = NamedTuple[]

    for j in 1:length(xs)-1
        a, b = xs[j], xs[j+1]
        L = b-a
        section = only(s for s in sections if s.Start <= a && b <= s.End)
        wa, wb = 0.0, 0.0
        for load in loads
            if load.Type in ("UDL", "UVL") && load.Start <= a && b <= load.End
                if load.Type == "UDL"
                    wa += 1000load.Intensity
                    wb += 1000load.Intensity
                else
                    gradient = (load.EndIntensity-load.StartIntensity)/(load.End-load.Start)
                    wa += 1000*(load.StartIntensity + gradient*(a-load.Start))
                    wb += 1000*(load.StartIntensity + gradient*(b-load.Start))
                end
            end
        end
        EI = section.E*section.I
        ke = element_stiffness(EI, L)
        ffe = fixed_end_load(wa, wb, L)
        dofs = [2j-1, 2j, 2j+1, 2j+2]
        Kbeam[dofs,dofs] += ke
        Fload[dofs] -= ffe
        push!(elements, (Start=a, End=b, L=L, E=section.E, I=section.I,
                         EI=EI, w0=wa, gradient=(wb-wa)/L, k=ke, ffe=ffe, dofs=dofs))
    end
    for load in loads
        if load.Type == "Point Load"
            Fload[2index[load.Location]-1] -= 1000load.Magnitude
        elseif load.Type == "Moment"
            Fload[2index[load.Location]] += 1000load.Magnitude
        end
    end

    K, F = copy(Kbeam), copy(Fload)
    prescribed = Dict{Int,Float64}()
    for s in supports
        n = index[node_data[s.Node].x]
        v = 2n-1
        settlement = get(s, :Settlement, 0.0)
        if s.Type == "spring"
            K[v,v] += s.Stiffness
            F[v] += s.Stiffness*settlement
        else
            prescribed[v] = settlement
            s.Type == "fixed" && (prescribed[2n] = 0.0)
        end
    end
    constrained = sort!(collect(keys(prescribed)))
    free = setdiff(1:ndof, constrained)
    d = zeros(ndof)
    for (i,value) in prescribed
        d[i] = value
    end
    if !isempty(free)
        A = K[free,free]
        # Diagonal scaling makes the mechanism check less sensitive to units.
        scale = 1 ./ sqrt.(diag(A))
        As = Symmetric((scale .* A) .* scale')
        ev = eigvals(As)
        minimum(ev) > 1e-12maximum(ev) ||
            throw(ArgumentError("Beam bending model is unstable or too ill-conditioned. Check restraints, springs, and very short elements."))
        rhs = F[free] - K[free,constrained]*d[constrained]
        d[free] = scale .* (cholesky(As) \ (scale .* rhs))
    end

    # Physical support forces exclude the artificial spring-base load in F.
    residual = Kbeam*d-Fload
    reactions = NamedTuple[]
    for s in supports
        x = node_data[s.Node].x
        n = index[x]
        vertical = s.Type == "spring" ? s.Stiffness*(get(s,:Settlement,0.0)-d[2n-1]) : residual[2n-1]
        moment = s.Type == "fixed" ? residual[2n] : 0.0
        push!(reactions, (Node=s.Node, MeshNode=n, x=x, Type=s.Type,
                          Vertical=vertical, Moment=moment))
    end
    solved_elements = [merge(e, (d=d[e.dofs], forces=e.k*d[e.dofs]+e.ffe)) for e in elements]
    return (x=xs, d=d, elements=solved_elements, reactions=reactions,
            K=K, F=F, Kbeam=Kbeam, Fload=Fload, free=free,
            prescribed=prescribed, loads=loads, length=Float64(beam_length))
end

"""Exact response at local distance t; forces are N and N-m, v is m."""
function element_response(e, t)
    0 <= t <= e.L || throw(ArgumentError("Local position outside element."))
    V1, M1 = e.forces[1:2]
    w, g = e.w0, e.gradient
    V = V1-w*t-g*t^2/2
    M = -M1+V1*t-w*t^2/2-g*t^3/6
    theta = e.d[2]+(-M1*t+V1*t^2/2-w*t^3/6-g*t^4/24)/e.EI
    v = e.d[1]+e.d[2]*t+(-M1*t^2/2+V1*t^3/6-w*t^4/24-g*t^5/120)/e.EI
    return (V=V, M=M, theta=theta, v=v)
end

# Ascending polynomial coefficients. Scale the independent variable to [0,1]
# before solving so roots used for extrema do not depend strongly on span units.
function interval_roots(coeffs, L)
    c = Float64[coeffs[i]*L^(i-1) for i in eachindex(coeffs)]
    scale = maximum(abs, c)
    scale == 0 && return Float64[]
    c ./= scale
    while length(c)>1 && abs(c[end])<1e-14
        pop!(c)
    end
    degree = length(c)-1
    degree == 0 && return Float64[]
    A = zeros(degree,degree)
    for i in 2:degree
        A[i,i-1] = 1.0
    end
    A[:,end] = -c[1:end-1]/c[end]
    roots = [clamp(real(z),0.0,1.0)*L for z in eigvals(A)
             if abs(imag(z))<1e-8 && -1e-10<=real(z)<=1+1e-10]
    return sort!(unique!(roots))
end

function sample_beam(solution; points_per_element=51)
    points_per_element >= 2 || throw(ArgumentError("At least two sample points are required."))
    xs, vs, ms, ts, ds = (Float64[] for _ in 1:5)
    zero_shear = Float64[]
    zero_shear_intervals = Tuple{Float64,Float64}[]
    for e in solution.elements
        V1,M1 = e.forces[1:2]
        shear = [V1,-e.w0,-e.gradient/2]
        moment = [-M1,V1,-e.w0/2,-e.gradient/6]
        slope = [e.d[2],-M1/e.EI,V1/(2e.EI),-e.w0/(6e.EI),-e.gradient/(24e.EI)]
        zr = interval_roots(shear,e.L)
        append!(zero_shear,e.Start .+ zr)
        all(iszero,shear) && push!(zero_shear_intervals,(e.Start,e.End))
        positions = sort!(unique!(vcat(collect(range(0,e.L,length=points_per_element)),
            interval_roots([-e.w0,-e.gradient],e.L),zr,
            interval_roots(moment,e.L),interval_roots(slope,e.L))))
        for t in positions
            r = element_response(e,t)
            push!(xs,e.Start+t)
            push!(vs,r.V/1000)
            push!(ms,r.M/1000)
            push!(ts,r.theta)
            push!(ds,r.v*1000)
        end
    end
    # Both sides of every element boundary are retained, drawing true jumps.
    return (x=xs,V=vs,M=ms,theta=ts,v_mm=ds,
            zero_shear=sort!(unique!(zero_shear)),zero_shear_intervals=zero_shear_intervals)
end

function beam_checks(s; rtol=1e-7)
    R = zeros(length(s.d))
    for r in s.reactions
        R[2r.MeshNode-1] += r.Vertical
        R[2r.MeshNode] += r.Moment
    end
    balance = s.Fload+R
    force_error = sum(balance[1:2:end])
    moment_error = sum(balance[1:2:end].*s.x)+sum(balance[2:2:end])
    force_scale = max(1.0,sum(abs,s.Fload[1:2:end])+sum(abs,R[1:2:end]))
    moment_scale = max(1.0,force_scale*s.length,sum(abs,s.Fload[2:2:end])+sum(abs,R[2:2:end]))
    v_scale = max(1.0,maximum(abs,s.d[1:2:end]))
    theta_scale = max(1.0,maximum(abs,s.d[2:2:end]))
    end_force_error,end_moment_error,v_error,theta_error = 0.0,0.0,0.0,0.0
    for e in s.elements
        r = element_response(e,e.L)
        end_force_error = max(end_force_error,abs(r.V+e.forces[3]))
        end_moment_error = max(end_moment_error,abs(r.M-e.forces[4]))
        v_error = max(v_error,abs(r.v-e.d[3]))
        theta_error = max(theta_error,abs(r.theta-e.d[4]))
    end
    jump_v,jump_m = 0.0,0.0
    for j in 2:length(s.x)-1
        left = element_response(s.elements[j-1],s.elements[j-1].L)
        right = element_response(s.elements[j],0.0)
        force,moment = R[2j-1],R[2j]
        for load in s.loads
            if load.Type == "Point Load" && load.Location == s.x[j]
                force -= 1000load.Magnitude
            elseif load.Type == "Moment" && load.Location == s.x[j]
                moment += 1000load.Magnitude
            end
        end
        jump_v = max(jump_v,abs(right.V-left.V-force))
        jump_m = max(jump_m,abs(right.M-left.M+moment))
    end
    bc_error = maximum((abs(s.d[i]-v) for (i,v) in s.prescribed);init=0.0)
    free_residual = s.K*s.d-s.F
    free_force = maximum(abs.(free_residual[intersect(s.free,1:2:length(s.d))]);init=0.0)
    free_moment = maximum(abs.(free_residual[intersect(s.free,2:2:length(s.d))]);init=0.0)
    passed = max(abs(force_error),end_force_error,jump_v,free_force) <= rtol*force_scale &&
        max(abs(moment_error),end_moment_error,jump_m,free_moment) <= rtol*moment_scale &&
        v_error <= rtol*v_scale && theta_error <= rtol*theta_scale && bc_error <= rtol
    return (passed=passed,force_error=force_error,moment_error=moment_error,
            end_force_error=end_force_error,end_moment_error=end_moment_error,
            v_error=v_error,theta_error=theta_error,jump_force_error=jump_v,
            jump_moment_error=jump_m,bc_error=bc_error,
            free_force_error=free_force,free_moment_error=free_moment)
end

function equation_summary(s)
    io = IOBuffer()
    println(io,"Local t = x - element start; 0 <= t <= element length")
    println(io,"SI units: N, m, Pa; w(t) = w0 + g*t (downward positive)")
    println(io,"V(t) = V1 - w0*t - g*t^2/2")
    println(io,"M(t) = -M1 + V1*t - w0*t^2/2 - g*t^3/6")
    println(io,"theta(t) = theta1 + (-M1*t + V1*t^2/2 - w0*t^3/6 - g*t^4/24)/EI")
    println(io,"v(t) = v1 + theta1*t + (-M1*t^2/2 + V1*t^3/6 - w0*t^4/24 - g*t^5/120)/EI")
    println(io,"v is upward positive; theta is in radians; M is sagging positive.")
    for (i,e) in enumerate(s.elements)
        @printf(io,"\nElement %d: x = %.6g to %.6g m; EI = %.7g N-m^2\n",i,e.Start,e.End,e.EI)
        @printf(io,"  V1 = %.7g N; M1 = %.7g N-m; w0 = %.7g N/m; g = %.7g N/m^2\n",e.forces[1],e.forces[2],e.w0,e.gradient)
        @printf(io,"  v1 = %.9g m; theta1 = %.9g rad\n",e.d[1],e.d[2])
    end
    return String(take!(io))
end

function beam_report(s, samples=sample_beam(s))
    io = IOBuffer()
    println(io,"BEAM ANALYSIS - DIRECT STIFFNESS METHOD")
    println(io,"Bending model: v and theta only; axial stability/reactions are not analyzed.")
    println(io,"Continuous Euler-Bernoulli beam; E and I are constant within each section.")
    println(io,"\nSUPPORT REACTIONS (upward and anticlockwise positive)")
    for r in s.reactions
        @printf(io,"Input node %d / mesh node %d at x=%.6g m (%s): V=%.9g kN, M=%.9g kN-m\n",r.Node,r.MeshNode,r.x,r.Type,r.Vertical/1000,r.Moment/1000)
    end
    println(io,"\nMESH NODAL DISPLACEMENTS")
    for (i,x) in enumerate(s.x)
        @printf(io,"Node %d: x=%.6g m, v=%.9g mm, theta=%.9g rad\n",i,x,1000s.d[2i-1],s.d[2i])
    end
    println(io,"\nELEMENT END FORCES [V1, M1, V2, M2] (kN, kN-m)")
    for (i,e) in enumerate(s.elements)
        println(io,"Element $i: ",e.forces/1000)
    end
    println(io,"\nPIECEWISE EQUATIONS AND COEFFICIENTS")
    print(io,equation_summary(s))
    println(io,"\nEXTREMA (including polynomial stationary points and both sides of jumps)")
    for (label,values,unit) in (("V",samples.V,"kN"),("M",samples.M,"kN-m"),
                               ("theta",samples.theta,"rad"),("v",samples.v_mm,"mm"))
        lo,hi = argmin(values),argmax(values)
        @printf(io,"%s: min=%.9g %s at x=%.9g m; max=%.9g %s at x=%.9g m\n",label,values[lo],unit,samples.x[lo],values[hi],unit,samples.x[hi])
    end
    println(io,"Zero-shear positions (m): ",samples.zero_shear)
    println(io,"Intervals with identically zero shear (m): ",samples.zero_shear_intervals)
    checks = beam_checks(s)
    println(io,"\nVERIFICATION: ",checks.passed ? "PASS" : "FAIL - inspect residuals before using results")
    for key in keys(checks)
        key == :passed && continue
        @printf(io,"%s = %.6e (N, N-m, m or rad as applicable)\n",string(key),getproperty(checks,key))
    end
    return String(take!(io))
end

end # module
