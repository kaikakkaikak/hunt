-- Config holds the game-specific values. Edit this file when the boss names
-- and the game's auto button are known; nothing else needs to change.
return {
    Name = "Config",
    Dependencies = {},

    Start = function()
        return {
            Name = "Config",

            --// The bosses' model names in workspace, as shown in the
            --// selection list. Only one can be selected at a time.
            BOSS_NAMES = {
                "Whitefang Sabertooth",
                "Obsidian Pharaoh",
                "Tempest Dragon King",
                "Volcano Turtle King",
            },

            --// Only a model with a living Humanoid counts as the boss, so a
            --// same-named marker (like the boss timer) is not mistaken for it.
            BOSS_REQUIRE_HUMANOID = true,

            --// The spawn timers in workspace, matched by name (case-insensitive)
            --// and counted in workspace:GetDescendants() order.
            BOSS_TIMER_NAME = "bosstimer",
            --// Boss name -> which of those timers is its own.
            BOSS_TIMERS = {
                ["Obsidian Pharaoh"] = 3,
                --// Assumed from the zone number (Boss02 -> 2, ...); check
                --// with tools/DumpBossTimer.lua.
                ["Whitefang Sabertooth"] = 2,
                ["Tempest Dragon King"] = 4,
                ["Volcano Turtle King"] = 5,
            },
            --// Stay when a selected boss spawns within this; hop otherwise.
            BOSS_WAIT_MAX_SECONDS = 30,
            --// While waiting, how long past the timer the boss may take to show.
            BOSS_SPAWN_GRACE = 10,

            --// Where bosses are looked for (searched with GetDescendants).
            --// Narrow it, e.g. workspace:FindFirstChild("Enemies"), once known.
            GetBossRoot = function()
                return workspace
            end,

            --// TODO: the game's own auto-fight button in PlayerGui, matched by
            --// instance Name or by its text (case-insensitive).
            AUTO_BUTTON_NAMES = { "Auto", "AutoButton", "AutoFight" },
            AUTO_BUTTON_TEXTS = { "AUTO" },

            --// Boss name -> the zone walked to before every look for it.
            BOSS_ZONES = {
                ["Whitefang Sabertooth"] = "Boss02",
                ["Obsidian Pharaoh"] = "Boss03",
                ["Tempest Dragon King"] = "Boss04",
                ["Volcano Turtle King"] = "Boss05",
            },
            --// Within this many studs of the zone counts as arrived.
            ZONE_ARRIVE_DISTANCE = 10,
            --// A walk gives up after this and is tried again from there.
            ZONE_WALK_TIMEOUT = 60,
            --// This many failed walks in a row: hop instead of fighting from
            --// somewhere that is not the boss's spawn point.
            WALK_FAILS_BEFORE_HOP = 3,

            --// After the boss dies, keep the game's auto on this long to
            --// pick up the drops.
            LOOT_WAIT_SECONDS = 3,
            --// The boss taking damage and then none for this long means the
            --// game turned its auto off: press the auto button again.
            AUTO_STALL_SECONDS = 8,

            --// After joining a server, wait this long for the map and bosses
            --// to load before the first scan.
            JOIN_SETTLE_SECONDS = 6,
            --// A server counts as "no boss" only after this many empty scans.
            SCAN_TRIES = 3,
            SCAN_INTERVAL = 2,
            --// How often a fight checks whether the boss is still alive.
            WATCH_INTERVAL = 1,
            --// A hop that failed (no server, list unreadable) tries again after this.
            HOP_RETRY_DELAY = 5,
            --// A teleport still not done after this is given up and retried.
            TELEPORT_TIMEOUT = 30,

            --// Server list: pages read per hop at most (100 servers each),
            --// stopping early once this many unvisited roomy servers are in.
            HOP_MAX_PAGES = 4,
            HOP_POOL_TARGET = 40,
            --// Servers with at least this many free slots are preferred.
            HOP_FREE_SLOTS = 2,
            --// After a rate limit (HTTP 429) the next try waits this long,
            --// doubling up to HOP_RATE_LIMIT_MAX.
            HOP_RATE_LIMIT_DELAY = 15,
            HOP_RATE_LIMIT_MAX = 60,

            --// Server memory (ServerMemory): how long a server left is not
            --// hopped back to.
            --// How often a boss respawns after it dies.
            BOSS_RESPAWN_SECONDS = 600,
            --// A timer below this right after a kill has not reset yet.
            SPAWN_TIMER_MIN_SECONDS = 30,
            --// With a known spawn time: banned until this long before it.
            SPAWN_LEAD_SECONDS = 60,
            --// Never banned for less than this.
            BAN_MIN_SECONDS = 120,
            --// Spawn time unknown (no timer, did not spawn, walk failed).
            BAN_UNKNOWN_SECONDS = 300,
            --// Someone camps the boss there.
            BAN_CAMPED_SECONDS = 1800,
            --// A teleport there failed (full, closed).
            BAN_UNJOINABLE_SECONDS = 120,
            MEMORY_MAX_SERVERS = 200,

            --// Spawn targets: a remembered server whose boss spawns within
            --// this window is joined instead of a random one, and waited on
            --// for up to TARGET_WAIT_MAX_SECONDS there.
            SPAWN_TARGET_MIN_SECONDS = 25,
            SPAWN_TARGET_MAX_SECONDS = 120,
            TARGET_WAIT_MAX_SECONDS = 150,

            --// Campers (CamperCheck): someone within CAMPER_RADIUS studs of
            --// the boss zone who moved no more than CAMPER_MOVE_TOLERANCE in
            --// CAMPER_IDLE_SECONDS. With no boss alive the server is left
            --// at once; with one alive it is fought anyway.
            CAMPER_CHECK = true,
            CAMPER_RADIUS = 40,
            CAMPER_IDLE_SECONDS = 8,
            CAMPER_MOVE_TOLERANCE = 6,
            --// A camper is recognised on join for this long.
            CAMPER_MEMORY_SECONDS = 6 * 3600,
        }
    end,
}
