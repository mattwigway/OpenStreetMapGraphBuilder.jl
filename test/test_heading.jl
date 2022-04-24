# Test the algorithms in compute_heading.jl

@testset "Compute heading" begin
    @test StreetRouter.OSM.compute_heading(LatLon(37, -121), LatLon(37.1, -121)) ≈ 0
    @test StreetRouter.OSM.compute_heading(LatLon(37, -121), LatLon(37.01, -121 + 0.01 / cosd(37))) ≈ 45
    @test StreetRouter.OSM.compute_heading(LatLon(37, -121), LatLon(37, -120.9)) ≈ 90
    @test StreetRouter.OSM.compute_heading(LatLon(37, -121), LatLon(36.9, -121 + 0.1 / cosd(37))) ≈ 135
    @test StreetRouter.OSM.compute_heading(LatLon(37, -121), LatLon(36.9, -121)) ≈ 180
    @test StreetRouter.OSM.compute_heading(LatLon(37, -121), LatLon(36.9, -121 - 0.1 / cosd(37))) ≈ 225
    @test StreetRouter.OSM.compute_heading(LatLon(37, -121), LatLon(37, -121.1)) ≈ 270
    @test StreetRouter.OSM.compute_heading(LatLon(37, -121), LatLon(37.1, -121 - 0.1 / cosd(37))) ≈ 315
end