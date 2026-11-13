"""Solve unit shears and the requested force. SC coordinates are in mm."""
function solve_section(section::Section; Vx::Real=0.0, Vy::Real=1.0)
    properties = section_properties(section)
    unit_y = shear_flow(section, 0.0, 1.0)
    unit_x = shear_flow(section, 1.0, 0.0)
    applied = shear_flow(section, Vx, Vy)
    xs, ys = unit_y.Mz, -unit_x.Mz
    centre = (; xs, ys, x=xs+properties.xc, y=ys+properties.yc, distance=hypot(xs,ys))
    return (; section, properties, centre, unit_y, unit_x, applied)
end

"""Small built-in benchmark report; the full regression suite is in tests/."""
function validation_report()
    h, b, tw, tf = 200.0, 75.0, 6.0, 12.0
    expected = -3b^2*tf/(h*tw+6b*tf)
    checks = Pair{String,Bool}[]
    for (name, section, x, y) in [
        ("channel unequal thickness", channel_section(b,h,tw,tf), expected, h/2),
        ("channel equal thickness", channel_section(b,h,tw), -3b^2/(h+6b), h/2),
        ("angle junction", angle_section(b,b,tw), 0.0, 0.0),
        ("T junction", tee_section(b,h,tw,tf), 0.0, h),
        ("I symmetry", i_section(b,h,tw,tf), 0.0, h/2),
        ("Z point symmetry", z_section(b,h,tw,tf), 0.0, h/2)]
        r = solve_section(section; Vx=31.0, Vy=-47.0)
        push!(checks, name => hypot(r.centre.x-x,r.centre.y-y) < 1e-9*h)
    end
    return checks
end
