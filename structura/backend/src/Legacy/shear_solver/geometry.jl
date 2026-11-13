struct ClosedCellError <: Exception end
Base.showerror(io::IO, ::ClosedCellError) = print(io,
    "Closed cells are Phase 2: circulating flows and compatibility are not implemented.")

"""Straight wall with positive thickness t (mm), oriented i -> j."""
struct Segment
    i::Int
    j::Int
    t::Float64
end

"""Validated connected open wall graph. Optional E and G are in N/mm²."""
struct Section
    nodes::Dict{Int,NTuple{2,Float64}}
    segments::Vector{Segment}
    E::Union{Nothing,Float64}
    G::Union{Nothing,Float64}
    name::String
    function Section(nodes, segments; E=nothing, G=nothing, name="Custom section")
        xy = Dict{Int,NTuple{2,Float64}}()
        for (id, p) in pairs(nodes)
            key = id isa AbstractString ? parse(Int, id) : Int(id)
            haskey(xy, key) && throw(ArgumentError("Duplicate node ID $key."))
            length(p) == 2 || throw(ArgumentError("Node $key needs x and y."))
            all(isfinite, p) || throw(ArgumentError("Node coordinates must be finite."))
            xy[key] = (Float64(p[1]), Float64(p[2]))
        end
        walls = Segment[s isa Segment ? s : Segment(s[1], s[2], s[3]) for s in segments]
        isempty(walls) && throw(ArgumentError("At least one wall is required."))
        for value in (E, G)
            isnothing(value) || (isfinite(value) && value > 0) ||
                throw(ArgumentError("E and G must be finite and positive."))
        end
        adj = Dict(id => Int[] for id in keys(xy))
        edges = Set{Tuple{Int,Int}}()
        for s in walls
            haskey(xy, s.i) && haskey(xy, s.j) ||
                throw(ArgumentError("Wall references an unknown node."))
            isfinite(s.t) && s.t > 0 || throw(ArgumentError("Thickness must be finite and positive."))
            xy[s.i] != xy[s.j] || throw(ArgumentError("Zero-length wall."))
            edge = minmax(s.i, s.j)
            edge in edges && throw(ArgumentError("Duplicate wall $edge."))
            push!(edges, edge)
            push!(adj[s.i], s.j); push!(adj[s.j], s.i)
        end
        visited = Set{Int}()
        stack = [first(keys(xy))]
        while !isempty(stack)
            id = pop!(stack)
            id in visited && continue
            push!(visited, id)
            append!(stack, adj[id])
        end
        length(visited) == length(xy) || throw(ArgumentError("Section must be connected; remove unused nodes."))
        length(walls) == length(xy)-1 || throw(ClosedCellError())
        # Intersections must be explicit graph junctions. Reject overlapping walls too.
        span = maximum(hypot((xy[s.j] .- xy[s.i])...) for s in walls)
        tol = 1e-10 * span
        for a in 1:length(walls), b in a+1:length(walls)
            sa, sb = walls[a], walls[b]
            p, q = xy[sa.i], xy[sb.i]
            r, v = xy[sa.j] .- p, xy[sb.j] .- q
            cross(u, w) = u[1]*w[2] - u[2]*w[1]
            d = cross(r, v)
            shared = !isempty(intersect((sa.i, sa.j), (sb.i, sb.j)))
            if abs(d) > 1e-12 * hypot(r...) * hypot(v...)
                u, w = cross(q .- p, v)/d, cross(q .- p, r)/d
                if -1e-10 <= u <= 1+1e-10 && -1e-10 <= w <= 1+1e-10 && !shared
                    throw(ArgumentError("Walls intersect without a shared node; split walls at the junction."))
                end
            elseif abs(cross(q .- p, r)) <= tol * hypot(r...)
                rr = sum(abs2, r)
                lo, hi = minmax(sum((q .- p) .* r)/rr, sum((xy[sb.j] .- p) .* r)/rr)
                overlap = min(1.0, hi) - max(0.0, lo)
                if overlap > 1e-10 || (overlap >= -1e-10 && !shared)
                    throw(ArgumentError("Collinear walls overlap or meet without a shared node."))
                end
            end
        end
        new(xy, walls, E, G, String(name))
    end
end

"""Root the tree deterministically; return parent and edge lookup plus preorder."""
function rooted_tree(section::Section)
    adj = Dict(id => Tuple{Int,Int}[] for id in keys(section.nodes))
    for (k, s) in enumerate(section.segments)
        push!(adj[s.i], (s.j, k)); push!(adj[s.j], (s.i, k))
    end
    root = minimum(id for (id, edges) in adj if length(edges) == 1)
    parent = Dict(root => root)
    edge = Dict{Int,Int}()
    order = [root]
    cursor = 1
    while cursor <= length(order)
        id = order[cursor]
        for (child, k) in adj[id]
            haskey(parent, child) && continue
            parent[child] = id; edge[child] = k
            push!(order, child)
        end
        cursor += 1
    end
    return (; root, parent, edge, order, adj)
end
