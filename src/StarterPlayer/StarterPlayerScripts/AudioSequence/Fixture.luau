--!strict
-- Provides a Python-generated reference file and a bounded large-file test fixture.
local Shared=game.ReplicatedStorage.Shared.AudioSequence
local Format=require(Shared.Format)
local Checksum=require(Shared.Checksum)
local Fixture={}
Fixture.SmallChecksum=4009434010
Fixture.LargeChecksum=1312460576
Fixture.Track2Offset=115
local HEX="52534551010028009e0000009a1bfbee0200e0010000f0420600000080070000000000000000000000000000040000003f000000003c640000e8020a003200647800e2e00340640000e8020a003200647800e2e00343640000e8020a003200647800e2e00348640000e8020a003200647800e201000000020000001f0000000024500100c8060a0032006478001ec0072b500100c8060a0032006478001e"
function Fixture.Small(): buffer
    local data=buffer.create(#HEX/2)
    for offset=0,buffer.len(data)-1 do buffer.writeu8(data,offset,assert(tonumber(string.sub(HEX,offset*2+1,offset*2+2),16))) end
    return data
end
function Fixture.Seal(data: buffer)
    local a,b=Checksum.Update(data,0,buffer.len(data),1,0)
    buffer.writeu32(data,12,Checksum.Finish(a,b))
end
function Fixture.Large(yieldFrame: ()->()): buffer
    local count=16384
    local size=52+count*14
    local data=buffer.create(size)
    buffer.writeu32(data,0,Format.MAGIC);buffer.writeu16(data,4,1);buffer.writeu16(data,6,40)
    buffer.writeu32(data,8,size);buffer.writeu16(data,16,1);buffer.writeu16(data,18,480)
    buffer.writef32(data,20,120);buffer.writeu32(data,24,count);buffer.writeu32(data,28,count*120+96)
    buffer.writeu32(data,44,count);buffer.writeu32(data,48,count*14)
    local event=buffer.create(14)
    buffer.writeu8(event,0,120);buffer.writeu8(event,1,60);buffer.writeu8(event,2,90)
    buffer.writeu8(event,5,96);buffer.writeu16(event,6,10);buffer.writeu16(event,8,50)
    buffer.writeu8(event,10,100);buffer.writeu16(event,11,120)
    for i=0,count-1 do
        buffer.copy(data,52+i*14,event)
        if i%2048==2047 then yieldFrame() end
    end
    local a,b=1,0
    for offset=0,size-1,Format.CHECKSUM_BATCH_BYTES do
        a,b=Checksum.Update(data,offset,math.min(Format.CHECKSUM_BATCH_BYTES,size-offset),a,b)
        yieldFrame()
    end
    buffer.writeu32(data,12,Checksum.Finish(a,b))
    return data
end
return table.freeze(Fixture)

