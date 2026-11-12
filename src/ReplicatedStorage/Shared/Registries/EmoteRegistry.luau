--!strict
-- Validates and indexes immutable emote definitions by their stable saved names.
local Shared = script.Parent.Parent
local TableUtils = require(Shared.Utils.TableUtils)
local RegistryLoader = require(Shared.Utils.RegistryLoader)
local MediaLibrary = require(Shared.Utils.MediaLibrary)
local byName = MediaLibrary.ApplyEmotes(RegistryLoader.Load(script.Parent.Emotes, "Name"), Shared:FindFirstChild("MediaLibrary"))
local ordered = {}
local lowerNames = {}
local orders = {}
for name, entry in pairs(byName) do
    assert(type(entry.Order) == "number" and not orders[entry.Order], `Invalid/duplicate order for {name}`)
    assert(type(entry.Loop) == "string" or (type(entry.Loop1) == "string" and type(entry.Loop2) == "string"), `Missing animation: {name}`)
    assert(not lowerNames[string.lower(name)], `Ambiguous name: {name}`)
    orders[entry.Order] = true
    lowerNames[string.lower(name)] = name
    -- Video emotes form their own category (wheel badge, giveall video, showvideo).
    entry.Video = (type(entry.Song) == "table" and type(entry.Song.Video) == "string") or nil
    TableUtils.Freeze(entry)
    table.insert(ordered, entry)
end
table.sort(ordered, function(a, b) return a.Order < b.Order end)
table.freeze(ordered)
local Registry = {}
function Registry.Get(name: string): any return byName[name] end
function Registry.All(): {any} return ordered end
function Registry.ResolveName(name: string): string? return lowerNames[string.lower(name)] end
local CATEGORIES = table.freeze({"all", "default", "exclusive", "video", "special", "gamepass", "syncable", "traversal"})
function Registry.Categories(): {string} return CATEGORIES end
function Registry.ByCategory(category: string): {string}
    local key = string.lower(category)
    local names = {}
    for _, entry in ordered do
        local keep = key == "all" or (key == "default" and entry.Default == true) or (key == "exclusive" and entry.Exclusive == true)
            or (key == "video" and entry.Video == true) or (key == "special" and entry.Special == true)
            or (key == "gamepass" and entry.Gamepass == true) or (key == "syncable" and entry.Syncable == true)
            or (key == "traversal" and entry.Traversal == true)
        if keep then table.insert(names, entry.Name) end
    end
    return names
end
function Registry.StarterNames(): {string}
    local names = {}
    for _, entry in ordered do if entry.Default and not entry.Exclusive then table.insert(names, entry.Name) end end
    return names
end
return table.freeze(Registry)

