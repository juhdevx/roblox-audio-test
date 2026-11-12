--!strict
-- Maps instrument numbers to authorized Roblox audio samples.
export type Sample = {
	AssetId: number,
	RootNote: number,
	Volume: number,
	Voices: number,
	Loop: boolean,
}
-- No asset is uploaded or selected implicitly. Example shape:
-- [0] = {AssetId = YOUR_AUTHORIZED_ID, RootNote = 60, Volume = 0.7, Voices = 8, Loop = false}
local samples: {[number]: Sample} = {}
return table.freeze(samples)
