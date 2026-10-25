-- Config holds the game-specific values. Edit this file when the boss names
-- and the game's auto button are known; nothing else needs to change.
return {
    Name = "Config",
    Dependencies = {},

    Start = function()
        return {
            Name = "Config",

            --// The bosses' model names in workspace, as shown in the
            --// selection list.
            BOSS_NAMES = {
                "Obsidian Pharaoh",
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
        }
    end,
}
