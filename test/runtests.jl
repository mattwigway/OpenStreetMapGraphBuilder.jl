using Test, StreetRouter, Graphs, MetaGraphs

get_graph() = StreetRouter.OSM.build_graph(Base.joinpath(Base.source_dir(), "traffic_garden.osm.pbf"))

vertices_for_node(G, node) = filter(v -> get_prop(G, v, :from_node) == node, 1:nv(G))

function get_path(G, fr_node, to_node)
    # find vertices for nodes
    sources = vertices_for_node(G, fr_node)
    # Only single destination, so we have a single shortest path
    # this is generally fine, unless there is a turn restriction to the dest,
    # we just avoid that in tests
    dest = vertices_for_node(G, to_node)[1]

    paths = dijkstra_shortest_paths(G, sources)

    # back-walk the path
    current_vertex = dest
    path = Vector{Int64}()
    push!(path,  get_prop(G, current_vertex, :from_node))
    while current_vertex ∉ sources
        current_vertex = paths.parents[current_vertex]
        push!(path, get_prop(G, current_vertex, :from_node))
    end

    reverse!(path)
    path
end

const G = get_graph()

include("test_basic.jl")
include("test_restric.jl")