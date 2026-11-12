--!strict
-- Spawns an attached animated dummy using a separately managed avatar pool.
local ServerStorage = game:GetService("ServerStorage")
local GetVFXFolder = require(game:GetService("ReplicatedStorage").Shared.Utils.GetVFXFolder)
local FriendAvatarPool = require(script.Parent.Parent.FriendAvatarPool)
local DummySpawner = {}
function DummySpawner.Start(player: Player, character: Model, params: any)
	-- NOVO: valida params
	if type(params) ~= "table" then return nil end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local dummyTemplate = ServerStorage.Assets.EmoteEffects:FindFirstChild(params.DummyName or "EffectDummy") or ServerStorage:FindFirstChild(params.DummyName or "EffectDummy")
	if not dummyTemplate then return nil end

	local dummy = dummyTemplate:Clone()
	dummy.Name = "Effect_" .. character.Name

	for _, part in ipairs(dummy:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Anchored = false
			part.Massless = true
		end
	end

	local dRoot = dummy:FindFirstChild("HumanoidRootPart")
	if dRoot then
		dRoot.CFrame = root.CFrame * (params.Offset or CFrame.new())
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = dRoot
		weld.Part1 = root
		weld.Parent = dRoot
	end

	-- NOVO: pcall no GetVFXFolder (pode falhar se não estiver pronto)
	local vfxOk, vfxParent = pcall(GetVFXFolder)
	if not vfxOk or not vfxParent then
		warn("[DummySpawner] GetVFXFolder falhou, usando workspace")
		vfxParent = workspace
	end
	dummy.Parent = vfxParent

	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator")
		or Instance.new("Animator", humanoid))
	local track: AnimationTrack? = nil

	if animator and params.AnimationId then
		local anim = Instance.new("Animation")
		anim.AnimationId = params.AnimationId
		-- NOVO: pcall no LoadAnimation
		local ok, loadedTrack = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		anim:Destroy()
		if ok and loadedTrack then
			track = loadedTrack
			task.spawn(function()
				if params.Delay and params.Delay > 0 then
					task.wait(params.Delay)
				end
				if dummy.Parent and track then
					-- NOVO: pcall no Play
					pcall(function()
						track:Play()
						track.Looped = params.Looped or false
					end)
				end
			end)
		end
	end

	if humanoid then
        task.spawn(function()
            local description = FriendAvatarPool.GetDescription(player)
            if description then
                if dummy.Parent then pcall(function() humanoid:ApplyDescription(description) end) end
                description:Destroy()
            end
        end)
    end

	-- NOVO: guard no task.delay do Duration
	if params.Duration then
		task.delay(params.Duration, function()
			if dummy and dummy.Parent then
				dummy:Destroy()
			end
		end)
	end

	return {
		Instance = dummy,
		Track = track,
	}
end

function DummySpawner.Stop(state: any)
	if not state then return end
	if state.Track then
		pcall(function() state.Track:Stop() end)
	end
	if state.Instance and state.Instance.Parent then
		state.Instance:Destroy()
	end
end


return DummySpawner
