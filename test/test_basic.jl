
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
        101834 # Garden Fwy downgrade
    ]

    @test get_path(G, 101934, 101834) == path
end

@testset "Way filter" begin
    # No access way should not be in graph
    @test isempty(filter(v -> get_prop(G, v, :way) == 291280, 1:nv(G)))
    # nodes from no access way should not have split roads
    @test isempty(filter(v -> get_prop(G, v, :from_node) == 102193, 1:nv(G)))
end