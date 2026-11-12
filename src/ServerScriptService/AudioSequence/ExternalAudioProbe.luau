--!strict
-- Verifies the hosted original MP3 from the server without treating it as RSEQ.
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Probe = {}
Probe.Url = "https://raw.githubusercontent.com/juhdevx/roblox-audio-test/760f07d383941d2c25a226ce8d5bff2aab2ff0fc/woahuseit.mp3"
local EXPECTED_BYTES = 2762429
local EXPECTED_ADLER32 = 2350210845
export type Result = {Success: boolean, StatusCode: number, Bytes: number, Checksum: number, Format: string}
function Probe.Run(): Result
	assert(not RunService:IsClient(), "HTTP probe must run on the server")
	local ok, response = pcall(function()
		return HttpService:RequestAsync({Url = Probe.Url, Method = "GET", Timeout = 10})
	end)
	assert(ok, `Audio download failed: {tostring(response)}`)
	assert(response.Success and response.StatusCode == 200, `HTTP {response.StatusCode}`)
	local data = response.Body
	assert(#data == EXPECTED_BYTES, "Hosted MP3 length differs from the original")
	assert(string.sub(data, 1, 3) == "ID3", "Expected the original ID3-tagged MP3")
	local a, b = 1, 0
	for first = 1, #data, 32768 do
		for index = first, math.min(first + 32767, #data) do
			a = (a + string.byte(data, index)) % 65521
			b = (b + a) % 65521
		end
		task.wait()
	end
	local checksum = b * 65536 + a
	assert(checksum == EXPECTED_ADLER32, "Hosted MP3 checksum differs from the original")
	local result: Result = {Success = true, StatusCode = response.StatusCode,
		Bytes = #data, Checksum = checksum, Format = "MP3/ID3"}
	script:SetAttribute("HttpVerified", true)
	script:SetAttribute("VerifiedBytes", #data)
	return result
end
return Probe

