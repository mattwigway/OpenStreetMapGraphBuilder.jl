@testset "Implied restrictions" begin
    # Make sure the implied no U turn is applied at the traffic light on Wash Trl
    fr_v = findfirst(v -> get_prop(G, v, :from_node) == 102042 && get_prop(G, v, :to_node) == 102044, 1:nv(G))
    to_v = findfirst(v -> get_prop(G, v, :from_node) == 102044 && get_prop(G, v, :to_node) == 102042, 1:nv(G))

    paths = dijkstra_shortest_paths(G, fr_v)

    @test paths.parents[to_v] != fr_v

    # make sure it is not applied in other places - U turn at Succulent Way is legal
    paths = dijkstra_shortest_paths(G, to_v)
    @test paths.parents[fr_v] == to_v
end

@testset "Simple restrictions" begin
    # no left turn from Beavertail to Prickly Pear, need to go around the long way
    # also checks that right turn is allowed in other direction.
    @testset "No left turn" begin
        path = [
            101906, # Beavertail split before Garden Pkwy
            102104, # Beavertail and Prickly Pear - no left turn
            102095, # Beavertail and Succulent - can U turn here
            102104, # Back at Beavertail and Prickly Pear, can turn right
            3101764, # Turn onto service road
            3101765  # Circle on service road
        ]
        @test get_path(G, (101906, 102104), 3101765) == path
    end

    @testset "No right turn did not get applied to opposing left turn (ambiguous without turn angles)" begin
        # confirm no-left-turn did not get applied to the rirght turn
        @test get_path(G, 101956, 3101765) == [
            101956, # JT Hwy @ Beavertail
            102095,  # Beavertail @ Succulent
            102104, # Beavertail @ prickly pear
            3101764,  # Prickly pear @ service
            3101765]
    end

    @testset "Only right turn works" begin
        @test get_path(G, 102177, 102097) == [
            102177, # Succulent at Tropical Island (should remain in graph, island removal does not remove vertices)
            102095, # Succulent @ Beavertail - only right turn (can't go straight)
            101956, # Beavertail @ JT Hwy, U turn # TODO should U-turn here be disallowed since it's against the direction of traffic on the crossing street?
            102095, # Beavertail @ Succulent
            102097  # Succulent at Prickly Pear
        ]

    end
end