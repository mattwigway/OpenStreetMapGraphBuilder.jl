using ParserCombinator, Graphs, GraphIO, GraphIO.GML, StreetRouter

function main()
    G = StreetRouter.OSM.build_graph(ARGS[1])
    open(ARGS[2], "w") do str
        savegraph(str, G, "graph", GraphIO.GML.GMLFormat())
    end
end

main()