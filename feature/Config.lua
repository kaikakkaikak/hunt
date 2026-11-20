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
            --// The game's auto taking over a walk (left on from before the
            --// hop) is pressed off and the walk retried this many times per
            --// server before such walks count as failed.
            AUTO_OFF_TRIES = 2,

            --// After the boss dies, keep the game's auto on this long to
            --// pick up the drops.
            LOOT_WAIT_SECONDS = 3,
            --// The boss taking damage and then none for this long means the
            --// game turned its auto off: press the auto button again.
            AUTO_STALL_SECONDS = 8,
            --// After pressing auto in a fight, our character must move, turn
            --// or the boss take damage within this; otherwise the press is
            --// taken to have turned auto off and is made again, up to
            --// AUTO_CONFIRM_TRIES times (2: on -> off -> on at worst).
            AUTO_CONFIRM_SECONDS = 5,
            AUTO_CONFIRM_TRIES = 2,
            --// Our character moving this far (X and Z) counts as the auto working.
            AUTO_ACTIVE_MOVE = 3,

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

            ------------------------------------------------------------------
            --// AutoDungeon. Names marked TODO: check with tools/DumpDungeon.lua.
            ------------------------------------------------------------------

            --// The dungeon's folder in workspace; everything is looked for in it.
            DUNGEON_ROOT_NAME = "Halloween",
            --// Names match ignoring case, spaces, "_" and "-". The pillar is
            --// looked for in all of workspace: there = standing.
            DUNGEON_PILLAR_NAMES = { "Ritual Pillar" },
            --// Only these are fought as monsters (empty: any Humanoid that
            --// is not a player).
            DUNGEON_MOB_NAMES = { "Sheet Ghost", "Skull Bat", "Zombie Scarecrow", "Bone Hound" },
            --// The miniboss and the boss: their skills are dodged. A name
            --// with a keyword in it counts too.
            DUNGEON_MAJOR_NAMES = { "Potion Witch", "Skull King" },
            DUNGEON_MAJOR_KEYWORDS = { "boss" },
            --// The boss door's ProximityPrompt: one whose name, texts,
            --// parent's or grandparent's name have a keyword in it (empty:
            --// any prompt).
            DUNGEON_DOOR_KEYWORDS = { "stone door", "stonedoor", "door" },
            --// Rooms flown into when nothing is in sight (monsters spawn
            --// only once someone gets there): things in the dungeon's folder
            --// named with one of ROOM_NAMES, or with ROOM_KEYWORDS while
            --// that is empty. Arrived within ROOM_ARRIVE studs; then wait
            --// up to ROOM_WAIT seconds for monsters.
            DUNGEON_ROOM_NAMES = {},
            DUNGEON_ROOM_KEYWORDS = { "room", "spawn", "trigger", "wave", "stage", "area" },
            DUNGEON_ROOM_ARRIVE = 8,
            DUNGEON_ROOM_WAIT = 3,
            DUNGEON_ROOM_MAX = 40,
            --// A room skipped this many times is dropped for good.
            DUNGEON_ROOM_GIVE_UP_SKIPS = 2,
            --// Boxes: any prompt in the dungeon that is not the door, unless
            --// LOOT_KEYWORDS names them; never one with a SKIP keyword (a
            --// way out). Each is tried at most LOOT_TRIES times.
            DUNGEON_LOOT_KEYWORDS = {},
            DUNGEON_LOOT_SKIP_KEYWORDS = { "leave", "exit", "return", "lobby", "teleport", "quit" },
            DUNGEON_LOOT_TRIES = 3,
            --// Only boxes this close are flown to (the room we are in).
            DUNGEON_LOOT_RADIUS = 40,

            --// The end: this boss dying ends the run. The end chest is
            --// waited for up to END_CHEST_WAIT seconds, the summary's Replay
            --// button (a button with one of REPLAY_TEXTS) up to REPLAY_WAIT;
            --// it is pressed every REPLAY_RETRY seconds, REPLAY_CLICKS times
            --// at most, until the summary closes.
            DUNGEON_FINAL_BOSS_NAMES = { "Skull King" },
            DUNGEON_END_CHEST_WAIT = 8,
            --// The end chest is looked for this far from where the boss died.
            DUNGEON_END_CHEST_RADIUS = 80,
            DUNGEON_REPLAY_TEXTS = { "replay", "play again", "retry" },
            DUNGEON_REPLAY_WAIT = 30,
            DUNGEON_REPLAY_RETRY = 3,
            DUNGEON_REPLAY_CLICKS = 5,
            DUNGEON_DOOR_KEY = "E",

            --// Flying: WalkSpeed times this, this far above standing height,
            --// in legs of at most DUNGEON_STEP_STUDS. The wall check sweeps a
            --// box this size (X, Y, Z studs).
            DUNGEON_SPEED_MULTIPLIER = 2.7,
            DUNGEON_HOVER_OFFSET = 1.5,
            DUNGEON_STEP_STUDS = 14,
            DUNGEON_SWEEP_SIZE = { 2.5, 4, 2.5 },
            --// Fly through when there is no clear way: along the path when
            --// every leg of it is blocked, straight at the target when no
            --// path is found (off: such a target counts as blocked).
            DUNGEON_FLY_THROUGH_BLOCKED = true,

            --// Fighting: hover this far from the target; skills go out while
            --// it (or any monster we pass) is within ATTACK_RANGE. Monsters
            --// within ENGAGE_RADIUS are fought before anything else.
            DUNGEON_ATTACK_DISTANCE = 6,
            DUNGEON_ENGAGE_RADIUS = 30,
            DUNGEON_ATTACK_RANGE = 14,
            --// "auto": the game's own auto-fight (its button, see
            --// AUTO_BUTTON_NAMES); "keys": the skill keys below.
            DUNGEON_ATTACK_MODE = "auto",
            --// Enum.KeyCode names: skill 1 every 0.2s, the buff (skill 4)
            --// every BUFF_INTERVAL (pressing it on cooldown does nothing).
            DUNGEON_SKILL_KEY = "One",
            DUNGEON_SKILL_INTERVAL = 0.2,
            DUNGEON_BUFF_KEY = "Four",
            DUNGEON_BUFF_INTERVAL = 1,
            --// A target not reached after this many blocked legs is left
            --// for this long.
            --// (each blocked try aims at another side of the target).
            DUNGEON_BLOCKED_TRIES = 8,
            --// A target's size counts up to this (studs from its centre).
            DUNGEON_MAX_TARGET_RADIUS = 10,
            DUNGEON_UNREACHABLE_SECONDS = 15,
            --// After a boss was seen, nothing left for this long = cleared.
            DUNGEON_DONE_SECONDS = 10,
            DUNGEON_TICK = 0.1,

            --// Boss skill warnings: the parts the boss and miniboss put in
            --// these folders (anywhere in workspace), green = safe zone.
            DUNGEON_SKILL_FX_FOLDERS = { "LumiBossFx", "LumiBossSkillFx" },
            --// Parts counted by name wherever they are.
            DUNGEON_SKILL_PART_NAMES = {},
            DUNGEON_SAFE_ZONE_NAMES = {},
            --// Also guess from shape outside the folders (flat, wide, not
            --// colliding). Off: it can catch our own skills' effects.
            DUNGEON_DETECT_UNNAMED = false,
            DUNGEON_SAFE_ZONE_BY_COLOR = true,
            DUNGEON_GREEN_MARGIN = 60,
            DUNGEON_TELEGRAPH_MAX_THICKNESS = 2,
            DUNGEON_TELEGRAPH_MIN_SIZE = 6,
            --// A warning still there after this is forgotten.
            DUNGEON_TELEGRAPH_MAX_SECONDS = 8,
            --// Dodge: stay this far outside a warning; look for a spot in
            --// rings DODGE_STEP apart, up to DODGE_MAX_DISTANCE away.
            DUNGEON_DODGE_MARGIN = 3,
            DUNGEON_DODGE_STEP = 4,
            DUNGEON_DODGE_MAX_DISTANCE = 40,
        }
    end,
}
