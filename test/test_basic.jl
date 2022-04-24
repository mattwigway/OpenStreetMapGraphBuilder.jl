
@testset "Basic routing" begin
    # NB Joshua Tree Highway just north of Cactus to the freeway
    path = [
        101934, # JT Highway
        # skip forbidden lane, should not be in graph
        101956, # JT Hwy @ Beavertail
        101955, # @ Tropical Island - still in graph b/c removed by island removal
        102040, # @ Wash Trl
        101954, # Ramp
        101969, # Ramp
        101825, # Merge to EB Garden Fwy
        101826 # Garden Fwy exit to Wash Trl
    ]

    @test get_path(G, 101934, 101826) == path
end

@testset "Way filter" begin
    # No access way should not be in graph
    @test isempty(filter(v -> get_prop(G, v, :way) == 291280, 1:nv(G)))
    # nodes from no access way should not have split roads
    @test isempty(filter(v -> get_prop(G, v, :from_node) == 102193, 1:nv(G)))
end

function get_neighbors(node)
    vertices = vertices_for_node(G, node)
    return Set(map(x -> get_prop(G, x, :from_node), Iterators.flatten(map(v -> outneighbors(G, v), vertices))))
end

@testset "Neighbors" begin
    # it's a beautiful day in this neighborhood, a beautiful day for a neighbor
    @test get_neighbors(101936) == # SB JT Hwy @ Beavertail
        Set([
            101956, # NB JT Hwy @ Beavertail
            101907, # Beavertail @ Saguaro
            7101949  # JT Hwy @ Rattlesnake
        ])

    # One-way streets should not have previous nodes as neighbors
    @test 101956 ∉ get_neighbors(101955) # NB JT Hwy @ Beavertail should not be neighbor of NB JT Hwy @ Tropical Island
    @test 101955 ∈ get_neighbors(101956) # But the opposite should be true
    
    # should be true for implied one way also
    @test 101825 ∉ get_neighbors(101826) # EB entrance ramp from JT Hwy should not be neighbor of exit ramp to Wash Trl
    @test 101826 ∈ get_neighbors(101825)

    @test 101811 ∉ get_neighbors(101798) # EB Garden Fwy should not be neighbor of Saguaro @ circle
    @test 101798 ∈ get_neighbors(101811)

    @test 101969 ∉ get_neighbors(101825) # EB Garden Fwy onramp from JT Hwy
    @test 101825 ∈ get_neighbors(101969) # EB Garden Fwy onramp from JT Hwy

    # but if implied one way is specifically mapped as two-way, then it should not be one way
    # two way access ramp to Garden Fwy from Wash Trl
    @test 2101778 ∈ get_neighbors(102045)
    @test 102045 ∈ get_neighbors(2101778)

    # Reversed one way should be handled correctly (rest area ramp from EB Garden Fwy)
    @test 102017 ∉ get_neighbors(102028)
    @test 102028 ∈ get_neighbors(102017)
end

@testset "Correct topology" for v in 1:nv(G)
    from_node = get_prop(G, v, :from_node)
    to_node = get_prop(G, v, :to_node)
    nodes = get_prop(G, v, :nodes)
    @test nodes[1] == from_node
    @test nodes[end] == to_node
    for nbr in outneighbors(G, v)
        @test get_prop(G, nbr, :from_node) == to_node
    end
end