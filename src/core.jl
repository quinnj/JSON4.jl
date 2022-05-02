@enum Error UnexpectedEOF ExpectedOpeningObjectChar ExpectedOpeningQuoteChar ExpectedOpeningArrayChar ExpectedClosingArrayChar ExpectedComma ExpectedSemiColon ExpectedNewline InvalidChar InvalidNumber

function getbyte(buf::AbstractVector{UInt8}, pos)
    @inbounds b = buf[pos]
    return b
end

macro nextbyte(checkwh=true)
    esc(quote
        if pos > len
            error = UnexpectedEOF
            @goto invalid
        end
        b = getbyte(buf, pos)
        if $checkwh
            while b == UInt8('\t') || b == UInt8(' ') || b == UInt8('\n') || b == UInt8('\r')
                pos += 1
                if pos > len
                    error = UnexpectedEOF
                    @goto invalid
                end
                b = getbyte(buf, pos)
            end
        end
    end)
end

# value
function getvalue(buf, pos, len, b)
    if b == UInt8('{')
        return Object(buf, pos)
    elseif b == UInt8('[')
        return Array(buf, pos)
    elseif b == UInt8('"')
        return readstring(buf, pos, len, b)
    elseif pos + 3 <= len &&
        b            == UInt8('n') &&
        buf[pos + 1] == UInt8('u') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('l')
        return pos + 4, nothing
    elseif pos + 3 <= len &&
        b            == UInt8('t') &&
        buf[pos + 1] == UInt8('r') &&
        buf[pos + 2] == UInt8('u') &&
        buf[pos + 3] == UInt8('e')
        return pos + 4, true
    elseif pos + 4 <= len &&
        b            == UInt8('f') &&
        buf[pos + 1] == UInt8('a') &&
        buf[pos + 2] == UInt8('l') &&
        buf[pos + 3] == UInt8('s') &&
        buf[pos + 4] == UInt8('e')
        return pos + 5, false
    else

    end
end

# null

# Bool

# Number

# String
function readstring(buf, pos, len, b)
    if b != UInt8('"')
        error = ExpectedOpeningQuoteChar
        @goto invalid
    end
    pos += 1
    spos = pos
    slen = 0
    escaped = false
    @nextbyte
    while b != UInt8('"')
        if b == UInt8('\\')
            # skip next character
            escaped = true
            pos += 2
        else
            pos += 1
            slen += 1
        end
        @nextbyte(false)
    end
    str = JString(buf, spos, slen)
    return pos + 1, (escaped ? JString(unescape(str)) : str)

@label invalid
    invalid(error, buf, pos, "string")
end

# object/array funcs
struct Funcs{A, B, C, D, E, F}
    objectinit::A
    objectkeyvalue::B
    objectfinalize::C
    arrayinit::D
    arrayvalue::E
    arrayfinalize::F
end

# Array

# Object
struct ObjectIterator{T <: AbstractVector{UInt8}}
    buf::T
    pos::Int # positioned at opening '{' of object
    len::Int

    function ObjectIterator(buf::T, pos=1, len=length(buf)) where {T <: AbstractVector{UInt8}}
        if pos > len
            invalid(UnexpectedEOF, buf, pos, "object")
        end
        b = getbyte(buf, pos)
        if b != UInt8('{')
            invalid(ExpectedOpeningObjectChar, buf, pos, "object")
        end
        return new{T}(buf, pos, len)
    end
end

Base.IteratorSize(::Type{<:ObjectIterator}) = Base.SizeUnknown()
Base.IteratorEltype(::Type{<:ObjectIterator}) = Base.EltypeUnknown()

@enum ParsingState KEY VALUE DONE

function Base.iterate(x::ObjectIterator)
    buf, pos, len = x.buf, x.pos, x.len
    pos += 1
    @nextbyte
    if b == UInt8('}')
        return nothing
    end
    return iterate(x, (pos, KEY))
@label invalid
    invalid(error, buf, pos, "object")
end

function Base.iterate(x::ObjectIterator, (pos, state))
    (state === DONE || pos > x.len) && return nothing
    buf, len = x.buf, x.len
    b = getbyte(buf, pos)
    if state === KEY
        if b != UInt8('"')
            error = ExpectedOpeningQuoteChar
            @goto invalid
        end
        # pos/b are at opening quote character (") of key-value pair of object
        pos, key = readstring(buf, pos, len, b)
        @nextbyte
        if b != UInt8(':')
            error = ExpectedSemiColon
            @goto invalid
        end
        pos += 1
        return key, (pos, VALUE)
    else
        # pos/b are at start of value of key-value pair of object
        pos, value = readvalue(funcs, buf, pos, len, b)
        @nextbyte
        newstate = KEY
        if b == UInt8('}')
            newstate = DONE
        elseif b != UInt8(',')
            error = ExpectedComma
            @goto invalid
        end
        return value, (pos, newstate)
    end

@label invalid
    invalid(error, buf, pos, "object")
end

function startreadobject()
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    x = funcs.objectinit(buf, pos)

end

function readobject(funcs, buf, pos, len, b)
    if b != UInt8('{')
        error = ExpectedOpeningObjectChar
        @goto invalid
    end
    x = funcs.objectinit(buf, pos)
    pos += 1ii7
    while true
        @nextbyte
        if b != UInt8('"')
            error = ExpectedOpeningQuoteChar
            @goto invalid
        end
        # pos/b are at opening quote character (") of key-value pair of object
        # @show pos, len, Char(b)
        pos, key = readstring(buf, pos, len, b)
        @nextbyte
        if b != UInt8(':')
            error = ExpectedSemiColon
            @goto invalid
        end
        pos += 1
        @nextbyte
        # pos/b are at start of value of key-value pair of object
        pos, value = readvalue(funcs, buf, pos, len, b)
        if funcs.objectkeyvalue(x, key, value) === true
            return pos, funcs.objectfinalize(x)
        end
        if b == UInt8('}')
            return pos + 1, funcs.objectfinalize(x)
        end
        if !first
            if b != UInt8(',')
                error = ExpectedComma
                @goto invalid
            end
            pos += 1
            @nextbyte
        else
            first = false
        end
    end

@label invalid
    invalid(error, buf, pos, "object")
end
