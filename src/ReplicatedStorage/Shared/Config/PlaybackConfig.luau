--!strict
-- Preserves animation, audio, and after-image timing defaults.
return {
	SyncCorrectionInterval = 2.5,
	SyncDriftThreshold = 0.35,
	SyncInitialCorrectionDelay = 0.2,
	SoundFolder = game:GetService("ReplicatedStorage").Assets.Sounds,
	AfterImageBeatInterval = 0.4,
	AfterImageFadeDuration = 0.35,
	AfterImageGrowScale = 1.15,
	AfterImageStartTransparency = 0.5,
	AfterImageEndTransparency = 1,
	RemoteSoundPollInterval = 0.5,
	RemoteSoundStaleGrace = 3,
	-- NOVO: throttle do PreRender check
	ValidateEveryNFrames = 3,
}
