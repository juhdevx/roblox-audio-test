--!strict
-- Defines the AuditDump admin command.
return {
	Name = "auditdump",
	Aliases = { "logs" },
	Description = "Dump the recent command audit logs to the console.",
	Group = "Admin",
	Args = {
		{ Type = "integer", Name = "count", Default = 25, Description = "Number of recent logs to retrieve." }
	},
}
