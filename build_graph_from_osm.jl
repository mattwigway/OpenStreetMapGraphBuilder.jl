using ParserCombinator, Graphs, GraphIO, StreetRouter, Serialization

function main(args)
    G = StreetRouter.OSM.build_graph(args[1])
    StreetRouter.compute_freeflow_weights!(G)
    serialize(args[2], G)
    StreetRouter.to_gml(G, args[3])
end

main(ARGS)