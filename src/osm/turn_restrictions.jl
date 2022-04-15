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
end
