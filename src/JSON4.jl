module JSON4

include("utils.jl")
include("core.jl")

# @enum PathType Root GetProperty GetIndex RecursiveSearch

# mutable struct PathNode{T}
#     type::PathType
#     value::T
#     parent::Union{PathNode, Nothing}
#     next::Union{PathNode, Nothing}
# end
# Base.$() = PathNode(Root, nothing, nothing, nothing)

# function Base.getproperty(x::PathNode, key::Symbol)
#     x.next = PathNode(GetProperty, String(key), x, nothing)
#     return getfield(x, :next)
# end

# function Base.getindex(x::PathNode, key::String)
#     x.next = PathNode(GetProperty, key, x, nothing)
#     return getfield(x, :next)
# end

# function Base.getindex(x::PathNode, i::Int)
#     x.next = PathNode(GetIndex, i, x, nothing)
#     return getfield(x, :next)
# end

# function Base.getindex(x::PathNode, I::Vararg{Int})
#     x.next = PathNode(GetIndex, I, x, nothing)
#     return getfield(x, :next)
# end

# function Base.getindex(x::PathNode, i::Colon)
#     x.next = PathNode(GetIndex, i, x, nothing)
#     return getfield(x, :next)
# end

# function Base.getindex(x::PathNode, r::AbstractRange)
#     x.next = PathNode(GetIndex, r, x, nothing)
#     return getfield(x, :next)
# end

# function Base.getindex(x::PathNode, f::Base.Callable)
#     x.next = PathNode(GetIndex, f, x, nothing)
#     return getfield(x, :next)
# end

# function Base.getindex(x::PathNode, ::typeof(~))
#     x.type = RecursiveSearch
#     return getfield(x, :next)
# end


struct Object{T <: AbstractVector{UInt8}}
    buf::T
    pos::Int
end

buffer(x::Object) = getfield(x, :buf)
position(x::Object) = getfield(x, :pos)

struct Array{T <: AbstractVector{UInt8}}
    buf::T
    pos::Int
end

struct ForEach{T}
    items::Vector{T}
end

items(x::ForEach) = getfield(x, :items)
Base.getindex(x::ForEach) = items(x)
ForEach() = ForEach([])
Base.length(x::ForEach) = length(getfield(x, :items))
Base.eltype(::ForEach{T}) where {T} = T

function Base.iterate(x::ForEach, i=1)
    i > length(x) && return nothing
    return getfield(x, :items)[i], i + 1
end

struct NotFound end
const notfound = NotFound()
mutable struct FoundProperty
    key::String
    value::Any
end
(f::FoundProperty)(x, k, v) = k == f.key && (f.value = v) === v

Base.getproperty(x::Object, key::Symbol) = getindex(x, String(key))

function Base.getindex(x::Object, key::String)
    buf, pos = buffer(x), position(x)
    itr = ObjectIterator(buf, pos)
    while true
        state = iterate(itr)
        if state !== nothing && state[2][2] === VALUE && state[1] == key
            pos = state[2][1]
            return getvalue(buf, pos, length(buf), buf[pos])
        elseif state === nothing || state[2][2] === DONE
            break
        end
    end
    throw(KeyError(key))
end

function Base.getindex(x::Object, ::Colon)
    buf, pos = buffer(x), position(x)
    itr = ObjectIterator(buf, pos)
    items = []
    while true
        state = iterate(itr)
        if state !== nothing && state[2][2] === KEY
            push!(items, state[1][2])
        elseif state === nothing || state[2][2] === DONE
            break
        end
    end
    return ForEach(items)
end

end # module
