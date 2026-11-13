function positive_dimensions(values...)
    all(x -> isfinite(x) && x > 0, values) ||
        throw(ArgumentError("Dimensions must be finite and positive."))
end

"""Channel: web x=0, depth h, flanges extending to x=b; centreline mm."""
function channel_section(b::Real, h::Real, tw::Real, tf::Real=tw)
    positive_dimensions(b, h, tw, tf)
    Section(Dict(1=>(b,0), 2=>(0,0), 3=>(0,h), 4=>(b,h)),
            [(1,2,tf), (2,3,tw), (3,4,tf)]; name="Channel")
end

"""Angle: horizontal leg b and vertical leg h from the centreline junction (0,0)."""
function angle_section(b::Real, h::Real, t::Real)
    positive_dimensions(b, h, t)
    Section(Dict(1=>(b,0), 2=>(0,0), 3=>(0,h)), [(1,2,t),(2,3,t)]; name="Angle")
end

"""T: total centreline flange width b, stem depth h, junction (0,h)."""
function tee_section(b::Real, h::Real, tw::Real, tf::Real=tw)
    positive_dimensions(b, h, tw, tf)
    Section(Dict(1=>(-b/2,h),2=>(0,h),3=>(b/2,h),4=>(0,0)),
            [(1,2,tf),(2,3,tf),(4,2,tw)]; name="T-section")
end

"""I: total centreline flange width b, web depth h; two split flanges."""
function i_section(b::Real, h::Real, tw::Real, tf::Real=tw)
    positive_dimensions(b, h, tw, tf)
    Section(Dict(1=>(-b/2,0),2=>(0,0),3=>(b/2,0),
                 4=>(-b/2,h),5=>(0,h),6=>(b/2,h)),
            [(1,2,tf),(2,3,tf),(2,5,tw),(4,5,tf),(5,6,tf)]; name="I-section")
end

"""Point-symmetric Z: opposing centreline flanges of length b, web depth h."""
function z_section(b::Real, h::Real, tw::Real, tf::Real=tw)
    positive_dimensions(b, h, tw, tf)
    Section(Dict(1=>(-b,0),2=>(0,0),3=>(0,h),4=>(b,h)),
            [(1,2,tf),(2,3,tw),(3,4,tf)]; name="Z-section")
end
