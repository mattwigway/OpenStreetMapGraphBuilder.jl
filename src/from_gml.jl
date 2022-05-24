# read a GML file
# TODO slow!

# use macro to avoid recompiling regex each call
macro is_open_tag(line, tag)
    r = Regex("^\\h*$(tag)\\h+\\[\\h*\$")
    :(occursin($r, $(esc(line))))
end

is_close_tag(line) = strip(line) == "]"

mutable struct FileAndLineNumber
    io::IO
    line_number::Int64
end

FileAndLineNumber(io) = FileAndLineNumber(io, 0)
function Base.readline(f::FileAndLineNumber)
    f.line_number += 1
    readline(f.io)
end

line_number(f::FileAndLineNumber) = f.line_number

function from_gml(filename)
    open(filename) do fileraw
        file = FileAndLineNumber(fileraw)
        while true
            line = readline(file)
            if @is_open_tag(line, "graph")
                return process_graph(file)
            end
        end
        error("no graph found in $filename")
    end
end

function process_graph(file)
    # figure out if we're a directed graph or not
    prog = ProgressUnknown()
    G = nothing
    while true
        line = readline(file)
        m = match(r"^\h*directed\h+([01])\h*", line)
        if !isnothing(m)
            if m[1] == "1"
                G = MetaDiGraph()
            else
                G = DiGraph()
            end
            break
        end
    end

    # now read lines
    while true
        line = readline(file)
        ProgressMeter.next!(prog)
        if @is_open_tag(line, "node")
            process_node(file, G)
        elseif @is_open_tag(line, "edge")
            process_edge(file, G)
        elseif is_close_tag(line)
            ProgressMeter.finish!(prog)
            return G
        end
    end
end

function process_node(file, G)
    props = Dict{Symbol, Any}()
    found_id = false
    while true
        line = readline(file)
        m = match(r"^\h*id\h+([0-9]+)\h*$", line)
        if !isnothing(m)
            found_id = true
            id = parse(Int64, m[1])
            if id != nv(G) + 1
                error("At line number $(line_number(file)), found vertex id $id, expected $(nv(G) + 1) (vertices must be in order)")
            end
        elseif is_close_tag(line)
            if !found_id
                error("For node ending on line $(line_number(file)), did not find ID")
            end
            add_vertex!(G, props)
            break
        else
            parse_prop(line, file, props)
        end
    end
end

function process_edge(file, G)
    source = -1
    target = -1
    props = Dict{Symbol, Any}()
    while true
        line = readline(file)
        if !isnothing(begin m = match(r"^\h*source\h+([0-9]+)\h*$", line) end)
            source = parse(Int64, m[1])
        elseif !isnothing(begin m = match(r"^\h*target\h+([0-9]+)\h*$", line) end)
            target = parse(Int64, m[1])
        elseif is_close_tag(line)
            if source == -1 || target == -1
                error("For node ending on line $(line_number(file)), did not find source and target")
            end
            add_edge!(G, source, target, props)
            return
        else
            parse_prop(line, file, props)
        end
    end
end

function parse_prop(line, file, props)
    m = match(r"^\h*([^\h]+)\h+(.*)\h*$", line)
    if isnothing(m)
        error("Could not parse attribute from \"$line\", at line $(line_number(file))")
    else
        key = Symbol(m[1])
        if occursin(r"^-?[0-9]+$", m[2])
            # integer prop
            add_prop(key, parse(Int64, m[2]), props)
        elseif occursin(r"^-?[0-9]*\.[0-9]+(e\+?-?[0-9]+)?$|^nan$|^NaN$|^NAN$", m[2])
            # float prop
            add_prop(key, parse(Float64, m[2]), props)
        else
            # string prop
            add_prop(key, m[2], props)
        end
    end
end

function add_prop(key, val, props)
    if haskey(props, key)
        ex = props[key]
        if ex isa Vector
            push!(ex, val)
        else
            props[key] = typeof(val)[val]
        end
    else
        props[key] = val
    end
end