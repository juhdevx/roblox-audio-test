--!strict
-- Selects energetic source trajectories for small voice pools without altering source pitch, pan or phase.
local Shared = game:GetService("ReplicatedStorage").Shared.SpectralAudio
local Format = require(Shared.Format)

export type Settings = {
	Enabled: boolean, AdaptiveMaxVoices: number, CadenceSeconds: number, MinHoldSeconds: number,
	ReplacementRatio: number, MinimumEnergyShare: number, LookaheadWeight: number,
	MinHz: number, MaxHz: number,
}
type State = {Slot: number, Pending: number, Stage: number, Born: number, Restart: boolean}
local VoiceSelection = {}
VoiceSelection.__index = VoiceSelection

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end
local function descending(self: any, a: number, b: number): boolean
	local x, y = self.Scores[a + 1], self.Scores[b + 1]
	return if x == y then a < b else x > y
end
function VoiceSelection.new(settings: Settings)
	local self = setmetatable({
		Settings = settings, States = {} :: {State}, Scores = {} :: {number}, Ranking = {} :: {number},
		Owned = {} :: {[number]: boolean}, SourceCount = 0, Budget = 0, FPS = 0,
		LastFrame = -1, LastScan = -math.huge, Adaptive = false, Destroyed = false,
		Swaps = 0, Scans = 0, Resets = 0,
		Sort = nil :: ((number, number) -> boolean)?,
	}, VoiceSelection)
	self.Sort = function(a, b) return descending(self, a, b) end
	return self
end
export type Selector = typeof(VoiceSelection.new({} :: Settings))

-- Reset releases assignments; the renderer owns and silences the actual carriers.
function VoiceSelection.Reset(self: Selector)
	self.SourceCount = 0; self.Budget = 0; self.FPS = 0
	self.LastFrame = -1; self.LastScan = -math.huge; self.Adaptive = false
	for _, state in self.States do
		state.Pending = -1; state.Stage = 0; state.Born = -math.huge; state.Restart = false
	end
	table.clear(self.Owned)
	self.Resets += 1
end
local function scan(self: Selector, first: buffer, firstFrame: number, second: buffer,
	secondFrame: number, fraction: number, rate: number): number
	local total = 0
	local settings = self.Settings
	for slot = 0, self.SourceCount - 1 do
		local hz0, amp0 = Format.Read(first, firstFrame, slot, self.SourceCount)
		local hz1, amp1 = Format.Read(second, secondFrame, slot, self.SourceCount)
		local hz = (if hz0 > 0 and hz1 > 0 then hz0 * (hz1 / hz0) ^ fraction else math.max(hz0, hz1)) * rate
		local energy = 0
		if finite(hz) and finite(amp0) and finite(amp1) and hz >= settings.MinHz and hz <= settings.MaxHz then
			energy = (1 - settings.LookaheadWeight) * amp0 * amp0 + settings.LookaheadWeight * amp1 * amp1
		end
		self.Scores[slot + 1] = energy
		self.Ranking[slot + 1] = slot
		total += energy
	end
	local sort = self.Sort
	assert(sort ~= nil)
	table.sort(self.Ranking, sort)
	self.Scans += 1
	return total
end

-- Returns true when existing carriers must be stopped before reading the new assignment map.
-- No scan, sort or scratch allocation occurs for fixed-prefix and full-identity profiles.
function VoiceSelection.Update(self: Selector, first: buffer, firstFrame: number, second: buffer,
	secondFrame: number, fraction: number, sourceCount: number, budget: number, fps: number,
	absoluteFrame: number, playbackRate: number): boolean
	assert(not self.Destroyed, "Voice selector is destroyed")
	local configured = self.SourceCount > 0
	local changed = sourceCount ~= self.SourceCount or budget ~= self.Budget or fps ~= self.FPS
	local jumped = configured and absoluteFrame < self.LastFrame
	local reset = changed or jumped
	if reset then
		self:Reset()
		self.SourceCount = sourceCount; self.Budget = budget; self.FPS = fps
		self.Adaptive = self.Settings.Enabled and budget > 0 and budget < sourceCount
			and budget <= self.Settings.AdaptiveMaxVoices
		if self.Adaptive then
			-- Resize only when a source bank changes; frame updates reuse these arrays.
			for index = #self.Ranking, sourceCount + 1, -1 do
				self.Ranking[index] = nil; self.Scores[index] = nil
			end
			for index = #self.States + 1, budget do
				self.States[index] = {Slot = index - 1, Pending = -1, Stage = 0, Born = -math.huge, Restart = false}
			end
			scan(self, first, firstFrame, second, secondFrame, fraction, playbackRate)
			for index = 1, budget do
				local state = self.States[index]
				state.Slot = self.Ranking[index]; state.Pending = -1; state.Stage = 0
				state.Born = -math.huge; state.Restart = false
			end
			self.LastScan = absoluteFrame
		end
	end
	if not self.Adaptive then self.LastFrame = absoluteFrame; return configured and reset end
	local newFrame = absoluteFrame ~= self.LastFrame
	local holdFrames = math.ceil(self.Settings.MinHoldSeconds * fps * playbackRate)
	for index = 1, budget do
		local state = self.States[index]
		state.Restart = false
		if newFrame and not reset then
			if state.Stage == 1 then
				state.Slot = state.Pending; state.Pending = -1; state.Stage = 2; state.Born = absoluteFrame
				state.Restart = true; self.Swaps += 1
			elseif state.Stage == 2 then state.Stage = 0 end
		end
	end
	local cadence = math.max(1, math.ceil(self.Settings.CadenceSeconds * fps * playbackRate))
	if newFrame and not reset and absoluteFrame - self.LastScan >= cadence then
		local total = scan(self, first, firstFrame, second, secondFrame, fraction, playbackRate)
		self.LastScan = absoluteFrame
		local owned = self.Owned
		table.clear(owned)
		for index = 1, budget do
			local state = self.States[index]
			owned[state.Slot] = true
			if state.Pending >= 0 then owned[state.Pending] = true end
		end
		for _, candidate in self.Ranking do
			local energy = self.Scores[candidate + 1]
			if energy <= 0 or energy < total * self.Settings.MinimumEnergyShare then break end
			if owned[candidate] then continue end
			local weakest: State? = nil
			for index = 1, budget do
				local state = self.States[index]
				if state.Stage == 0 and absoluteFrame - state.Born >= holdFrames
					and (weakest == nil or self.Scores[state.Slot + 1] < self.Scores[weakest.Slot + 1]) then
					weakest = state
				end
			end
			if weakest == nil then break end
			if energy <= self.Scores[weakest.Slot + 1] * self.Settings.ReplacementRatio then break end
			weakest.Pending = candidate; weakest.Stage = 1; owned[candidate] = true
		end
	end
	self.LastFrame = absoluteFrame
	return configured and reset
end

-- Source slots are zero-based. Restart must clear the old carrier before any new pitch is assigned.
function VoiceSelection.Get(self: Selector, index: number, fraction: number): (number, number, boolean)
	if not self.Adaptive then return index - 1, 1, false end
	local state = self.States[index]
	local gate = if state.Stage == 1 then 1 - fraction elseif state.Stage == 2 then fraction else 1
	return state.Slot, math.clamp(gate, 0, 1), state.Restart
end
function VoiceSelection.Destroy(self: Selector)
	if self.Destroyed then return end
	self:Reset(); self.Destroyed = true
	table.clear(self.States); table.clear(self.Scores); table.clear(self.Ranking)
	self.Sort = nil
end
return VoiceSelection
