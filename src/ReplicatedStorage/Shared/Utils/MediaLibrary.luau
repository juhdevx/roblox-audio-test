--!strict
-- Loads bounded media definitions and merges their tracks and emotes without editing core registries.
local TableUtils = require(script.Parent.TableUtils)
local Library = {}
local MAX_ENTRIES = 128
local function validName(name: any): boolean
	return type(name) == "string" and #name >= 1 and #name <= 40 and name:match("^[%w_]+$") ~= nil
end
function Library.Read(folder: Instance?): {[string]: any}
	local entries: {[string]: any} = {}
	if not folder then return entries end
	assert(folder:IsA("Folder"), "MediaLibrary must be a Folder")
	local children = folder:GetChildren()
	assert(#children <= MAX_ENTRIES, "Too many media definition modules")
	table.sort(children, function(a, b) return a.Name < b.Name end)
	local count = 0
	for _, child in children do
		if not child:IsA("ModuleScript") then continue end
		local bundle = require(child)
		assert(type(bundle) == "table" and bundle.Version == 1 and type(bundle.Entries) == "table",
			`Invalid media bundle: {child:GetFullName()}`)
		for name, definition in bundle.Entries do
			count += 1
			assert(count <= MAX_ENTRIES and validName(name) and entries[name] == nil,
				`Invalid or duplicate media entry: {tostring(name)}`)
			assert(type(definition) == "table" and type(definition.Emote) == "table", `Missing emote settings: {name}`)
			assert(definition.Emote.ReplaceExisting == nil or type(definition.Emote.ReplaceExisting) == "boolean",
				`Invalid replacement policy: {name}`)
			entries[name] = TableUtils.Copy(definition)
		end
	end
	return entries
end
function Library.MergeTracks(base: {[string]: any}, folder: Instance?, kind: string): {[string]: any}
	assert(kind == "Audio" or kind == "Video", "Unknown media track kind")
	local merged = TableUtils.Copy(base)
	for name, definition in Library.Read(folder) do
		local track = definition[kind]
		if track == nil then continue end
		assert(type(track) == "table", `Invalid {kind} track: {name}`)
		assert(merged[name] == nil or definition.Emote.ReplaceExisting == true, `Media entry already exists: {name}`)
		merged[name] = TableUtils.Copy(track)
	end
	return merged
end
function Library.ApplyEmotes(base: {[string]: any}, folder: Instance?): {[string]: any}
	local merged = TableUtils.Copy(base)
	local nextOrder = 1
	for _, entry in merged do if type(entry.Order) == "number" then nextOrder = math.max(nextOrder, entry.Order + 1) end end
	local definitions = Library.Read(folder)
	local names = {}
	for name in definitions do table.insert(names, name) end
	table.sort(names)
	for _, name in names do
		local settings = definitions[name].Emote
		assert(merged[name] == nil or settings.ReplaceExisting == true, `Emote already exists: {name}`)
		local templateName = settings.Template or "PaniniEvent"
		assert(validName(templateName) and base[templateName], `Unknown emote template: {tostring(templateName)}`)
		local entry = TableUtils.Copy(base[templateName])
		for key, value in settings do
			if key ~= "Template" and key ~= "ReplaceExisting" then entry[key] = TableUtils.Copy(value) end
		end
		entry.Name = name
		entry.Order = if type(settings.Order) == "number" and settings.Order > 0 then settings.Order
			elseif merged[name] then merged[name].Order else nextOrder
		assert(entry.Order % 1 == 0 and entry.Order >= 1 and entry.Order <= 1000000, `Invalid emote order: {name}`)
		nextOrder = math.max(nextOrder, entry.Order + 1)
		assert(type(entry.Song) == "table" and entry.Song.Backend == "Spectral" and validName(entry.Song.Track),
			`Invalid media song: {name}`)
		assert(entry.Song.Video == nil or validName(entry.Song.Video), `Invalid media video: {name}`)
		merged[name] = entry
	end
	return merged
end
return Library
