# a turn is a left turn if between these headings
# note that these do overlap, because there is some ambiguity in whether some turns
# are straight/right/left etc, and may depend on perceptions.
const LEFT_TURN_RANGES = [(-170, -15)]
const STRAIGHT_RANGES = [(-30, 30)]
const RIGHT_TURN_RANGES = [(15, 170)]
const U_TURN_RANGES = [(-Inf32, -95), (95, Inf32)]

# make sure we don't get any weird/unexpected restrictions, like
# no_right_turn_on_red
const VALID_RESTRICTION = Set([
    "no_left_turn",
    "no_right_turn",
    "no_u_turn",
    "no_straight_on",
    "only_left_turn",
    "only_right_turn",
    "only_u_turn",
    "only_straight_on",
])

struct TurnRestriction
    segments::AbstractVector{Int64}
    osm_id::Int64
end

# Get the restriction type (no_left_turn etc) for a restriction
function get_rtype(r)
    if haskey(r.tags, "restriction")
        return r.tags["restriction"]
    elseif haskey(r.tags, "restriction:motorcar")
        return r.tags["restriction:motorcar"]
    else
        error("unreachable code")
    end
end

function process_turn_restrictions(infile, G)
    @info "indexing ways"
    # This index represents all vertices that represent each way
    vertices_for_way = DefaultDict(Vector{Int64})
    @showprogress for vertex in 1:nv(G)
        push!(vertices_for_way[get_prop(G, vertex, :way)], vertex)
    end

    n_wildcard = 0
    turn_restrictions = Vector{TurnRestriction}()
    @info "Parsing turn restrictions"
    rprog = ProgressUnknown()
    scan_relations(infile) do r
        # first, check if this is a turn restriction
        if haskey(r.tags, "type") && r.tags["type"] == "restriction" && any(haskey.([r.tags], ["restriction", "restriction:motorcar"])) &&
                !(haskey(r.tags, "except") && occursin("motorcar", r.tags["except"]))
            ProgressMeter.next!(rprog)

            rtype = get_rtype(r)

            if !(rtype in VALID_RESTRICTION)
                n_wildcard += 1
                @warn "Skipping restriction $(r.id) with unknown type $rtype"
            else
                # parse the restriction
                from = nothing
                to = nothing
                via = Vector{OpenStreetMapPBF.RelationMember}()

                # sort members into roles
                for member in r.members
                    if member.role == "from"
                        if !isnothing(from)
                            @warn "Relation $(r.id) has multiple from members"
                        end
                        from = member
                    elseif member.role == "to"
                        if !isnothing(to)
                            @warn "Relation $(r.id) has multiple to members"
                        end
                        to = member
                    elseif member.role == "via"
                        push!(via, member)
                    else
                        @warn "Ignoring member with role $(member.role) in relation $(r.id)"
                    end
                end

                if isnothing(from)
                    @warn "Relation $(r.id) is missing from way"
                    return
                end

                if isnothing(to)
                    @warn "Relation $(r.id) is missing to way"
                    return
                end

                parsed = if length(via) == 1 && via[1].type == OpenStreetMapPBF.node
                     process_simple_restriction(r, from, to, via[1], G, vertices_for_way)
                elseif length(via) ≥ 1 && all(map(v -> v.type == OpenStreetMapPBF.way, via))
                     process_complex_restriction(r, G, vertices_for_way)
                elseif length(via) == 0
                    @warn "restriction $(r.id) has no via members, skipping"
                    nothing
                else
                    @warn "via members of restriction $(r.id) are invalid (multiple nodes, mixed nodes/ways, relation members), skipping"
                    nothing
                end

                if !isnothing(parsed)
                    if startswith(rtype, "no_")
                        push!(turn_restrictions, parsed)
                    # elseif startswith(rtype, "only_")
                    #     restrictions = convert_restriction_to_only_turn(parsed, G)
                    #     append!(turn_restrictions, restrictions)
                    else
                        @error "Skipping turn restriction of type $rtype"
                    end
                end
            end
        end
    end

    @info "created $(length(turn_restrictions)) turn restrictions"

    if n_wildcard > 0
        @warn "Ignored $n_wildcard no_entry or no_exit restrictions"
    end 

    apply_turn_restrictions!(G, turn_restrictions)
end

function process_simple_restriction(restric, from, to, via, G, vertices_for_way)
    # all the segments each way got split into
    if !haskey(vertices_for_way, from.id)
        @warn "Way $(from.id) referenced in restriction $(restric.id), but not in graph"
        return
    end

    if !haskey(vertices_for_way, to.id)
        @warn "Way $(to.id) referenced in restriction $(restric.id), but not in graph"
        return
    end

    origin_candidates = vertices_for_way[from.id]
    destination_candidates = vertices_for_way[to.id]
    
    # locate the correct way segment
    #= check all possible combinations
    this is complicated by the fact that OSM ways are undirected. Consider a situation like this:
    
    ---------Main St--------+-------------------------
                            |
                            E                ^
                            l                N
                            m

                            S
                            t
                            |
                            |

    Suppose there is a no-left restriction from Main St to Elm St. We have to actually look at
    turn angles to figure out that this means WB Main -> SB Elm is prohibited, and EB Main -> SB Elm
    is allowed.

    It might be useful to have additional tags in restrictions for from_direction = forward/backward and to_direction
    # forward on both edges
    
    =#
    matching_turns = filter(reshape(collect(Base.product(origin_candidates, destination_candidates)), :)) do (fr, to)
        # check that these connect at the via node
        (get_prop(G, fr, :to_node) == via.id) &&
        (get_prop(G, to, :from_node) == via.id)
    end |> collect

    rtype = get_rtype(restric)

    if length(matching_turns) == 1
        angle = get_prop(G, matching_turns[1]..., :turn_angle)
        if !is_turn_type(angle, rtype)
            @warn "Restriction $(restric.id) is nonambiguous, but indicates it should be of type $(rtype), but has bearing $(angle); including anyways"
        end
        return TurnRestriction([matching_turns[1]...], restric.id)
    else
        # filter by turn type
        filter!((fr, to) -> is_turn_type(get_prop(G, fr, to, :turn_angle), rtype), matching_turns)
        if length(matching_turns) == 1
            return TurnRestriction([matching_turns[1]...], restric.id)
        elseif isempty(matching_turns)
            @warn "No turns match restric $(restric.id)"
        else
            buf = IOBuffer()
            print(buf, "Restriction $(restric.id)")

            @warn "Restriction $(restric.id) of type $(rtype) is ambiguous, skipping. \nPossible restrictions\n" *
                join(summarize_restriction.(Ref(G), matching_turns), "\n")
        end
    end
end

function summarize_restriction(G, vertices)
    join(
        map(v -> "way $(get_prop(G, v, :way)) from node $(get_prop(G, v, :from_node)) to node $(get_prop(G, v, :to_node))", vertices),
        " followed by "
    ) * "(turn angle: $(round(bearing_between(get_prop(G, vertices[1], :heading_end), get_prop(G, vertices[end], :heading_start))))°)"
end

"""
Process a complex turn restriction with via way(s)
"""
function process_complex_restriction(restric, G, vertices_for_way)
    # I don't think that the members of a relation are ordered... so the order the
    # via ways occur may or may not match the order they are traversed 🤦. Do a little depth-first search
    # to find all the ways you could hook them up.

    # turns out OSM relations are ordered (https://wiki.openstreetmap.org/wiki/Elements), but let's not
    # rely on them being coded properly. 

    # because the way segments rather than the nodes are what we care about, we use a "dual graph"
    # with nodes representing way segments and way segments representing nodes. See
    # Winter, Stephan. 2002. “Modeling Costs of Turns in Route Planning.” GeoInformatica 6
    # (4): 345–361. doi:10.1023/A:1020853410145.

    # all vertices that represent any part of the involved ways
    vertices_to_explore = Set{Int64}()
    ways = Set{Int64}()
    local origins, destinations

    for member in restric.members
        if !(member.role in Set(["from", "to", "via"]))
            continue  # warning printed above
        end

        if !haskey(vertices_for_way, member.id)
            @warn "processing restriction $(restric.id), way $(member.id) not found in graph"
            return nothing
        end

        push!(ways, member.id)
        push!.(Ref(vertices_to_explore), vertices_for_way[member.id])
        if member.role == "from"
            origins = vertices_for_way[member.id]
        elseif member.role == "to"
            destinations = vertices_for_way[member.id]
        end
    end
    
    # paths that pass through all mentioned ways
    candidate_paths = filter(find_paths(G, origins, destinations, vertices_to_explore)) do path
        # figure out if it traverses all the member ways
        traverses = Set{Int64}()
        for vx in path
            push!(traverses, get_prop(G, vx, :way))
        end

        # make sure it traversed all ways
        return traverses == ways
    end

    rtype = get_rtype(restric)

    # if there's only one candidate path, then it's easy
    if length(candidate_paths) == 1
        turn_angle = bearing_between(
            get_prop(G, candidate_paths[1][1], :heading_end),
            get_prop(G, candidate_paths[1][end], :heading_start),
        )
        if !is_turn_type(turn_angle, rtype)
            @warn "Restric $(restric.id) has type $rtype but has bearing $(turn_angle)"
        end
        return TurnRestriction(candidate_paths[1], restric.id)
    else
        # multiple candidate paths; filter by turn type
        filtered_paths =
            filter(candidate_paths) do path
                turn_angle = bearing_between(
                    get_prop(G, path[1], :heading_end),
                    get_prop(G, path[end], :heading_start),
                )
                is_turn_type(turn_angle, rtype)
            end
        
        if length(filtered_paths) == 1
            return TurnRestriction(candidate_paths[1], restric.id)

        elseif length(filtered_paths) > 1
            @warn "Restriction $(restric.id) of type $(rtype) is ambiguous, skipping. \nPossible restrictions\n" *
                join(summarize_restriction.(Ref(G), filtered_paths), "\n")
            return nothing
        elseif length(filtered_paths) == 0
            @error "No matching restriction for $rtype, for restriction $(restric.id)"
            return nothing
        end
    end
end

function is_turn_type(bearing, type)
    if endswith(type, "left_turn")
        target_ranges = LEFT_TURN_RANGES
    elseif endswith(type, "right_turn")
        target_ranges = RIGHT_TURN_RANGES
    elseif endswith(type, "u_turn")
        target_ranges = U_TURN_RANGES
    elseif endswith(type, "straight_on")
        target_ranges = STRAIGHT_RANGES
    else
        error("Unrecognized turn restriction $type")
    end

    for range in target_ranges
        # ranges will overlap at ends b/c using ≤ and ≥, but that's okay
        if range[1] ≤ bearing && range[2] ≥ bearing
            return true
        end
    end
    return false # not in any target range
end

function apply_turn_restrictions!(G, turn_restrictions)
    # first, apply all simple turn restrictions (no via ways), and
    # accumulate complex turn restrictions for later

    complex_restrictions = Vector{TurnRestriction}()

    # before we go any further, validate that all segments are in the graph
    for restriction in turn_restrictions
        for (fr, to) in zip(restriction.segments[1:end-1], restriction.segments[2:end])
            has_edge(G, fr, to) || error("Restriction $(restriction.osm_id) refers to segments not in graph (internal error)!")
        end
    end

    for restriction in turn_restrictions
        if length(restriction.segments) == 2
            # simple, just remove this edge
            # check to make sure it hasn't already been removed by a duplicate turn restriction
            has_edge(G, restriction.segments...) && rem_edge!(G, restriction.segments...)
        else
            push!(complex_restrictions, restriction)
        end
    end

    # complex restrictions are, well, complex.
    # to represent a a -> b+ -> c restriction,
    # we remove all the middle ways (b) from the graph, and connect up all the
    # allowed movements from a to c and anything else that touched b. i.e.
    # we remove the vertex b, and bypass it where allowed. Where this gets really
    # tricky is if they overlap - i.e. you have a turn restriction that
    # starts or ends inside another one. So what we do is first sort turn restrictions
    # into turn restriction "systems" - sets of overlapping turn restrictions. Then we
    # use a DFS to find all paths from every vertex to every other vertex. Then we remove the ones
    # forbidden by the restriction, and add the others back to the graph.

    # first, sort restrictions into systems
    # system_for_vertex = Dict{Int64, Vector{TurnRestriction}}()
    # for restric in complex_restrictions
    #     system = Vector{TurnRestriction}()
    #     push!(system, restric)
    #     for v in restric.segments
    #         if haskey(system_for_vertex, v)
    #             @info "restriction $(restric.osm_id) is part of a complex restriction"  
    #             ex_system = system_for_vertex[v]
    #             push!.(Ref(system), ex_system)
    #         end
    #         # this might be a merged system or just the one we created above
    #         # it will be modified in-place as we discover more system members
    #     end

    #     system_vertices = Set(collect(Iterators.flatten(map(r -> r.segments, system))))

    #     # now, we need to merge systems which have only a single edge between them, as they will break routing
    #     # otherwise. Consider the following graph:
    #     #        |      |        |       |
    #     #   -----+------a========b-------+--------
    #     #        |No U turn     No U turn|
    #     #   -----+--+--+--+------+-------+--------
    #     #        |  |  |  |      |       |
    #     # at this point in the code, we would have two systems here - one for each U turn.
    #     # between the two systems, we have a single (highlighted) edge from a to b. However,
    #     # in the system on the left, a will be replaced by a set of vertices for each turning
    #     # movement, all connected to b. The same will happen in the right, with b replaced by
    #     # a set of vertices all connected to a. However, since a and b are no longer a part of
    #     # the routable graph (their edges are removed), we can no longer route from a to b.
    #     # in this case, we merge the systems together.
    #     # neighboring_systems = Set{Vector{TurnRestriction}}()
    #     # for r2 in system
    #     #     for v in r2.segments
    #     #         for nbr in neighbors(G, v)
    #     #             if nbr ∉ system_vertices && haskey(system_for_vertex, nbr)
    #     #                 push!(neighboring_systems, system_for_vertex[nbr])  # neighboring_systems is a set, no need to check for dupes
    #     #             end
    #     #         end
    #     #     end
    #     # end

    #     # for nbrsys in neighboring_systems
    #     #     push!.(Ref(system), nbrsys)
    #     # end

    #     # now, the entire (potentially merged) system should be updated with all constituent vertices
    #     for r2 in system
    #         for v in r2.segments
    #             system_for_vertex[v] = system
    #         end
    #     end
    # end
    
    restriction_for_vertex = Dict{Int64, Vector{TurnRestriction}}()
    for restric in complex_restrictions
        for v in restric.segments
            if haskey(restriction_for_vertex, v)
                push!(restriction_for_vertex[v], restric)
            else
                restriction_for_vertex[v] = [restric]
            end
        end
    end

    # now, compile them into systems
    processed_restrictions = Set{TurnRestriction}()
    systems = Vector{Vector{TurnRestriction}}()

    restric_queue = Queue{TurnRestriction}()
    for start in complex_restrictions
        if start ∉ processed_restrictions
            system = Set{TurnRestriction}()

            @assert isempty(restric_queue)
            enqueue!(restric_queue, start)
            while !isempty(restric_queue)
                # pop a restriction off the queue
                restric = dequeue!(restric_queue)
                # add it to the system
                push!(system, restric)
                # and mark it as processed
                push!(processed_restrictions, restric)

                for v in restric.segments
                    # should always be in restriction_for_vertex
                    for r2 in restriction_for_vertex[v]
                        if r2 ∉ system && r2 ∉ restric_queue
                            # this is a connected turn restriction not yet in the system
                            enqueue!(restric_queue, r2)
                        end
                    end

                    # also check neighbors.
                    # Consider the following graph:
                    #        |      |        |       |
                    #   -----+------a========b-------+--------
                    #        |No U turn     No U turn|
                    #   -----+--+--+--+------+-------+--------
                    #        |  |  |  |      |       |
                    # at this point in the code, we would have two systems here - one for each U turn.
                    # between the two systems, we have a single (highlighted) edge from a to b. However,
                    # in the system on the left, a will be replaced by a set of vertices for each turning
                    # movement, all connected to b. The same will happen in the right, with b replaced by
                    # a set of vertices all connected to a. However, since a and b are no longer a part of
                    # the routable graph (their edges are removed), we can no longer route from a to b.
                    # in this case, we merge the systems together.
                    for nbr in all_neighbors(G, v)
                        # neighbors might not be in restrictions_for_vertex
                        if haskey(restriction_for_vertex, nbr)
                            for r2 in restriction_for_vertex[nbr]
                                if r2 ∉ system && r2 ∉ restric_queue
                                    enqueue!(restric_queue, r2)
                                end
                            end
                        end
                    end
                end
            end

            push!(systems, collect(system))
        end
    end

    @info "$(length(complex_restrictions)) complex restrictions become $(length(systems)) turn restriction systems"

    # now, apply the restriction
    # to do this, we find all possible paths through the system, then remove all the edges in the system and
    # add edges for each of the allowed turns. We don't remove any vertices to avoid changing vertex indices.
    # since weighting happens later, and we want to  properly account for turn costs, we don't add a single edge to
    # represent the complex turn, but rather the same number of edges as we started with. We add vertices between these
    # that are duplicates of the original vertices, but only connected as part of a single turn. We mark them
    # as being part of a complex turn, so they can be visualized without all being on top of each other in the visualizer.

    complex_restriction_idx = 1

    for (system_idx, system) in enumerate(systems)
        # first, find all paths in the system
        # we need to find _all_ paths, even if they start in the middle of the system. We will reconnect to external
        # vertices not in the system when we reconstruct this part of the graph.
        restricted_paths = collect(map(x -> x.segments, system))
        system_vertices = Set{Int64}(Iterators.flatten(restricted_paths))

        # find all vertices that are entrances or exits to the system - i.e. are just outside
        access_vertices = Set(Iterators.flatten(map(v -> filter(n -> n ∉ system_vertices, inneighbors(G, v)), collect(system_vertices))))
        egress_vertices = Set(Iterators.flatten(map(v -> filter(n -> n ∉ system_vertices, outneighbors(G, v)), collect(system_vertices))))

        for v1 in access_vertices
            for v2 in egress_vertices
                # figure out if there are non-restricted paths between these vertices through the system
                # TODO should we find only a single shortest path? Could become problematic
                # in assignment if the shortest path changes
                paths = find_paths(G, [v1], [v2], Set([system_vertices..., v1, v2]))

                # remove restricted paths
                filter!(paths) do p
                    if all(p .∉ Ref(system_vertices))
                        return false # these vertices are directly connected without passing through system
                    end

                    for r in restricted_paths
                        for offset in 1:(length(p) - length(r) + 1)
                            if (@view p[offset:(offset + length(r) - 1)]) == r
                                return false
                            end
                        end
                    end
                    return true
                end

                # add paths
                for path in paths
                    # first and last element of path stay in graph
                    new_vertices = [
                        path[1],
                        map(path[2:end - 1]) do v
                            add_vertex!(G, copy(props(G, v)))
                            vn = nv(G)
                            set_prop!(G, vn, :complex_restriction_idx, complex_restriction_idx)
                            set_prop!(G, vn, :system_idx, system_idx)
                            vn
                        end...,
                        path[end]
                    ]

                    # add the edges
                    for (i1, i2) in zip(1:(length(path) - 1), 2:length(path))
                        @assert add_edge!(G, new_vertices[i1], new_vertices[i2], copy(props(G, path[i1], path[i2])))
                    end

                    complex_restriction_idx += 1
                end
            end
        end

        # all_paths = find_all_paths(G, system_vertices)
        # n_paths = length(all_paths)
        # filter!(all_paths) do p
        #     for r in restricted_paths
        #         for offset in 1:(length(p) - length(r) + 1)
        #             if (@view p[offset:(offset + length(r) - 1)]) == r
        #                 return false
        #             end
        #         end
        #     end

        #     # only add the path if the ends are connected to something external to the system
        #     for nbr in Iterators.flatten([inneighbors(G, p[1]), outneighbors(G, p[end])])
        #         if nbr ∉ system_vertices
        #             # this vertex is an interface point to the outside world
        #             # need to keep this path
        #             return true
        #         end
        #     end

        #     return false
        # end


        # for path in all_paths
        #     # create the edges
        #     prev_v = nothing
        #     prev_newv = nothing
        #     for v in path
        #         add_vertex!(G, copy(props(G, v)))
        #         newv = nv(G)
        #         set_prop!(G, newv, :complex_restriction_idx, complex_restriction_idx)
        #         set_prop!(G, newv, :system_idx, system_idx)

        #         # connect vertex to any external to system neighbors
        #         for nbr in inneighbors(G, v)
        #             if nbr ∉ system_vertices
        #                 add_edge!(G, nbr, newv, copy(props(G, nbr, v)))
        #             end
        #         end

        #         for nbr in outneighbors(G, v)
        #             if nbr ∉ system_vertices
        #                 add_edge!(G, newv, nbr, copy(props(G, v, nbr)))
        #             end
        #         end

        #         # add edges between vertices on this turn
        #         if !isnothing(prev_v)
        #             add_edge!(G, prev_newv, newv, copy(props(G, prev_v, v)))
        #         end

        #         prev_v = v
        #         prev_newv = newv
        #     end
        #     complex_restriction_idx += 1
        # end

        # remove all edges from original system vertices
        for v in system_vertices
            for nbr in inneighbors(G, v)
                @assert rem_edge!(G, nbr, v)
            end

            for nbr in outneighbors(G, v)
                @assert rem_edge!(G, v, nbr)
            end
        end
    end
end
