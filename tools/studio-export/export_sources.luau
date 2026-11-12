-- Run in Studio's Command Bar (Edit mode, HTTP requests enabled) while
-- `py tools/studio-export/receive_sources.py` is listening. Sends every script's
-- source to the receiver, which mirrors them under src/ in the repository.
local HttpService = game:GetService("HttpService")
local URL = "http://127.0.0.1:8765/"
local ROOTS = {
	game.ServerScriptService, game.ServerStorage, game.ReplicatedStorage,
	game.ReplicatedFirst, game.StarterPlayer, game.StarterGui, game.Workspace,
}
local batch, sent = {}, 0
local function flush()
	if #batch == 0 then return end
	local ok, err = pcall(function()
		HttpService:PostAsync(URL, HttpService:JSONEncode(batch), Enum.HttpContentType.ApplicationJson)
	end)
	if not ok then error("export failed: " .. tostring(err)) end
	sent += #batch
	table.clear(batch)
	task.wait()
end
for _, root in ROOTS do
	for _, inst in root:GetDescendants() do
		if inst:IsA("LuaSourceContainer") then
			local hasChildren = false
			for _, child in inst:GetDescendants() do
				if child:IsA("LuaSourceContainer") then hasChildren = true; break end
			end
			table.insert(batch, {path = inst:GetFullName(), class = inst.ClassName, source = inst.Source, hasChildren = hasChildren})
			if #batch >= 25 then flush() end
		end
	end
end
flush()
print(("Exported %d scripts to %s"):format(sent, URL))
