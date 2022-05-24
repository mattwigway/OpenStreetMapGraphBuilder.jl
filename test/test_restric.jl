# implied turn restrictions should be in both turn restrictions and no turn restrictions graphs
@testset "Implied restrictions" for gr in [G, N]
    @testset "No U turn at non-intersection" begin
        # Make sure the implied no U turn is applied at the traffic light on Wash Trl
        fr_v = findfirst(v -> get_prop(gr, v, :from_node) == 102042 && get_prop(gr, v, :to_node) == 102044, 1:nv(G))
        to_v = findfirst(v -> get_prop(gr, v, :from_node) == 102044 && get_prop(gr, v, :to_node) == 102042, 1:nv(G))

        paths = dijkstra_shortest_paths(gr, fr_v)

        @test paths.parents[to_v] != fr_v

        # make sure it is not applied in other places - U turn at Succulent Way is legal
        paths = dijkstra_shortest_paths(gr, to_v)
        @test paths.parents[fr_v] == to_v
    end

    @testset "No U turn at wrong-way one-way" begin
        # not working due to new weights
        # @test get_path(gr, (102095, 101956), 101906) == [
        #     102095, # Beavertail at Succulent
        #     101956, # Beavertail at NB JT Hwy (u turn against traffic)
        #     101936, # SB JT Hwy, can U turn here
        #     101956,
        #     102095,
        #     102104,
        #     101906
        # ]

        # make sure the edge doesn't exist
        fr = vertices_for_node(gr, (102095, 101956))
        to = vertices_for_node(gr, (101956, 102095))
        @test length(fr) == 1
        @test length(to) == 1
        @test fr[1] != to[1]
        @test !has_edge(gr, fr[1], to[1])
    end

    @testset "Can make U turn at one-way tee" begin
        # test that if there is a one-way road going off to the right, you can still make a U turn
        @test get_path(gr, (101794, 101795), 101793) == [
            101794, # Saguaro at Cactus
            101795, # Saguaro at Cholla
            101794,
            101793  # End Saguaro
        ]
    end

    @testset "Can make U turn at begin one way" begin


        # make sure the edge exists
        fr = vertices_for_node(gr, (7101960, 7101961))
        to = vertices_for_node(gr, (7101961, 7101960))
        @test length(fr) == 1
        @test length(to) == 1
        @test fr[1] != to[1]
        @test has_edge(gr, fr[1], to[1])

        # test fails due to weights. Overwrite weight for U turn edge.
        oldweight = get_prop(G, fr[1], to[1], :weight)
        set_prop!(G, fr[1], to[1], :weight, 0)

        # If a street becomes one way, we should be able to make a U turn assuming it's
        # an intersection, even if the rightmost way out of the node is the one-way street
        @test get_path(gr, (7101960, 7101961), (7101960, 7101949)) == [
            7101960, # Scorpion/Rattlesnake
            7101961, # U turn at Jackrabbit
            7101960,
            #7101949 # Rattlesnake @ JT Hwy
        ]

        set_prop!(G, fr[1], to[1], :weight, oldweight)
    end

    @testset "Can make U turn at right-direction one-way tee" begin
        # If a street tees into a right to left one way, should still be able to U turn with traffic
        @test get_path(gr, (7101960, 7101942), 7101949) == [
            7101960, # Scorpion/Rattlesnake
            7101942, # U turn at Cholla
            7101960,
            7101949 # Rattlesnake @ JT Hwy
        ]
    end

    @testset "Cannot make U turn at wrong-direction one-way tee" begin
        @test get_path(gr, (7101960, 7101949), 7101942) == [
            7101960, # Rattlesnake/Scorpion
            7101949, # JT Hwy
            101934,  # JT Hwy downgrade to single carriageway
            101896,  # JT Hwy/Cactus
            101897,  # Cactus @ Cholla
            101794,  # Cactus @ Saguaro
            101795,  # Saguaro @ Cholla
            7101965, # Cholla/Jackrabbit
            7101940, # Cholla/Oasis
            7101942  # Cholla/Rattlesnake

        ]
    end

end

@testset "Simple restrictions" begin
    # no left turn from Beavertail to Prickly Pear, need to go around the long way
    # also checks that right turn is allowed in other direction.
    @testset "No left turn" begin
        # With the no turn restrictions path, we should just get the left turn
        @test get_path(N, (101906, 102104), 3101765) == [
            101906, # Beavertail split before Garden Pkwy
            102104, # Beavertail and Prickly Pear
            3101764, # Turn onto service road
            3101765  # Circle on service road
        ]

        @test get_path(G, (101906, 102104), 3101765) == [
            101906, # Beavertail split before Garden Pkwy
            102104, # Beavertail and Prickly Pear - no left turn
            102095, # Beavertail and Succulent - can U turn here
            102104, # Back at Beavertail and Prickly Pear, can turn right
            3101764, # Turn onto service road
            3101765  # Circle on service road
        ]
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
        @test get_path(N, 102177, 102097) == [
            102177, # Succulent at Tropical Island (should remain in graph, island removal does not remove vertices)
            102095, # Succulent @ Beavertail
            102097  # Succulent at Prickly Pear
        ]

        # turn restriction graph should force right turn onto Beavertail
        @test get_path(G, 102177, 102097) == [
            102177, # Succulent at Tropical Island (should remain in graph, island removal does not remove vertices)
            102095, # Succulent @ Beavertail - only right turn (can't go straight)
            101956, # Beavertail @ JT Hwy, no u turn against traffic
            101936, # U turn
            101956,
            102095, # Beavertail @ Succulent
            102097  # Succulent at Prickly Pear
        ]

    end

    @testset "No right turn on red does not prevent right turn" begin
        @test get_path(G, 101936, 101797) == [
            101936, # Beavertail @ JT Hwy SB
            101907, # Beavertail at Saguaro (no right turn on red)
            101797  # Saguaro at Wash Trl
        ]
    end
end

@testset "Complex restrictions" begin
    @testset "No U turn with via way" begin
        @test get_path(N, 102038, 102040) == [
            102038, # SB JT Hwy @ Wash Trl
            101936, # SB JT Hwy @ Beavertail
            101956, # NB JT Hwy @ Beavertail
            101955, # NB JT Hwy @ Tropical Island
            102040  # NB JT Hwy @ Wash Trl
        ]

        # confirm that there's no u turn in the turn restriction graph - go around the block instead
        @test get_path(G, 102038, 102040) == [
            102038, # SB JT Hwy @ Wash Trl
            101936, # SB JT Hwy @ Beavertail (no U turn)
            101956, # NB JT Hwy @ Beavertail (no U turn)
            102095, # Beavertail @ Succulent
            102177, # Succulent @ Tropical Island
            102042, # Succulent/Wash
            102040  # NB JT Hwy @ Wash Trl
        ]
    end

    @testset "No U turn with multiple via ways" begin
        # confirm we get a U turn at JT Hwy without turn restrictions
        @test get_path(N, 101842, 101826) == [
            101842, # WB Garden Fwy at Wash Trl onramp
            101844, # JT Hwy exit
            101987, # ramp split
            101940, # merge to JT Hwy
            101939, # exit back to Gardn Fwy
            101969, # ramp merge
            101825, # merge onto fwy
            101826  # Garden Fwy EB at Wash Trl offramp
        ]

        # confirm a U turn can't happen with turn restriction graph
        @test get_path(G, 101842, 101826) == [
            101842, # WB Garden Fwy at Wash Trl onramp
            101844, # JT Hwy exit
            101847, # Merge to highway
            102012, # exit to rest area
            101849, # entrance from rest area
            101811, # roundabout
            101798, # roundabout -> Saguaro
            101818, # roundabout -> Garden Fwy WB
            102017, # rest area entrance
            102023, # rest area exit
            101977, # JT Hwy exit
            101825, # merge onto fwy
            101826  # Garden Fwy EB at Wash Trl offramp
        ]
    end

    @testset "No left after right" begin
        # no turn restriction graph should allow left after right
        @test get_path(N, 101945, 102013) == [
            101945, # JT Hwy diverging diamond
            101942, # Entrance ramp
            101994, # Merge with other ramp
            101847, # Merge to highway
            102012, # exit to rest area
            102013, # in rest area
        ]

        # with turn restriction, should have to go another way
        # you'd expect to go around hte roundabout (commented out) but it's marginally faster
        # to go the other way and make a U-turn back onto the ramp.
        # @test get_path(G, 101945, 102013) == [
        #     101945, # JT Hwy diverging diamond
        #     101942, # Entrance ramp
        #     101994, # Merge with other ramp
        #     101847, # Merge to highway
        #     102012, # exit to rest area, but can't exit here due to restriction
        #     101849, # entrance from rest area
        #     101811, # roundabout
        #     101798, # roundabout -> Saguaro
        #     101818, # roundabout -> Garden Fwy WB
        #     102017, # rest area entrance
        #     102028, # in rest area
        #     102024, # in rest area
        #     102013, # in rest area
        # ]
        @test get_path(G, 101945, 102013) == [
            101945, # JT Hwy diverging diamond
            101942, # Entrance ramp
            101941, # Diverging diamond cross
            101940, # Exit reamp
            101939, # Entering to Fwy
            101969, # Ramp
            101825, # Entering fwy
            101826, # On Fwy
            2101778, # Exit
            102045,  # U turn
            2101778, # Enter
            101842, # Merge to Fwy
            101844, # on fwy
            101847, # On fwy,
            102012, # exit to rest area
            102013 # in rest area
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

    @testset "Only left turn with via way" begin
        # it's unclear how only turns with via ways should be applied, and they're actually disallowed in the OSM turn restriction
        # specification, but my interpretation is that once you've entered the portion of the way that
        # connects to the via way(s), you must follow the restriction - see more in-depth discussion in
        # only_turn.jl comments.

        @testset "should not be allowed to leave restriction after from way" begin
            # without turn restrictions, we can
            @test get_path(N, (101919, 101916), (101916, 101917)) == [
                101919, # exiting NB Garden Pkwy to Beavertail
                101916 # ramps cross in middle of intersection
            ]

            # should not be allowed to leave restriction after from way
            @test get_path(G, (101919, 101916), (101916, 101917)) == [
                101919, # exiting NB Garden Pkwy to Beavertail
                101916, # ramps cross in middle of intersection, but only turn
                101903, # cross SB Garden Pkwy
                101906, # end of ramp - No U turn
                102104, # Prickly Pear U turn
                101906, # back at ramps
                101910, # ramps split
                101915, # Cross SB Garden Pkwy
                101916 # ramps cross
            ]

        end

        @testset "should not be allowed to leave restriction after via way" begin
            @test get_path(N, (101919, 101916), (101903, 101915)) == [
                101919, # exiting NB Garden Pkwy to Beavertail
                101916, # ramps cross in middle of intersection, but only turn
                101903, # cross SB Garden Pkwy
            ]

            @test get_path(G, (101919, 101916), (101903, 101915)) == [
                101919, # exiting NB Garden Pkwy to Beavertail
                101916, # ramps cross in middle of intersection, but only turn
                101903, # cross SB Garden Pkwy
                101906, # end of ramp
                102104, # Beavertail @ prickly pear
                102095, # Beavertail @ Succulent
                101956, # Beavertail @ JT Hwy
                101955, # JT Hwy @ Tropical Island
                102040, # JT Hwy @ Wash Trl
                101954, # JT Hwy @ Garden Freeway EB onramp
                101969, # Garden Freeway EB onramp
                101825, # Garden Fwy EB
                101826, # Exit to wash trail
                101834, # Downgrades to primary
                101872, # Garden Pkwy SB @ Wash Trl
                101903 # Garden Pkwy at Beavertail WB
            ]
        end
    end
end


@testset "Is turn type" begin
    # they should overlap
    @test OpenStreetMapGraphBuilder.OSM.is_turn_type(-18, "no_left_turn")
    @test OpenStreetMapGraphBuilder.OSM.is_turn_type(-18, "no_straight_on")

    # but this is too far
    @test OpenStreetMapGraphBuilder.OSM.is_turn_type(-38, "no_left_turn")
    @test !OpenStreetMapGraphBuilder.OSM.is_turn_type(-38, "no_straight_on")

    # again, overlap
    @test OpenStreetMapGraphBuilder.OSM.is_turn_type(-130, "no_left_turn")
    @test OpenStreetMapGraphBuilder.OSM.is_turn_type(-130, "no_u_turn")

    @test OpenStreetMapGraphBuilder.OSM.is_turn_type(18, "only_right_turn")
    @test OpenStreetMapGraphBuilder.OSM.is_turn_type(18, "only_straight_on")

    # but this is too far
    @test OpenStreetMapGraphBuilder.OSM.is_turn_type(38, "only_right_turn")
    @test !OpenStreetMapGraphBuilder.OSM.is_turn_type(38, "only_straight_on")

    # again, overlap
    @test OpenStreetMapGraphBuilder.OSM.is_turn_type(130, "only_right_turn")
    @test OpenStreetMapGraphBuilder.OSM.is_turn_type(130, "only_u_turn")
end