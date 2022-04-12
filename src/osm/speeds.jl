const MILES_TO_KILOMETERS = 1.609344
const KNOTS_TO_KMH = 1.852

function parse_max_speed(speed_text)::Union{Float64, Missing}
    try
        return parse(Float64, speed_text)
    catch
        # not a raw km/hr number
        mtch = match(r"([0-9]+)(?: ?)([a-zA-Z/]+)", speed_text)
        if isnothing(mtch)
            @warn "unable to parse speed limit $speed_text"
            return missing
        else
            speed_scalar = parse(Float64, mtch.captures[1])
            units = lowercase(mtch.captures[2])

            if (units == "kph" || units == "km/h" || units == "kmph")
                return speed_scalar
            elseif units == "mph"
                return speed_scalar * MILES_TO_KILOMETERS
            elseif units == "knots"
                return speed_scalar * KNOTS_TO_KMH
            else
                @warn "unknown speed unit $units"
                return missing
            end
        end
    end
end

# car.lua says the traffic light penalty is 2 deciseconds or 0.2 seconds, but that seems unreasonably
# short. Based on reading the code it seems likely that these are intended to be _decaseconds_ or
# tens of seconds, and the docs are simply wrong
# https://github.com/Project-OSRM/osrm-backend/issues/5989
# const TRAFFIC_LIGHT_PENALTY_SECS = 20.0
# const BASE_TURN_PENALTY = 7.5
# # makes left turns more costly than right - for drive-on-left countries, set to
# # 1/1.075
# const TURN_BIAS = 1.075
# const TURN_PENALTY = 7.5

const DEFAULT_SPEED = 50.0

# copied from OSRM 5.24.0 car.lua
const DEFAULT_FREEFLOW_SPEEDS = Dict{String, Float64}(
    "motorway" => 90.0,
    "motorway_link" => 45,
    "trunk" => 85,
    "trunk_link" => 40,
    "primary" => 65,
    "primary_link" => 30,
    "secondary" => 55,
    "secondary_link" => 25,
    "tertiary" => 40,
    "tertiary_link" => 20,
    "unclassified" => 25,
    "residential" => 25,
    "living_street" => 10,
    "service" => 15,

    # additional link types that are driveable
    "road" => DEFAULT_SPEED
)

default_speed_for_way(way) = haskey(way.tags, "highway") ? getindex(DEFAULT_FREEFLOW_SPEEDS, way.tags["highway"]::String, DEFAULT_SPEED) : DEFAULT_SPEED