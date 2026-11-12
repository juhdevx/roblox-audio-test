--!strict
-- Defines server-owned source URLs; clients can only request catalog IDs.
export type Entry = {Url: string?, Embedded: (() -> buffer)?}
local Catalog = {}
Catalog.AllowedHosts = table.freeze({
	["raw.githubusercontent.com"] = true,
	-- Add the exact project hostname for Supabase Storage, never a wildcard.
})
local DEMO = "52534551010028009e0000009a1bfbee0200e0010000f0420600000080070000000000000000000000000000040000003f000000003c640000e8020a003200647800e2e00340640000e8020a003200647800e2e00343640000e8020a003200647800e2e00348640000e8020a003200647800e201000000020000001f0000000024500100c8060a0032006478001ec0072b500100c8060a0032006478001e"
Catalog.Entries = {
	Demo = {Embedded = function(): buffer
		local data = buffer.create(#DEMO / 2)
		for index = 1, #DEMO, 2 do
			buffer.writeu8(data, (index - 1) / 2, tonumber(DEMO:sub(index, index + 1), 16) :: number)
		end
		return data
	end},
	-- MySong = {Url = "https://raw.githubusercontent.com/owner/repo/commit/song.rseq"},
} :: {[string]: Entry}
function Catalog.IsAllowed(url: string): boolean
	-- Reject credentials, ports, fragments and non-HTTPS schemes.
	local host, path = url:match("^https://([%w%.%-]+)(/[^#]*)$")
	return host ~= nil and path ~= nil and Catalog.AllowedHosts[host:lower()] == true
end
return Catalog
