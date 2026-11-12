--!strict
-- Central emote limits and synchronization policy used by server and client.
return table.freeze({
    MAX_SLOTS = 8, MAX_PARTICIPANTS = 10, SYNC_DISTANCE = 8, MAX_NAME_LENGTH = 64,
    RATE_TOKENS = 10, RATE_REFILL = 5, DEFAULT_TRAVERSAL_SPEED = 1,
    REQUIRE_EXCLUSIVE_SYNC_OWNERSHIP = true,
    FORMATION = table.freeze({V = 2.4, Line = 3, Circle = 3, Front = 2.5}),
})
