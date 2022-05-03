@testset "Weights" begin
    @testset "All edges have weights" begin
        for edge in edges(G)
            @test get_prop(G, edge, :weight) > 0 
            @test get_prop(G, edge, :weight) != 1  # should not be exactly 1 as that's probably a default
            @test get_prop(G, edge, :traversal_time) > 0
            @test get_prop(G, edge, :turn_cost) ≥ 0
        end    
    end

    @testset "traffic lights" begin
        fr = vertices_for_node(G, (102042, 102044))[1]
        to = vertices_for_node(G, (102044, 102045))[1]
        @test get_prop(G, fr, to, :traffic_signal)
        @test isapprox(get_prop(G, fr, to, :weight),
            get_prop(G, fr, to, :length_m) / 1000 / StreetRouter.OSM.DEFAULT_FREEFLOW_SPEEDS["residential"] * 3600 +
            StreetRouter.TRAFFIC_LIGHT_PENALTY_SECS +
            StreetRouter.BASE_INTERSECTION_COST,
            atol=0.05)
        
        # and check for back edge as well
        fr = vertices_for_node(G, (102045, 102044))[1]
        to = vertices_for_node(G, (102044, 102042))[1]
        @test get_prop(G, fr, to, :traffic_signal)
        @test isapprox(get_prop(G, fr, to, :weight),
            get_prop(G, fr, to, :length_m) / 1000 / StreetRouter.OSM.DEFAULT_FREEFLOW_SPEEDS["residential"] * 3600 +
            StreetRouter.TRAFFIC_LIGHT_PENALTY_SECS +
            StreetRouter.BASE_INTERSECTION_COST,
            atol=0.05)

        # but confirm not for other direction
        fr = vertices_for_node(G, (102044, 102042))[1]
        to = vertices_for_node(G, (102042, 102040))[1]
        @test !get_prop(G, fr, to, :traffic_signal)
        @test isapprox(get_prop(G, fr, to, :weight),
            get_prop(G, fr, to, :length_m) / 1000 / StreetRouter.OSM.DEFAULT_FREEFLOW_SPEEDS["residential"] * 3600 +
            StreetRouter.BASE_INTERSECTION_COST,
            atol=0.05)

        fr = vertices_for_node(G, (102044, 102045))[1]
        to = vertices_for_node(G, (102045, 101872))[1]
        @test !get_prop(G, fr, to, :traffic_signal)
        @test isapprox(get_prop(G, fr, to, :weight),
            get_prop(G, fr, to, :length_m) / 1000 / StreetRouter.OSM.DEFAULT_FREEFLOW_SPEEDS["residential"] * 3600 +
            StreetRouter.BASE_INTERSECTION_COST,
            atol=0.05)
    end

    @testset "Turn costs" begin
        @testset "Left turn should be more costly than right turn" begin
            # TODO handle drive-on-left
            @test get_prop(G, get_edge(G, 3101764, 102104, 102095)..., :turn_cost) > get_prop(G, get_edge(G, 3101764, 102104, 101906)..., :turn_cost)
            @test get_prop(G, get_edge(G, 3101764, 102104, 102095)..., :weight) > get_prop(G, get_edge(G, 3101764, 102104, 101906)..., :weight)
        end

        @testset "No turn costs on motorway" begin
            @test get_prop(G, get_edge(G, 101825, 101826, 101834)..., :turn_cost) == 0
            @test get_prop(G, get_edge(G, 101825, 101826, 2101778)..., :turn_cost) == 0
            @test get_prop(G, get_edge(G, 2101778, 101842, 101844)..., :turn_cost) == 0
            @test get_prop(G, get_edge(G, 101836, 101842, 101844)..., :turn_cost) == 0
        end

        @testset "Traffic signal costs lower than non-traffic-signal" begin
            # left turn
            @test (
                get_prop(G, get_edge(G, 101956, 101936, 7101949)..., :turn_cost) -
                get_prop(G, get_edge(G, 101934, 101896, 102100)..., :turn_cost) > 1
            )

            # right turn
            @test (
                get_prop(G, get_edge(G, 102095, 101956, 101955)..., :turn_cost) -
                get_prop(G, get_edge(G, 101934, 101896, 101897)..., :turn_cost) > 1
            )
        end

        @testset "Maxspeed tags" begin
            e1 = get_edge(G, 7101961, 7101960, 7101949)
            @test get_prop(G, e1..., :speed_kmh) ≈ 30 * StreetRouter.OSM.MAXSPEED_MULTIPLIER
            @test get_prop(G, e1..., :traversal_time) ≈ get_prop(G, e1..., :length_m) / 1000 /
                (30 * StreetRouter.OSM.MAXSPEED_MULTIPLIER) * 3600 
        end
    end
end