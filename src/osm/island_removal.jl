# Remove islands from a graph
using DelimitedFiles

function remove_islands_smaller_than(G, island_size)
    to_remove = Vector{Int64}()
    n_removed = 0
    for component in strongly_connected_components(G)
        if length(component) < island_size
            push!.(Ref(to_remove), component)
            n_removed += 1
        end
    end

    # remove in backwards order to avoid affecting vertex indexing
    sort!(to_remove, rev=true)

    for v in to_remove
        @assert rem_vertex!(G, v)
    end

    writedlm("removed_vertices.txt", [to_remove], ',')

    @info "removed $n_removed components with less than $island_size vertices"
end
