--!strict
-- Derives bounded phase-consistent oscillator frequencies from existing spectral frames.
local PhaseTracking = {}
local MIN_PHASE_AMPLITUDE = 0.0001
local DEFAULT_CORRECTION_RATIO = 0.04
local PITCH_STEP_RATIO = 1.08

local function isFinite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function interpolate(hz0: number, hz1: number, fraction: number): number
	if hz0 > 0 and hz1 > 0 then return hz0 * (hz1 / hz0) ^ fraction end
	return math.max(hz0, hz1)
end

local function integratedCycles(hz0: number, hz1: number, fps: number, fraction: number): number
	local logRatio = math.log(hz1 / hz0)
	if math.abs(logRatio) < 0.000001 then return hz0 * fraction / fps end
	return hz0 * ((hz1 / hz0) ^ fraction - 1) / (logRatio * fps)
end

-- Returns source Hz and its constant phase correction; multiply Hz by playback rate afterwards.
function PhaseTracking.InterpolateHz(hz0: number, hz1: number, phase0: number, phase1: number,
	fps: number, fraction: number, amp0: number, amp1: number, pan0: number?, pan1: number?,
	enabled: boolean?, maxCorrectionRatio: number?, pitchStepRatio: number?): (number, number)
	local blend = math.clamp(fraction, 0, 1)
	local hz = interpolate(hz0, hz1, blend)
	if enabled == false or hz0 <= 0 or hz1 <= 0 or fps <= 0
		or amp0 < MIN_PHASE_AMPLITUDE or amp1 < MIN_PHASE_AMPLITUDE
		or not isFinite(hz0) or not isFinite(hz1) or not isFinite(phase0)
		or not isFinite(phase1) or not isFinite(fps) then return hz, 0 end
	if pan0 ~= nil and pan1 ~= nil and (pan0 > 0) ~= (pan1 > 0) then return hz, 0 end
	local continuityRatio = pitchStepRatio or PITCH_STEP_RATIO
	if not isFinite(continuityRatio) then continuityRatio = PITCH_STEP_RATIO end
	continuityRatio = math.max(1, continuityRatio)
	if math.max(hz0, hz1) / math.min(hz0, hz1) > continuityRatio
		and math.abs(hz1 - hz0) > 18 then return hz, 0 end
	local limit = maxCorrectionRatio or DEFAULT_CORRECTION_RATIO
	if not isFinite(limit) then limit = DEFAULT_CORRECTION_RATIO end
	limit = math.clamp(limit, 0, DEFAULT_CORRECTION_RATIO) * math.min(hz0, hz1)
	local expected = integratedCycles(hz0, hz1, fps, 1)
	local phaseError = (phase1 - phase0 - expected + 0.5) % 1 - 0.5
	local correction = math.clamp(phaseError * fps, -limit, limit)
	return hz + correction, correction
end

-- Returns phase cycles at the selected source position before carrier phase/launch-lead offsets.
function PhaseTracking.BirthCycles(hz0: number, hz1: number, phase0: number, phase1: number,
	fps: number, fraction: number, amp0: number, amp1: number, correctionHz: number?): number
	if fps <= 0 or not isFinite(fps) then return 0 end
	local blend = math.clamp(fraction, 0, 1)
	local phase: number
	if amp0 > 0 and hz0 > 0 then
		if hz1 > 0 and amp1 > 0 then
			phase = phase0 + integratedCycles(hz0, hz1, fps, blend)
				+ (correctionHz or 0) * blend / fps
		else
			phase = phase0 + hz0 * blend / fps
		end
	else
		phase = phase1 - math.max(hz1, 0) * (1 - blend) / fps
	end
	return if isFinite(phase) then phase % 1 else 0
end

-- Rejects invalid configuration values and shares the same rate limits with the controller.
function PhaseTracking.SanitizeRate(value: any, minimum: number?, maximum: number?): number
	local lower = minimum or 0.25
	local upper = maximum or 2
	if not isFinite(lower) or not isFinite(upper) or lower <= 0 or upper < lower then
		lower = 0.25; upper = 2
	end
	if typeof(value) ~= "number" or not isFinite(value) or value <= 0 then return math.clamp(1, lower, upper) end
	return math.clamp(value, lower, upper)
end

return table.freeze(PhaseTracking)

