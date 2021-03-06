@enum RoadClass motorway motorway_link trunk trunk_link primary primary_link secondary secondary_link tertiary tertiary_link unclassified residential service other

function get_road_class(cln::String)
    if cln == "motorway"
        return motorway
    elseif cln == "motorway_link"
        return motorway_link
    elseif cln == "trunk"
        return trunk
    elseif cln == "trunk_link"
        return trunk_link
    elseif cln == "primary"
        return primary
    elseif cln == "primary_link"
        return primary_link
    elseif cln == "secondary"
        return secondary
    elseif cln == "secondary_link"
        return secondary_link
    elseif cln == "tertiary"
        return tertiary
    elseif cln == "tertiary_link"
        return tertiary_link
    elseif cln == "unclassified"
        return unclassified
    elseif cln == "residential"
        return residential
    elseif cln == "service"
        return service
    else
        return other
    end
end

mutable struct WaySegment
    origin_node::Int64
    destination_node::Int64
    way_id::Int64
    heading_start::Float32
    heading_end::Float32
    length_m::Float32
    oneway::Bool
    start_traffic_signal::Bool # Is there a traffic signal at the start of this way segment
    end_traffic_signal::Bool # Is there a traffic signal at the end of this way segment
    lanes::Union{Int64, Missing}
    speed_kmh::Union{Float64, Missing}
    # can't be packed, oh well - we're not serializing anyhow
    nodes::Vector{Int64}
    class::RoadClass
end

struct NodeAndCoord
    id::Int64
    lat::Float64
    lon::Float64
end