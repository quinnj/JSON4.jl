import Base: ==

@noinline invalid(error, buf, pos, T) = throw(ArgumentError("""
invalid JSON at byte position $pos while parsing type $T: $error
$(String(buf[max(1, pos-25):min(end, pos+25)]))
"""))

const EMPTY = UInt8[]

struct JString{T <: AbstractVector{UInt8}} <: AbstractString
    buf::T
    pos::Int
    len::Int
    escaped::String

    JString(buf::T, pos::Int, len::Int) where {T} =new{T}(buf, pos, len)
    JString(escaped::String) = new{Vector{UInt8}}(EMPTY, 0, sizeof(escaped), escaped)
end

Base.pointer(x::JString, i::Integer=1) = pointer(x.buf, x.pos + i - 1)

function ==(x::String, y::JString)
    sizeof(x) == sizeof(y) || return false
    if !escaped(y)
        ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t),
              pointer(x), pointer(y), sizeof(x)) == 0
    else
        return ==(x, y.escaped)
    end
end
==(y::JString, x::String) = x == y

escaped(x::JString) = isdefined(x, :escaped)
Base.ncodeunits(x::JString) = x.len
Base.codeunit(::JString) = UInt8
Base.codeunit(x::JString, i::Integer) = escaped(x) ? codeunit(x.escaped, i) : getbyte(x.buf, x.pos + i - 1)
Base.@propagate_inbounds function Base.isvalid(x::JString, i::Int)
    @boundscheck checkbounds(Bool, x, i) || throw(BoundsError(x, i))
    return @inbounds thisind(x, i) == i
end
Base.@propagate_inbounds function Base.thisind(s::JString, i::Int)
    i == 0 && return 0
    n = ncodeunits(s)
    i == n + 1 && return i
    @boundscheck Base.between(i, 1, n) || throw(BoundsError(s, i))
    @inbounds b = codeunit(s, i)
    (b & 0xc0 == 0x80) & (i-1 > 0) || return i
    @inbounds b = codeunit(s, i-1)
    Base.between(b, 0b11000000, 0b11110111) && return i-1
    (b & 0xc0 == 0x80) & (i-2 > 0) || return i
    @inbounds b = codeunit(s, i-2)
    Base.between(b, 0b11100000, 0b11110111) && return i-2
    (b & 0xc0 == 0x80) & (i-3 > 0) || return i
    @inbounds b = codeunit(s, i-3)
    Base.between(b, 0b11110000, 0b11110111) && return i-3
    return i
end
Base.@propagate_inbounds function Base.iterate(s::JString, i::Int=firstindex(s))
    (i % UInt) - 1 < ncodeunits(s) || return nothing
    b = @inbounds codeunit(s, i)
    u = UInt32(b) << 24
    Base.between(b, 0x80, 0xf7) || return reinterpret(Char, u), i+1
    return iterate_continued(s, i, u)
end
function iterate_continued(s::JString, i::Int, u::UInt32)
    u < 0xc0000000 && (i += 1; @goto ret)
    n = ncodeunits(s)
    # first continuation byte
    (i += 1) > n && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 16
    # second continuation byte
    ((i += 1) > n) | (u < 0xe0000000) && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 8
    # third continuation byte
    ((i += 1) > n) | (u < 0xf0000000) && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b); i += 1
@label ret
    return reinterpret(Char, u), i
end

function reverseescapechar(b)
    b == UInt8('"')  && return UInt8('"')
    b == UInt8('\\') && return UInt8('\\')
    b == UInt8('/')  && return UInt8('/')
    b == UInt8('b')  && return UInt8('\b')
    b == UInt8('f')  && return UInt8('\f')
    b == UInt8('n')  && return UInt8('\n')
    b == UInt8('r')  && return UInt8('\r')
    b == UInt8('t')  && return UInt8('\t')
    return 0x00
end

utf16_is_surrogate(c::UInt16) = (c & 0xf800) == 0xd800
utf16_get_supplementary(lead::UInt16, trail::UInt16) = Char(UInt32(lead-0xd7f7)<<10 + trail)

charvalue(b) = (UInt8('0') <= b <= UInt8('9')) ? b - UInt8('0') :
               (UInt8('a') <= b <= UInt8('f')) ? b - (UInt8('a') - 0x0a) :
               (UInt8('A') <= b <= UInt8('F')) ? b - (UInt8('A') - 0x0a) :
               throw(ArgumentError("JSON invalid unicode hex value"))

@noinline invalid_escape(str) = throw(ArgumentError("encountered invalid escape character in json string: \"$(String(str))\""))
@noinline unescaped_control(b) = throw(ArgumentError("encountered unescaped control character in json: '$(escape_string(Base.string(Char(b))))'"))

function unescape(s)
    n = ncodeunits(s)
    buf = Base.StringVector(n)
    len = 1
    i = 1
    @inbounds begin
        while i <= n
            b = codeunit(s, i)
            if b == UInt8('\\')
                i += 1
                i > n && invalid_escape(s)
                b = codeunit(s, i)
                if b == UInt8('u')
                    c = 0x0000
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    i += 1
                    i > n && invalid_escape(s)
                    b = codeunit(s, i)
                    c = (c << 4) + charvalue(b)
                    if utf16_is_surrogate(c)
                        i += 3
                        i > n && invalid_escape(s)
                        c2 = 0x0000
                        b = codeunit(s, i)
                        c2 = (c2 << 4) + charvalue(b)
                        i += 1
                        i > n && invalid_escape(s)
                        b = codeunit(s, i)
                        c2 = (c2 << 4) + charvalue(b)
                        i += 1
                        i > n && invalid_escape(s)
                        b = codeunit(s, i)
                        c2 = (c2 << 4) + charvalue(b)
                        i += 1
                        i > n && invalid_escape(s)
                        b = codeunit(s, i)
                        c2 = (c2 << 4) + charvalue(b)
                        ch = utf16_get_supplementary(c, c2)
                    else
                        ch = Char(c)
                    end
                    st = codeunits(Base.string(ch))
                    for j = 1:length(st)-1
                        @inbounds buf[len] = st[j]
                        len += 1
                    end
                    b = st[end]
                else
                    b = reverseescapechar(b)
                    b == 0x00 && invalid_escape(s)
                end
            end
            @inbounds buf[len] = b
            len += 1
            i += 1
        end
    end
    resize!(buf, len - 1)
    return String(buf)
end
