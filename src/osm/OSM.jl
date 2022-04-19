module OSM
using OpenStreetMapPBF, Graphs, MetaGraphs, DataStructures, Logging, Geodesy, ProgressMeter, DataStructures, Infiltrator

include("speeds.jl")
include("osm_types.jl")
include("compute_heading.jl")
include("graph_algos.jl")
include("turn_restrictions.jl")
include("build_graph.jl")

end