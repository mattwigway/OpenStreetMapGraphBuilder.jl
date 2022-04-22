function default_way_filter(way::Way)::Bool
    if !haskey(way.tags, "highway") || !haskey(DEFAULT_FREEFLOW_SPEEDS, way.tags["highway"])
        return false  # footway etc
    end

    if haskey(way.tags, "area") && way.tags["area"] == "yes"
        return false  # driveable area, often coincident with other roads
    end
    
    driveable = true
    for tag in ("motor_vehicle", "motorcar", "access")
        if haskey(way.tags, tag) && way.tags[tag] ∈ NON_DRIVABLE_ACCESS
            driveable = false
        end
    end

    return driveable
end

function build_graph(osmpbf; way_filter=default_way_filter, save_names=true, remove_islands=100)
    # find all nodes that occur in more than one way
    node_count = counter(Int64)

    @info "Pass 1: find intersection nodes"
    n_ways = 0
    scan_ways(osmpbf) do w
        if way_filter(w)
            n_ways += 1
            for node in w.nodes
                inc!(node_count, node)
            end
        end
    end

    @info "..parsed $n_ways ways"

    # now retain all intersection nodes
    intersection_nodes = Set{Int64}()
    # just a guess but preallocate a bunch of space
    sizehint!(intersection_nodes, n_ways * 3)
    for (nidx, n_refs) in node_count
        if n_refs >= 2
            push!(intersection_nodes, nidx)
        end
    end

    @info "..found $(length(intersection_nodes)) intersection nodes"

    @info "Pass 2: read intersection and other highway nodes"
    node_geom = Dict{Int64, LLA}()
    traffic_signal_nodes = Set{Int64}()
    scan_nodes(osmpbf) do n
        if haskey(node_count, n.id)
            # lat lon, not lon lat, and we're not using altitude
            node_geom[n.id] = LLA(n.lat, n.lon, 0)

            if haskey(n.tags, "highway") && n.tags["highway"] == "traffic_signals"
                push!(traffic_signal_nodes, n.id)
                # also treat any node with a traffic signal as an intersection
                push!(intersection_nodes, n.id)
            end
        end
    end

    # save memory
    # TODO will this create type instability?
    node_count = nothing

    @info "Pass 3: re-read and catalog ways"
    way_segments = Vector{WaySegment}()
    way_segments_by_start_node = DefaultDict{Int64, Vector{Int64}}(Vector{Int64})
    way_segments_by_end_node = DefaultDict{Int64, Vector{Int64}}(Vector{Int64})

    sizehint!(way_segments, n_ways * 2)

    if save_names
        way_segment_names = Vector{String}()
        sizehint!(way_segment_names, n_ways * 2)
    end

    geoms = Vector{Vector{LatLon}}()

    scan_ways(osmpbf) do w
        if way_filter(w)
            seg_length::Float64 = 0
            origin_node::Int64 = w.nodes[1]
            heading_start::Float32 = NaN32
            heading_end::Float32 = NaN32
            traffic_signal::Int32 = 0
            back_traffic_signal::Int32 = 0

            # figure out one-way
            oneway = false
            if haskey(w.tags, "oneway")
                owt = w.tags["oneway"]
                if (owt == "yes" || owt == "1" || owt == "true")
                    oneway = true
                elseif (owt == "-1" || owt == "reverse")
                    oneway = true
                    # don't try to have a separate codepath for reversed, just reverse the nodes
                    # it's okay to be destructive, we aren't using this way object again
                    # this might not be the most efficient but reverse oneways are rare
                    # NB this will be an issue if we ever support multimodal routing in one graph
                    # as some ways are oneway for cars but two-way for bikes etc.
                    reverse!(w.nodes)
                end
            end
 
            # implied one way
            if (
                    w.tags["highway"] ∈ Set(["motorway", "motorway_link"]) ||
                    haskey(w.tags, "junction") && w.tags["junction"] ∈ Set(["roundabout", "rotary", "traffic_circle"])
            ) && !(haskey(w.tags, "oneway") && w.tags["oneway"] == "no")
                oneway = true
            end

            if haskey(w.tags, "name")
                name = w.tags["name"]
            else
                hwy = w.tags["highway"]
                name = "unnamed $(hwy)"
            end

            # store number of lanes, if present
            lanes_per_direction::Union{Int64, Missing} = missing
            if haskey(w.tags, "lanes")
                try
                    lanes_per_direction = parse(Int64, w.tags["lanes"])
                    if !oneway
                        lanes_per_direction ÷= 2
                    end
                catch
                    lanes_str = w.tags["lanes"]
                    @warn "could not parse lanes values $lanes_str"
                    lanes_per_direction = missing
                end
            end

            # store max speed, if present
            maxspeed::Union{Float64, Missing} = missing
            if haskey(w.tags, "maxspeed")
                maxspeed = parse_max_speed(w.tags["maxspeed"])
            end

            accumulated_nodes = Vector{Int64}()
            push!(accumulated_nodes, w.nodes[1]) # initialize with first node

            for idx in 2:length(w.nodes)
                this_node = w.nodes[idx]
                this_node_geom = node_geom[this_node]
                prev_node = w.nodes[idx - 1]
                prev_node_geom = node_geom[prev_node]

                push!(accumulated_nodes, this_node)

                if in(this_node, traffic_signal_nodes)
                    traffic_signal += 1
                end

                # gotta keep track of it the other way as well, b/c the traffic signals are on different nodes going the other way
                if in(prev_node, traffic_signal_nodes)
                    back_traffic_signal += 1
                end

                seg_length += euclidean_distance(prev_node_geom, this_node_geom)

                if idx == 2
                    # special case at start of way: compute heading
                    heading_start = compute_heading(prev_node_geom, this_node_geom)
                end

                if (idx == length(w.nodes) || in(this_node, intersection_nodes))
                    # save this way segment and start a new one
                    heading_end = compute_heading(prev_node_geom, this_node_geom)
                    # TODO figure out one-way
                    ws = WaySegment(
                        origin_node,
                        this_node,
                        w.id,
                        heading_start,
                        heading_end,
                        convert(Float32, seg_length),
                        oneway,
                        traffic_signal,
                        back_traffic_signal,
                        lanes_per_direction,
                        ismissing(maxspeed) ? default_speed_for_way(w) : maxspeed,
                        accumulated_nodes,
                        get_road_class(w.tags["highway"])
                    )
                    push!(way_segments, ws)

                    # index it by node
                    wsidx = length(way_segments)
                    push!(way_segments_by_start_node[origin_node], wsidx)
                    push!(way_segments_by_end_node[this_node], wsidx)

                    if save_names
                        # note that there will be many adjacent identical values, which doesn't matter b/c the
                        # names file gets gzipped
                        push!(way_segment_names, name)
                    end

                    # prepare for next iteration
                    if idx < length(w.nodes)
                        origin_node = this_node
                        heading_start = compute_heading(this_node_geom, node_geom[w.nodes[idx + 1]])
                        seg_length = 0
                        traffic_signal = 0
                        back_traffic_signal = 0
                        accumulated_nodes = Vector{Int64}()
                        push!(accumulated_nodes, this_node)
                    end
                end
            end
        end
    end
    
    @info "expanding bidirectional edges to unidirectional edges"
    new_way_segments = Vector{WaySegment}()
    sizehint!(new_way_segments, length(way_segments))

    if save_names
        new_way_segment_names = Vector{String}()
        sizehint!(new_way_segment_names, length(way_segments))
    end

    for (i, ws) in enumerate(way_segments)
        push!(new_way_segments, ws)
        if save_names
            name = way_segment_names[i]
            push!(new_way_segment_names, name)
        end

        if !ws.oneway
            # two-way street, add a back edge
            back = WaySegment(
                ws.destination_node,
                ws.origin_node,
                ws.way_id,
                circular_add(ws.heading_end, 180),
                circular_add(ws.heading_start, 180),
                ws.length_m,
                ws.oneway,
                ws.back_traffic_signal,
                ws.traffic_signal,
                ws.lanes,
                ws.speed_kmh,
                reverse(ws.nodes),
                ws.class
            )

            push!(new_way_segments, back)
            if save_names
                push!(new_way_segment_names, name)
            end
        end
    end

    way_segments = new_way_segments
    way_segment_names = new_way_segment_names

    @info "non-edge-based graph has $(length(way_segments)) edges"

    if save_names
        @assert length(way_segments) == length(way_segment_names) "way segments and names do not have same length!"
    end

    @info "reindexing segments for edge-based graph construction"
    way_segments_by_end_node = nothing  # should not be used anymore
    empty!(way_segments_by_start_node)
    for (wsidx, ws) in enumerate(way_segments)
        push!(way_segments_by_start_node[ws.origin_node], wsidx)
    end

    @info "creating edge-based graph"
    # confusing, but this is an edge-based graph - one vertex per _way segment_, and the numbers
    # are parallel to the vector way_segments
    G = MetaDiGraph(length(way_segments))

    for (srcidx, way_segment) in enumerate(way_segments)
        # set the location of this way segment vertex to be the start of the way - used for snapping
        # in snapping, we will still be able to snap to the end of a cul-de-sac because of the back edge,
        # unless it is a one-way cul-de-sac... cf. https://github.com/conveyal/r5/blob/dev/src/main/java/com/conveyal/r5/streets/TarjanIslandPruner.java
        set_prop!(G, srcidx, :geom, collect(map(nid -> node_geom[nid], way_segment.nodes)))
        set_prop!(G, srcidx, :from_node, way_segment.nodes[1])
        set_prop!(G, srcidx, :to_node, way_segment.nodes[end])
        set_prop!(G, srcidx, :way, way_segment.way_id)
        set_prop!(G, srcidx, :heading_start, way_segment.heading_start)
        set_prop!(G, srcidx, :heading_end, way_segment.heading_end)

        # find all of the way segments this way segment is connected to
        connected_segments = way_segments_by_start_node[way_segment.destination_node]
        for tgtidx in connected_segments
            # figure out if this is a straight-on or turn action
            tgtseg = way_segments[tgtidx]

            # handle implied no u turn in certain places
            # can't just look at start and end nodes - imagine a loop street with two segmetns that looks like this:
            #    ______________________
            #   /                      \
            #  +                        +
            #   \______________________/
            # That's not a U turn, but would look like one if we weren't careful.
            if tgtseg.way_id == way_segment.way_id && tgtseg.nodes == reverse(way_segment.nodes)
                # this is a u turn
                # get the other segments in this location
                other_segments = filter(x -> x!=tgtidx, connected_segments)
                if length(other_segments) == 1
                    # only one other segment, this is a node in the middle of a road, not at an intersection
                    # do allow u turns if there are 0 other segments, i.e. at the ends of cul-de-sacs
                    continue
                end
            end

            Δhdg = bearing_between(way_segment.heading_end, tgtseg.heading_start)

            # Δhdg should now be the angle from the entry heading to the exit heading
            # if |Δhdg| < 45, we call it straight-on
            # if Δhdg > 45, right turn
            # if Δhdg < 45, left turn
            # if Δhdg > 45
            #     turn_dir = right
            # elseif Δhdg < -45
            #     turn_dir = left
            # else
            #     turn_dir = straight
            # end

            # error if adding edge fails
            @assert add_edge!(G, srcidx, tgtidx)
            
            # set the edge metadata
            set_prop!(G, srcidx, tgtidx, :length_m, way_segment.length_m)
            set_prop!(G, srcidx, tgtidx, :turn_angle, Δhdg)
            set_prop!(G, srcidx, tgtidx, :traffic_signal, way_segment.traffic_signal)
            set_prop!(G, srcidx, tgtidx, :speed_kmh, way_segment.speed_kmh)
            set_prop!(G, srcidx, tgtidx, :lanes, way_segment.lanes)
            set_prop!(G, srcidx, tgtidx, :oneway, way_segment.oneway)
            set_prop!(G, srcidx, tgtidx, :this_class, way_segment.class)
            set_prop!(G, srcidx, tgtidx, :next_class, tgtseg.class)
        end
    end

    process_turn_restrictions(osmpbf, G)
    if remove_islands > 0
        remove_islands_smaller_than(G, remove_islands)
    end

    return G
end