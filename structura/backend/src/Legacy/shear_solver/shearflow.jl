"""Quadratic q(s) on a wall, where 0 <= s <= L follows its input orientation."""
struct WallFlow
    i::Int
    j::Int
    t::Float64
    L::Float64
    coefficients::NTuple{3,Float64}
    q_start::Float64
    q_mid::Float64
    q_end::Float64
    tau_max::Float64
    integral_q::Float64
end

function flow_at(w::WallFlow, s::Real)
    0 <= s <= w.L || throw(ArgumentError("s must lie in [0, L]."))
    a, b, c = w.coefficients
    return a+s*(b+s*c)
end

"""Compute signed flow and exact force/torque integrals for a load in N.

q' = -t*(alpha*y + beta*x). In postorder each branch contributes its
first moments to its parent. A cut's starting flow includes the complete
downstream subtree, imposing zero free-edge flow and junction continuity.
Reversing a supplied segment changes q's sign but not physical forces.
"""
function shear_flow(section::Section, Vx::Real, Vy::Real)
    all(isfinite, (Vx, Vy)) || throw(ArgumentError("Shears must be finite."))
    p = section_properties(section)
    tree = rooted_tree(section)
    alpha = (Vy*p.Iyy-Vx*p.Ixy)/p.D
    beta = (Vx*p.Ixx-Vy*p.Ixy)/p.D
    Qx = Dict(id => 0.0 for id in tree.order)
    Qy = copy(Qx)
    walls = Vector{WallFlow}(undef, length(section.segments))
    for child in reverse(tree.order[2:end])
        parent = tree.parent[child]
        k = tree.edge[child]
        wall = section.segments[k]
        x, y = section.nodes[parent] .- (p.xc, p.yc)
        dx, dy = section.nodes[child] .- section.nodes[parent]
        L = hypot(dx, dy)
        ux, uy = dx/L, dy/L
        sx = Qx[child] + wall.t*L*(y+dy/2)
        sy = Qy[child] + wall.t*L*(x+dx/2)
        a = alpha*sx+beta*sy
        b = -wall.t*(alpha*y+beta*x)
        c = -wall.t*(alpha*uy+beta*ux)/2
        Qx[parent] += sx; Qy[parent] += sy
        if wall.i != parent
            a, b, c = -(a+b*L+c*L^2), b+2c*L, -c
        end
        value(s) = a+s*(b+s*c)
        q0, qm, q1 = value(0), value(L/2), value(L)
        peak = max(abs(q0), abs(q1))
        if c != 0
            sv = -b/(2c)
            0 < sv < L && (peak = max(peak, abs(value(sv))))
        end
        walls[k] = WallFlow(wall.i, wall.j, wall.t, L, (a,b,c), q0, qm, q1,
                            peak/wall.t, L*(q0+4qm+q1)/6)
    end
    Fx = Fy = Mz = 0.0
    node_balance = Dict(id => 0.0 for id in tree.order)
    for w in walls
        dx, dy = section.nodes[w.j] .- section.nodes[w.i]
        x, y = section.nodes[w.i] .- (p.xc, p.yc)
        Fx += w.integral_q*dx/w.L
        Fy += w.integral_q*dy/w.L
        Mz += w.integral_q*(x*dy-y*dx)/w.L
        node_balance[w.i] -= w.q_start
        node_balance[w.j] += w.q_end
    end
    load_scale = max(hypot(Vx, Vy), eps(Float64))
    residual = hypot(Fx-Vx, Fy-Vy)
    residual <= 1e-9*load_scale || error("Shear resultant check failed: ($Fx, $Fy) != ($Vx, $Vy).")
    qscale = max(maximum(w -> max(abs(w.q_start),abs(w.q_mid),abs(w.q_end)), walls), eps(Float64))
    continuity = maximum(abs, values(node_balance))
    continuity <= 1e-9*qscale || error("Free-edge/junction flow continuity check failed.")
    all(isfinite, (Fx,Fy,Mz,maximum(w.tau_max for w in walls))) ||
        error("Non-finite shear solution.")
    return (; Vx=Float64(Vx), Vy=Float64(Vy), walls, Fx, Fy, Mz,
            principal_shear=principal_components(p,Vx,Vy),
            tau_max=maximum(w.tau_max for w in walls),
            resultant_residual=residual, continuity_residual=continuity)
end
