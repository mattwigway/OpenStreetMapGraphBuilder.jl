module OSM
using OpenStreetMapPBF, Graphs, MetaGraphs, DataStructures, Logging, Geodesy

include("speeds.jl")
include("osm_types.jl")
include("compute_heading.jl")
include("build_graph.jl")

end