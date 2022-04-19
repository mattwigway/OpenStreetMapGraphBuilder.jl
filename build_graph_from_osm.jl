using ParserCombinator, Graphs, GraphIO, StreetRouter, Serialization

function main(args)
    G = StreetRouter.OSM.build_graph(args[1])
    serialize(args[2], G)
end

main(["/Users/mwbc/Downloads/district-of-columbia-latest.osm.pbf", "dc.srgr"])