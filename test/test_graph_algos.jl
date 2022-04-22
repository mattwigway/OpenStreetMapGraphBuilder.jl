@testset "Graph algorithms" begin
    exg = MetaDiGraph()
    # add some vertices - making an H shaped graph; to test subgraph filtering
    # we do not include vertex 7 (this function is used in turn restriction finding
    # to find paths through a subnetwork, so we can select which vertices to consider)
    #   1     2
    #   |     |
    #   3-----4
    #   |     |
    #   5--7--6

    for _ in 1:7
        add_vertex!(exg)
    end

    add_edge!(exg, 1, 3)
    add_edge!(exg, 3, 1)
    add_edge!(exg, 2, 4)
    add_edge!(exg, 4, 2)
    add_edge!(exg, 3, 4)
    add_edge!(exg, 4, 3)
    add_edge!(exg, 3, 5)
    add_edge!(exg, 5, 3)
    add_edge!(exg, 4, 6)
    add_edge!(exg, 6, 4)
    add_edge!(exg, 5, 7)
    add_edge!(exg, 7, 5)
    add_edge!(exg, 7, 6)
    add_edge!(exg, 6, 7)

    # there should be exactly one acyclic path from 5 to 3 since 7 is not in the part of the
    # graph we search
    @test StreetRouter.OSM.find_paths(exg, Set([5]), Set([6]), Set(1:6)) == [
        [5, 3, 4, 6]
    ]

    # There should be four acyclic paths from (1, 2) to (5, 6)
    @test Set(StreetRouter.OSM.find_paths(exg, Set([1, 2]), Set([5, 6]), Set(1:6))) == Set([
        [1, 3, 5],
        [1, 3, 4, 6],
        [2, 4, 6],
        [2, 4, 3, 5]
    ])

end