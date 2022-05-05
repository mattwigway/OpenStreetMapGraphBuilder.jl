# test GML export

# this is a simple but fragile parser
# it assumes that line breaks are present, for example
function read_graph(buf)
    G = MetaDiGraph()
    current = Dict{String, Any}()

    processing_mode = nothing

    for line in eachline(buf)
        line = strip(line)
        if contains(line, "node [")
            processing_mode = :node
        elseif contains(line, "edge [")
            processing_mode = :edge
        elseif contains(line, "]")
            if processing_mode == :node
                add_vertex!(G)
                # simplifying assumption: nodes are written in order
                vxnbr = nv(G)
                curid = current["id"]
                vxnbr == curid || error("Node IDs not ordered: expected $vxnbr, found $(curid)")
                for (k, v) in pairs(current)
                    if k ∉ Set(["id", "label"])
                        set_prop!(G, vxnbr, Symbol(k), v)
                    end
                end
                empty!(current)
            elseif processing_mode == :edge
                src = current["source"]
                dest = current["target"]
                @assert add_edge!(G, src, dest)

                for (k, v) in pairs(current)
                    if k ∉ Set(["source", "target"])
                        set_prop!(G, src, dest, Symbol(k), v)
                    end
                end
                empty!(current)
            end

            processing_mode = nothing
        elseif !isnothing(processing_mode)
            # we're reading an attribute
            k, val = split(line, " ", limit=2)
            val = strip(val, [' ', '"'])
            parsed = if !isnothing(match(r"^-?[0-9]+[.][0-9]+$", val))
                parse(Float64, val)
            elseif !isnothing(match(r"-?^[0-9]+$", val))
                parse(Int64, val)
            else
                val
            end

            if haskey(current, k)
                if current[k] isa Vector
                    push!(current[k], parsed)
                else
                    current[k] = [current[k], parsed]
                end
            else
                current[k] = parsed
            end
            # catch e
            #     @warn "Error reading line" line
            # end
        end
    end
    return G
end

@testset "GML roundtrip" begin
    buf = IOBuffer()
    StreetRouter.to_gml(G, buf)

    # Read the GML back in. Can't use GraphIO as it doesn't support edge attributes
    seekstart(buf)

    G2 = read_graph(buf)

    @test nv(G) == nv(G2)
    @test ne(G) == ne(G2)
    for v in 1:nv(G)
        @test inneighbors(G, v) == inneighbors(G2, v)

        # we don't write everything to GML. Check the things we care about
        geom = get_prop(G, v, :geom)
        lats = get_prop(G2, v, :lats)
        lons = get_prop(G2, v, :lons)
        @test length(geom) == length(lons)
        @test length(geom) == length(lats)
        @test all(map(x -> x.lat, geom) .≈ lats)
        @test all(map(x -> x.lon, geom) .≈ lons)
    end

    for e in edges(G)
        @test get_prop(G, e, :weight) ≈ get_prop(G2, src(e), dst(e), :weight)
        @test get_prop(G, e, :length_m) ≈ get_prop(G2, src(e), dst(e), :length_m)
    end
end