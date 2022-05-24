using Test, OpenStreetMapGraphBuilder, Graphs, MetaGraphs, Geodesy

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

# get the edge connecting the way segment defined by from and via to the one defined by via and to (all OSM node ids)
function get_edge(G, from, via, to)
    for frv in vertices_for_node(G, (from, via))
        for tov in vertices_for_node(G, (via, to))
            if has_edge(G, frv, tov)
                return (frv, tov)
            end
        end
    end
end

const G = OpenStreetMapGraphBuilder.OSM.build_graph(Base.joinpath(Base.source_dir(), "traffic_garden.osm.pbf"))
OpenStreetMapGraphBuilder.compute_freeflow_weights!(G)

# a graph with turn restrictions ignored
const N = OpenStreetMapGraphBuilder.OSM.build_graph(Base.joinpath(Base.source_dir(), "traffic_garden.osm.pbf"), turn_restrictions=false)
OpenStreetMapGraphBuilder.compute_freeflow_weights!(N)

include("test_gml.jl")
include("test_weights.jl")
include("test_graph_algos.jl")
include("test_heading.jl")
include("test_basic.jl")
include("test_restric.jl")