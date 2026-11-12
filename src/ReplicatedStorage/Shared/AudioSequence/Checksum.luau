--!strict
local Format = require(script.Parent.Format)
local MODULUS = 65521
local Checksum = {}
function Checksum.Update(data: buffer, offset: number, count: number, a: number, b: number): (number, number)
    assert(offset >= 0 and count >= 0 and offset + count <= buffer.len(data), "Checksum range")
    for position = offset, offset + count - 1 do
        local value = if position >= Format.CHECKSUM_OFFSET and position < Format.CHECKSUM_OFFSET + 4
            then 0 else buffer.readu8(data, position)
        a = (a + value) % MODULUS
        b = (b + a) % MODULUS
    end
    return a, b
end
function Checksum.Finish(a: number, b: number): number
    return b * 65536 + a
end
return table.freeze(Checksum)
