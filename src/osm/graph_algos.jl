
struct PathState
    back::Union{PathState, Nothing}
    at_vertex::Int64
end

"find all the paths between all vertices in a subgraph"
# need to flatten twice b/c two levels of iteration over vertices
find_all_paths(G, vertices) = collect(Iterators.flatten([
    Iterators.flatten(Iterators.flatten([find_paths(G, [v1], [v2], vertices) for v2 in vertices if v2 != v1] for v1 in vertices)),
    [[v] for v in vertices]])
)

"return all acyclic paths from origin nodes to destination nodes"
function find_paths(g, origins, destinations, vertices)
    q = Queue{PathState}()
    states_at_dest = Vector{PathState}()

    # enqueue all origins
    for origin in origins
        enqueue!(q, PathState(nothing, origin))
    end

    # while there is anything on the queue, pop it off and explore from it
    # like dijkstra but without pqueue or vertex labels
    while length(q) > 0
        from_state = dequeue!(q)

        prev_vertices = Set{Int64}()
        back_state = from_state  # not from_state.back so we get current vertex in prev_vertices
        while !isnothing(back_state)
            push!(prev_vertices, back_state.at_vertex)
            back_state = back_state.back
        end

        for vertex in Graphs.outneighbors(g, from_state.at_vertex)
            # don't loop, and only traverse a single origin edge (i.e. don't traverse all parts of an origin way) 
            if (vertex ∈ vertices) && !(vertex in prev_vertices) && !(vertex in origins)
                next_state = PathState(from_state, vertex)
                if vertex in destinations
                    # we found a path
                    push!(states_at_dest, next_state)
                else
                    # not there yet
                    enqueue!(q, next_state)
                end
            end
        end
    end

    # convert states to something more useful by back-traversing
    paths = Vector{Vector{Int64}}()
    sizehint!(paths, length(states_at_dest))
    for state in states_at_dest
        path = Vector{Int64}()
        back_state = state
        while !isnothing(back_state)
            push!(path, back_state.at_vertex)
            back_state = back_state.back
        end
        reverse!(path)
        push!(paths, path)
    end

    return paths
end