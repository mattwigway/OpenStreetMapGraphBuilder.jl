using ParserCombinator, Graphs, GraphIO, OpenStreetMapGraphBuilder, Serialization

function main(args)
    G = OpenStreetMapGraphBuilder.OSM.build_graph(args[1])
    OpenStreetMapGraphBuilder.compute_freeflow_weights!(G)
    serialize(args[2], G)
    OpenStreetMapGraphBuilder.to_gml(G, args[3])
end

main(ARGS)