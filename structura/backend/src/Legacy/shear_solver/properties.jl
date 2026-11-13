"""Exact line-area integrals, including each wall's t*L³/12 contribution.
No through-thickness t³ correction: this is a consistent centreline model.
Ixy = integral(x*y*dA), with x,y measured from the centroid.
"""
function section_properties(section::Section)
    # Work relative to a nearby node to avoid large-origin cancellation.
    origin = section.nodes[minimum(keys(section.nodes))]
    A = mx = my = 0.0
    for s in section.segments
        p, q = section.nodes[s.i] .- origin, section.nodes[s.j] .- origin
        area = s.t * hypot((q .- p)...)
        A += area
        mx += area * (p[1]+q[1])/2
        my += area * (p[2]+q[2])/2
    end
    cx, cy = mx/A, my/A
    Ixx = Iyy = Ixy = 0.0
    for s in section.segments
        p, q = section.nodes[s.i] .- origin, section.nodes[s.j] .- origin
        dx, dy = q .- p
        area = s.t * hypot(dx, dy)
        x, y = (p[1]+q[1])/2-cx, (p[2]+q[2])/2-cy
        Ixx += area * (y*y + dy*dy/12)
        Iyy += area * (x*x + dx*dx/12)
        Ixy += area * (x*y + dx*dy/12)
    end
    D = Ixx*Iyy-Ixy^2
    all(isfinite, (A, cx, cy, Ixx, Iyy, Ixy, D)) && A > 0 ||
        throw(ArgumentError("Geometry is outside the finite numerical range."))
    Ixx > 0 && Iyy > 0 && D > 1e-12*Ixx*Iyy ||
        throw(ArgumentError("Singular or ill-conditioned inertia: walls must span two dimensions."))
    radius = hypot((Ixx-Iyy)/2, Ixy)
    I1 = (Ixx+Iyy)/2 + radius
    I2 = D/I1
    theta = radius <= 1e-14*(Ixx+Iyy) ? 0.0 : atan(-2Ixy, Ixx-Iyy)/2
    c, s = cos(theta), sin(theta)
    rotation = [c s; -s c]
    return (; A, xc=cx+origin[1], yc=cy+origin[2], Ixx, Iyy, Ixy, D,
            I1, I2, theta, rotation)
end

"""Force components along principal axes; theta is in radians."""
principal_components(p, Vx::Real, Vy::Real) = p.rotation * [Vx, Vy]
