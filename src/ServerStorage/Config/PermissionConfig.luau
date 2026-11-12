--!strict
-- Defines server-only administrator identities and explicitly allowed command groups.
-- Tiers: 0 User, 1 Moderator, 2 Staff, 3 Owner. Ranks given with the `rank` command persist (DataStore Ranks_v1).
return {
    Owners = {1803582764}, Staff = {}, Moderators = {},
    -- Minimum tier per command group (Cmdr `Group`). Groups without a rule are blocked.
    GroupMinimumTier = {Help=0, Emote=2, Media=2, Staff=3, Admin=2, DefaultAdmin=2, DefaultDebug=2, DefaultUtil=1},
    -- Per-command overrides (always the stricter of group/command).
    CommandMinimumTier = {auditdump=3, rank=3, unrank=3, ban=3, unban=3, gotoplace=3, takeall=3},
}
