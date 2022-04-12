mutable struct WaySegment
    origin_node::Int64
    destination_node::Int64
    way_id::Int64
    heading_start::Float32
    heading_end::Float32
    length_m::Float32
    oneway::Bool
    traffic_signal::Int32  # number of traffic signals on this way, _not including at first node_
    back_traffic_signal::Int32 # number of traffic signals on this way, _not including at last node_
    lanes::Union{Int64, Missing}
    speed_kmh::Union{Float64, Missing}
    # can't be packed, oh well - we're not serializing anyhow
    nodes::Vector{Int64}
end

struct NodeAndCoord
    id::Int64
    lat::Float64
    lon::Float64
end