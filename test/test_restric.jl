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

@testset "Complex restrictions" begin
    @testset "No U turn with via way" begin
        @test get_path(G, 102038, 102040) == [
            102038, # SB JT Hwy @ Wash Trl
            101936, # SB JT Hwy @ Beavertail (no U turn)
            101956, # NB JT Hwy @ Beavertail (no U turn)
            102095, # Beavertail @ Succulent
            101956, # NB JT Hwy @ Beavertail (now making right turn)
            101955, # NB JT Hwy @ Tropical Island
            102040  # NB JT Hwy @ Wash Trl
        ]
    end

    @testset "No U turn with multiple via ways" begin
        # confirm a U turn can't cut through the rest area
        # TODO would the weights make it such that cutting through the rest area would
        # even be a good option?
        @test get_path(G, 101844, 101977) == [
            101844, # WB Garden Fwy at JT Hwy offramp
            101847, # onramp
            102012, # exit to rest area
            101849, # entrance from rest area
            101811, # roundabout
            101798, # roundabout -> Saguaro
            101818, # roundabout -> Garden Fwy WB
            102017, # rest area entrance
            102023, # rest area exit
            101977  # JT Hwy offramp
        ]
    end

    @testset "No left after right" begin
        @test get_path(G, 101945, 102013) == [
            101945, # JT Hwy diverging diamond
            101942, # Entrance ramp
            101994, # Merge with other ramp
            101847, # Merge to highway
            102012, # exit to rest area, but can't exit here due to restriction
            101849, # entrance from rest area
            101811, # roundabout
            101798, # roundabout -> Saguaro
            101818, # roundabout -> Garden Fwy WB
            102017, # rest area entrance
            102028, # in rest area
            102024, # in rest area
            102013, # in rest area
        ]
    end

    @testset "No left after right not applied to partial turn" begin
        # make sure we can still exit to that rest are if we didn't just enter
        @test get_path(G, 101844, 102013) == [
            101844, # WB Garden Fwy at JT Hwy offramp
            101847, # onramp
            102012, # exit to rest area
            102013  # in rest area
        ]
    end

    @testset "Only right turn with via way" begin
        # it's unclear how these should be applied, and they're actually disallowed in the OSM turn restriction
        # specification, but my interpretation is that once you've entered the portion of the way that
        # connects to the via way(s), you must follow the restriction - see more in-depth discussion in
        # only_turn.jl comments.

        # should not be allowed to leave restriction after from way
        @test get_path(G, (101919, 101916), (101916, 101917)) == [
            101919, # exiting NB Garden Pkwy to Beavertail
            101916, # ramps cross in middle of intersection, but only turn
            101903, # cross SB Garden Pkwy
            101906, # end of ramp - U turn to entrance
            101910, # ramps split
            101915, # Cross SB Garden Pkwy
            101916 # ramps cross
        ]

        # should not be allowed to leave restriction after via way
        @test get_path(G, (101919, 101916), (101903, 101915)) == [
            101919, # exiting NB Garden Pkwy to Beavertail
            101916, # ramps cross in middle of intersection, but only turn
            101903, # cross SB Garden Pkwy
            101906, # end of ramp
            102104, # Beavertail @ prickly pear
            102095, # Beavertail @ Succulent
            102177, # Succulent at Tropical Island
            102042, # Succulent @ Wash Trl
            102044, # Wash Trl @ Traffic Light
            102045, # Wash Trl @ Garden Fwy ramp
            101872, # Wash Trl @ SB Garden Pkwy
            101903 # Garden Pkwy at Beavertail WB
        ]

    end
end
