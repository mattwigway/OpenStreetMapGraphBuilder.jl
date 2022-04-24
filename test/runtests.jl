using Test, StreetRouter, Graphs, MetaGraphs, Geodesy

vertices_for_node(G, node::Int64) = filter(v -> get_prop(G, v, :from_node) == node, 1:nv(G))
# allow passing (fr, to) tuple to get a specific direction of a specific node
vertices_for_node(G, node::Tuple{Int64, Int64}) = filter(v -> get_prop(G, v, :from_node) == node[1] && get_prop(G, v, :to_node) == node[2], 1:nv(G))

function get_path(G, fr_node, to_node)
    # find vertices for nodes
    sources = vertices_for_node(G, fr_node)

    paths = dijkstra_shortest_paths(G, sources)

    # find the shortest path to any destination node
    dests = vertices_for_node(G, to_node)
    dest = dests[argmin(paths.dists[dests])]

    # back-walk the path
    current_vertex = dest
    path = Vector{Int64}()
    push!(path,  get_prop(G, current_vertex, :from_node))
    while current_vertex ∉ sources
        current_vertex = paths.parents[current_vertex]
        if current_vertex == 0
            error("Vertex has no parent. Path so far: $(reverse(path)). Dists: $(paths.dists[dests])")
        end
        push!(path, get_prop(G, current_vertex, :from_node))
    end

    reverse!(path)
    path
end

const G = StreetRouter.OSM.build_graph(Base.joinpath(Base.source_dir(), "traffic_garden.osm.pbf"))
StreetRouter.compute_freeflow_weights!(G)

# a graph with turn restrictions ignored
const N = StreetRouter.OSM.build_graph(Base.joinpath(Base.source_dir(), "traffic_garden.osm.pbf"), turn_restrictions=false)
StreetRouter.compute_freeflow_weights!(N)

include("test_graph_algos.jl")
include("test_heading.jl")
include("test_basic.jl")
include("test_restric.jl")