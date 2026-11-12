--!strict
-- Resolves the shared effect container lazily.
local Workspace = game:GetService("Workspace")

local folder = nil

local function GetVFXFolder()
	if folder and folder.Parent then
		return folder
	end

	folder = Workspace:FindFirstChild("VFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "VFX"
		folder.Parent = Workspace
	end

	return folder
end

return GetVFXFolder
