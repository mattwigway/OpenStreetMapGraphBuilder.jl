module StreetRouter

using Graphs, MetaGraphs, DataStructures

include("osm/OSM.jl")
include("weights.jl")
include("to_gml.jl")
end