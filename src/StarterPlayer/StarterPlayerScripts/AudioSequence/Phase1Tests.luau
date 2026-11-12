--!strict
-- Exercises parser correctness, malformed input rejection, and bounded large decoding.
local Shared = game.ReplicatedStorage.Shared.AudioSequence
local Parser = require(Shared.Parser)
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local Fixture = require(script.Parent.Fixture)
export type Report = {Passed: number, Failures: {string}, MaximumStepMs: number, LargeBytes: number}
local Tests = {}

function Tests.Run(yieldFrame: () -> ()): Report
    local report: Report = {Passed = 0, Failures = {}, MaximumStepMs = 0, LargeBytes = 0}
    local function check(condition: boolean, name: string)
        if condition then report.Passed += 1 else table.insert(report.Failures, name) end
    end
    local function decode(data: buffer): (Types.Sequence?, string?)
        local job, issue = Parser.Begin(data)
        if not job then return nil, issue end
        for _ = 1, 1024 do
            local before = job.EventIndex
            local started = os.clock()
            local done, err = Parser.Step(job, 256)
            report.MaximumStepMs = math.max(report.MaximumStepMs, (os.clock() - started) * 1000)
            assert(job.EventIndex - before <= 256, "Decoder exceeded batch budget")
            if done then
                local result = Parser.Result(job)
                Parser.Destroy(job)
                return result, err
            end
            yieldFrame()
        end
        Parser.Destroy(job)
        return nil, "Decoder did not terminate"
    end
    local small = Fixture.Small()
    local result, err = decode(small)
    check(result ~= nil and err == nil, "Reference file accepted")
    if result then
        check(result.Metadata.Checksum == Fixture.SmallChecksum, "Independent Python checksum")
        check(result.Metadata.TrackCount == 2 and result.Metadata.EventCount == 6, "Header counts")
        check(buffer.readu32(result.Events, 0) == 0 and buffer.readu8(result.Events, 8) == 60, "First note")
        check(buffer.readu32(result.Events, 3 * 40) == 1440, "Multi-byte delta varint")
        check(buffer.readu32(result.Events, 4 * 40) == 0 and buffer.readu16(result.Events, 4 * 40 + 32) == 1, "Per-track time reset")
        check(buffer.readu32(result.Tracks, 16) == 4 and buffer.readu32(result.Tracks, 20) == 2, "Track index")
        check(math.abs(buffer.readf32(result.Events, 28) + 30 / 127) < 0.00001, "Signed pan")
        check(math.abs(buffer.readf32(result.Events, 12) - 0.01) < 0.00001, "ADSR units")
    end
    local function reject(name: string, mutate: (buffer) -> (), reseal: boolean?)
        local data = Fixture.Small()
        mutate(data)
        if reseal then Fixture.Seal(data) end
        local decoded, failure = decode(data)
        check(decoded == nil and failure ~= nil, name)
    end
    reject("Magic rejected", function(b) buffer.writeu8(b, 0, 0) end)
    reject("Version rejected", function(b) buffer.writeu16(b, 4, 99) end)
    reject("Size mismatch rejected", function(b) buffer.writeu32(b, 8, 1) end)
    reject("CRC corruption rejected", function(b) buffer.writeu8(b, 53, 61) end)
    reject("NaN BPM rejected", function(b) buffer.writeu32(b, 20, 0x7FC00000) end, true)
    reject("Oversized counts rejected", function(b) buffer.writeu32(b, 24, 0xFFFFFFFF) end, true)
    reject("Header flags rejected", function(b) buffer.writeu32(b, 32, 1) end, true)
    reject("Note range rejected", function(b) buffer.writeu8(b, 53, 128) end, true)
    reject("Velocity zero rejected", function(b) buffer.writeu8(b, 54, 0) end, true)
    reject("Instrument range rejected", function(b) buffer.writeu16(b, 55, 256) end, true)
    reject("Duration zero rejected", function(b) buffer.writeu8(b, 57, 0) end, true)
    reject("Envelope rejected", function(b) buffer.writeu16(b, 59, 65535) end, true)
    reject("Pan rejected", function(b) buffer.writei8(b, 66, -128) end, true)
    reject("Duplicate track ID rejected", function(b) buffer.writeu16(b, Fixture.Track2Offset, 0) end, true)
    reject("Track payload bounds rejected", function(b) buffer.writeu32(b, 48, 0xFFFFFFFF) end, true)
    reject("Overlong varint rejected", function(b)
        for i = 52, 55 do buffer.writeu8(b, i, 128) end
    end, true)
    reject("Noncanonical varint rejected", function(b)
        buffer.writeu8(b, 52, 128); buffer.writeu8(b, 53, 0)
    end, true)
    local tiny, tinyError = Parser.Begin(buffer.create(8))
    check(tiny == nil and tinyError ~= nil, "Truncated header rejected")
    local large = Fixture.Large(yieldFrame)
    report.LargeBytes = buffer.len(large)
    check(buffer.readu32(large, 12) == Fixture.LargeChecksum, "Large Python checksum matches")
    local decodedLarge = decode(large)
    check(decodedLarge ~= nil and decodedLarge.Metadata.EventCount == 16384, "Large file decoded")
    if decodedLarge then
        check(buffer.readu32(decodedLarge.Events, 16383 * Format.EVENT_BYTES) == 16384 * 120, "Last large tick")
    end
    local disposable = assert(Parser.Begin(Fixture.Small()))
    Parser.Destroy(disposable)
    local done, destroyedError = Parser.Step(disposable)
    check(done and destroyedError ~= nil and Parser.Result(disposable) == nil, "Destroyed decoder rejected")
    return report
end
return table.freeze(Tests)
