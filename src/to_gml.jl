# Convert a street router graph to GML
# There are packages to do this, but they don't support attributes, and the format is simple enough

mutable struct GMLState
    io::IO
    tagstack::Stack{String}
end

GMLState(io::IO) = GMLState(io, Stack{String}())

function Base.write(gml::GMLState, str::Union{String, Symbol}; last="\n")
    for _ in 1:length(gml.tagstack)
        write(gml.io, "  ")
    end
    write(gml.io, str)
    write(gml.io, last)
end

function Base.write(gml::GMLState, key::Union{String, Symbol}, val) 
    write(gml, key, last=" ")
    show(gml.io, val)
    write(gml.io, "\n")
end

Base.write(gml::GMLState, key::Union{String, Symbol}, val::Float32) = write(gml, key, convert(Float64, val))
function Base.write(gml::GMLState, key::Union{String, Symbol}, val::Vector{<:Any})
    for v in val
        write(gml, k, v)
    end
end

function starttag(gml::GMLState, tag::String)
    write(gml, "$tag [")
    push!(gml.tagstack, tag)
end

function endtag(gml::GMLState, tag::String)
    lasttag = pop!(gml.tagstack)
    lasttag == tag || error("Tried to close $lasttag with $tag")
    write(gml, "]")
end

to_gml(G, outfile::String) = open(x -> to_gml(G, x), outfile, "w")

function to_gml(G, f::IO)
    gml = GMLState(f)
    starttag(gml, "graph")
    write(gml, "comment", "StreetRouter.jl graph")
    write(gml, "directed", 1)

    for v in 1:nv(G)
        starttag(gml, "node")
        write(gml, "id", v)
        write(gml, "label", v)
        geom = get_prop(G, v, :geom)
        for ll in geom
            write(gml, "lats", ll.lat)
        end
        for ll in geom
            write(gml, "lons", ll.lon)
        end

        # for (prop, val) in pairs(props(G, v))
        #     if prop == :geom
        #         val = map(ll -> (ll.lon, ll.lat), val)
        #     end
        #     write(gml, prop, val)
        # end
        endtag(gml, "node")
    end

    for edge in edges(G)
        starttag(gml, "edge")
        write(gml, "source", edge.src)
        write(gml, "target", edge.dst)
        # for (prop, val) in pairs(props(G, edge))
        #     write(gml, prop, val)
        # end
        write(gml, "weight", get_prop(G, edge, :weight))
        write(gml, "length_m", get_prop(G, edge, :length_m))
        endtag(gml, "edge")
    end
    endtag(gml, "graph")
end
