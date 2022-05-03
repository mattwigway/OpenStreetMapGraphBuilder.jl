const KMH_TO_MS = 1000 / 3600
# car.lua says the traffic light penalty is 2 deciseconds or 0.2 seconds, but that seems unreasonably
# short. Based on reading the code it seems likely that these are intended to be _decaseconds_ or
# tens of seconds, and the docs are simply wrong
# https://github.com/Project-OSRM/osrm-backend/issues/5989
const TRAFFIC_LIGHT_PENALTY_SECS = 2.0
# makes left turns more costly than right - for drive-on-left countries, set to
# 1/1.075
const TURN_BIAS = 1.075
const TURN_PENALTY = 10 # prefer turns at signals
const TURN_PENALTY_SIGNAL = 5
const U_TURN_PENALTY = 20.0
const BASE_INTERSECTION_COST = 5.0  # This isn't in OSRM, but I think all intersection not on the motorway system should have some cost.

# get the free flow weight (i.e. travel time, in seconds) for an edge
# this is heavily based on the car.lua profile from OSRM v5.24.0
function compute_freeflow_weight(G, edge)
    traversal_time_secs::Float64 = 0.0

    # first, compute traversal time for the segment
    rclass = get_prop(G, edge, :this_class)::OSM.RoadClass
    length_m = convert(Float64, get_prop(G, edge, :length_m))::Float64

    next_rclass = get_prop(G, edge, :next_class)

    # read the speed limit if it was in OSM, otherwise use default
    speed_kmh = get_prop(G, edge, :speed_kmh)

    traffic_signal = get_prop(G, edge, :traffic_signal)
    
    traversal_time_secs += length_m / (speed_kmh * KMH_TO_MS)

    if traffic_signal
        traversal_time_secs += TRAFFIC_LIGHT_PENALTY_SECS
    end

    # first, determine if we even need a turn cost
    if ((rclass == OSM.motorway || rclass == OSM.motorway_link) &&
        (next_rclass == OSM.motorway || next_rclass == OSM.motorway_link) && !traffic_signal)
        # no turn costs needed in the motorway system
        return traversal_time_secs, 0.0
    else
        # need to compute turn costs
        turn_cost = BASE_INTERSECTION_COST  

        turn_angle = get_prop(G, edge, :turn_angle)

        if turn_angle >= 0
            # copied directly from lua code, I don't understand the math, it's a sigmoid of some sort
            # car.lua is confusing, but these values are actually in seconds
            turn_cost += (traffic_signal ? TURN_PENALTY_SIGNAL : TURN_PENALTY) / (1 + exp( -((13 / TURN_BIAS) *  turn_angle/180 - 6.5*TURN_BIAS)))
        else
            turn_cost += (traffic_signal ? TURN_PENALTY_SIGNAL : TURN_PENALTY) / (1 + exp( -((13 * TURN_BIAS) * -turn_angle/180 - 6.5/TURN_BIAS)))
        end

        if StreetRouter.OSM.is_turn_type(turn_angle, "u_turn")
            turn_cost += U_TURN_PENALTY
        end
    end

    return traversal_time_secs, turn_cost
end

function compute_freeflow_weights!(G)
    for edge in edges(G)
        traversal_time, turn_cost = compute_freeflow_weight(G, edge)
        set_prop!(G, edge, :traversal_time, convert(Float64, traversal_time))
        set_prop!(G, edge, :turn_cost, convert(Float64, turn_cost))
        set_prop!(G, edge, :weight, traversal_time + turn_cost)
    end
end