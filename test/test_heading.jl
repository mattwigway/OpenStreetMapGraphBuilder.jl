# Test the algorithms in compute_heading.jl

@testset "Compute heading" begin
    @test OpenStreetMapGraphBuilder.OSM.compute_heading(LatLon(37, -121), LatLon(37.1, -121)) ≈ 0
    @test OpenStreetMapGraphBuilder.OSM.compute_heading(LatLon(37, -121), LatLon(37.01, -121 + 0.01 / cosd(37))) ≈ 45
    @test OpenStreetMapGraphBuilder.OSM.compute_heading(LatLon(37, -121), LatLon(37, -120.9)) ≈ 90
    @test OpenStreetMapGraphBuilder.OSM.compute_heading(LatLon(37, -121), LatLon(36.9, -121 + 0.1 / cosd(37))) ≈ 135
    @test OpenStreetMapGraphBuilder.OSM.compute_heading(LatLon(37, -121), LatLon(36.9, -121)) ≈ 180
    @test OpenStreetMapGraphBuilder.OSM.compute_heading(LatLon(37, -121), LatLon(36.9, -121 - 0.1 / cosd(37))) ≈ 225
    @test OpenStreetMapGraphBuilder.OSM.compute_heading(LatLon(37, -121), LatLon(37, -121.1)) ≈ 270
    @test OpenStreetMapGraphBuilder.OSM.compute_heading(LatLon(37, -121), LatLon(37.1, -121 - 0.1 / cosd(37))) ≈ 315
end

@testset "Bearing between" begin
    @test OpenStreetMapGraphBuilder.OSM.bearing_between(0, 75) == 75
    @test OpenStreetMapGraphBuilder.OSM.bearing_between(0, 320) == -40
    @test OpenStreetMapGraphBuilder.OSM.bearing_between(190, 200) == 10
    @test OpenStreetMapGraphBuilder.OSM.bearing_between(190, 170) == -20
end

@testset "Circular add" begin
    @test OpenStreetMapGraphBuilder.OSM.circular_add(350, 180) == 170
    @test OpenStreetMapGraphBuilder.OSM.circular_add(-50, -180) == 130
end

@testset "Headings for geom" begin
    @test OpenStreetMapGraphBuilder.OSM.calculate_headings_for_geom([LatLon(36.9, -121), LatLon(37, -121), LatLon(37, -120.9)]) == (0, 90)

    # should not be affected by short heading changes at end, minimum distance req'd for heading calculation
    fr, to = OpenStreetMapGraphBuilder.OSM.calculate_headings_for_geom([LatLon(36.9, -121 - 1e-11), LatLon(36.9, -121), LatLon(37, -121), LatLon(37, -120.9), LatLon(37 + 1e-11, -120.9)])
    @test isapprox(fr, 0, atol=1e-5)
    @test to ≈ 90
end