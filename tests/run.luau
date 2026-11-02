-- Unit tests for the pure parts (Core) of the hop modules.
-- Run from the repo root:  lune run tests/run.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local function LoadSpec(Path)
    return luau.load(fs.readFile(Path), { debugName = Path })()
end

--// Config's real values, so the tests follow what ships.
local Cfg = LoadSpec("feature/Config.lua").Start()
local Memory = LoadSpec("feature/ServerMemory.lua").Core
local Hop = LoadSpec("feature/ServerHop.lua").Core
local Camper = LoadSpec("feature/CamperCheck.lua").Core
local SettingsCore = LoadSpec("feature/Settings.lua").Core
local Walk = LoadSpec("feature/ZoneWalk.lua").Core
local AutoCore = LoadSpec("feature/GameAuto.lua").Core
local HuntCore = LoadSpec("feature/AutoHunt.lua").Core

local Passed, Failed = 0, 0

local function Test(Name, Body)
    local Ok, Error = pcall(Body)

    if Ok then
        Passed += 1
    else
        Failed += 1
        print("FAIL  " .. Name .. "\n      " .. tostring(Error))
    end
end

local function Equal(Actual, Expected, What)
    if Actual ~= Expected then
        error(string.format("%s: expected %s, got %s", What or "value", tostring(Expected), tostring(Actual)), 2)
    end
end

local function Truthy(Value, What)
    if not Value then
        error((What or "value") .. " should be set", 2)
    end
end

local NOW = 1_000_000

local function First(N)
    return 1
end

------------------------------------------------------------------------
--// ServerMemory.Core
------------------------------------------------------------------------

Test("a kill bans until shortly before the respawn and records it", function()
    local Entry = Memory.LeaveEntry("KILLED", nil, "Boss", NOW, Cfg)

    Equal(Entry.SpawnAt, NOW + Cfg.BOSS_RESPAWN_SECONDS, "SpawnAt")
    Equal(Entry.Until, NOW + Cfg.BOSS_RESPAWN_SECONDS - Cfg.SPAWN_LEAD_SECONDS, "Until")
    Equal(Entry.Boss, "Boss", "Boss")
end)

Test("a kill with a stale timer uses the respawn time", function()
    local Entry = Memory.LeaveEntry("KILLED", 3, "Boss", NOW, Cfg)
    Equal(Entry.SpawnAt, NOW + Cfg.BOSS_RESPAWN_SECONDS, "SpawnAt")
end)

Test("a kill with a reset timer uses the timer", function()
    local Entry = Memory.LeaveEntry("KILLED", 590, "Boss", NOW, Cfg)
    Equal(Entry.SpawnAt, NOW + 590, "SpawnAt")
end)

Test("a far timer bans until before the spawn, never under the minimum", function()
    local Far = Memory.LeaveEntry("FAR", 400, "Boss", NOW, Cfg)
    Equal(Far.Until, NOW + 400 - Cfg.SPAWN_LEAD_SECONDS, "Until far")

    local Near = Memory.LeaveEntry("FAR", 40, "Boss", NOW, Cfg)
    Equal(Near.Until, NOW + Cfg.BAN_MIN_SECONDS, "Until near")
    Equal(Near.SpawnAt, NOW + 40, "SpawnAt near")
end)

Test("an unknown spawn gets the unknown ban and no spawn time", function()
    local Entry = Memory.LeaveEntry("NO_TIMER", nil, "Boss", NOW, Cfg)
    Equal(Entry.Until, NOW + Cfg.BAN_UNKNOWN_SECONDS, "Until")
    Equal(Entry.SpawnAt, nil, "SpawnAt")
end)

Test("an absurd timer reading is ignored", function()
    local Entry = Memory.LeaveEntry("FAR", 99999, "Boss", NOW, Cfg)
    Equal(Entry.SpawnAt, nil, "SpawnAt")
end)

Test("a camped server is banned long and never a spawn target", function()
    local Entry = Memory.LeaveEntry("CAMPED", 300, "Boss", NOW, Cfg)
    Equal(Entry.Until, NOW + Cfg.BAN_CAMPED_SECONDS, "Until")
    Equal(Entry.SpawnAt, nil, "SpawnAt")
end)

Test("GetBan only while the ban lasts", function()
    local Mem = Memory.WithServer(Memory.Empty(), "A", { Until = NOW + 10, Reason = "X" })

    Truthy(Memory.GetBan(Mem, "A", NOW), "ban now")
    Equal(Memory.GetBan(Mem, "A", NOW + 10), nil, "ban after")
    Equal(Memory.GetBan(Mem, "B", NOW), nil, "other server")
end)

Test("WithServer leaves the original memory alone", function()
    local Mem = Memory.Empty()
    local Next = Memory.WithServer(Mem, "A", { Until = NOW + 10, Reason = "X" })

    Equal(Mem.Servers.A, nil, "original")
    Truthy(Next.Servers.A, "new")
end)

Test("WithBan extends the ban and keeps the spawn time", function()
    local Mem = Memory.WithServer(Memory.Empty(), "A", { Until = NOW + 5, Reason = "KILLED", SpawnAt = NOW + 300, Boss = "Boss" })
    local Banned = Memory.WithBan(Mem, "A", Cfg.BAN_UNJOINABLE_SECONDS, "UNJOINABLE", NOW)

    Equal(Banned.Servers.A.Until, NOW + Cfg.BAN_UNJOINABLE_SECONDS, "Until")
    Equal(Banned.Servers.A.SpawnAt, NOW + 300, "SpawnAt")
    Equal(Banned.Servers.A.Reason, "UNJOINABLE", "Reason")

    local Kept = Memory.WithBan(Memory.WithServer(Memory.Empty(), "A", { Until = NOW + 900, Reason = "CAMPED" }), "A", 10, "UNJOINABLE", NOW)
    Equal(Kept.Servers.A.Until, NOW + 900, "a longer ban is kept")
end)

Test("Prune drops what has ended and keeps upcoming spawns", function()
    local Mem = Memory.Empty()
    Mem = Memory.WithServer(Mem, "Old", { Until = NOW - 1, Reason = "X" })
    Mem = Memory.WithServer(Mem, "Banned", { Until = NOW + 50, Reason = "X" })
    Mem = Memory.WithServer(Mem, "Spawn", { Until = NOW - 1, Reason = "FAR", SpawnAt = NOW + 30, Boss = "B" })
    Mem = Memory.WithCampers(Mem, { { UserId = 1, Name = "Old" } }, "Z", NOW - Cfg.CAMPER_MEMORY_SECONDS)
    Mem = Memory.WithCampers(Mem, { { UserId = 2, Name = "New" } }, "Z", NOW)

    local Pruned = Memory.Prune(Mem, NOW, Cfg)

    Equal(Pruned.Servers.Old, nil, "Old")
    Truthy(Pruned.Servers.Banned, "Banned")
    Truthy(Pruned.Servers.Spawn, "Spawn")
    Equal(Pruned.Campers["1"], nil, "old camper")
    Truthy(Pruned.Campers["2"], "new camper")
end)

Test("Prune keeps at most MEMORY_MAX_SERVERS, the longest lasting", function()
    local Mem = Memory.Empty()

    for Index = 1, Cfg.MEMORY_MAX_SERVERS + 5 do
        Mem = Memory.WithServer(Mem, "S" .. Index, { Until = NOW + Index, Reason = "X" })
    end

    local Pruned = Memory.Prune(Mem, NOW, Cfg)

    Equal(Memory.Count(Pruned.Servers), Cfg.MEMORY_MAX_SERVERS, "count")
    Equal(Pruned.Servers.S1, nil, "shortest dropped")
    Truthy(Pruned.Servers["S" .. (Cfg.MEMORY_MAX_SERVERS + 5)], "longest kept")
end)

Test("Normalize survives junk and keeps valid entries", function()
    Equal(Memory.Count(Memory.Normalize(nil).Servers), 0, "nil")
    Equal(Memory.Count(Memory.Normalize("x").Servers), 0, "string")

    local Mem = Memory.Normalize({
        Servers = { A = { Until = NOW, Reason = "KILLED", SpawnAt = NOW + 1, Boss = "B" }, B = { Until = "x" }, [1] = {} },
        Campers = { ["7"] = { Name = "P", Zone = "Z", Seen = NOW }, ["8"] = { Seen = NOW } },
        Expect = { JobId = "A", SpawnAt = NOW },
    })

    Equal(Memory.Count(Mem.Servers), 1, "servers")
    Equal(Mem.Servers.A.Boss, "B", "boss")
    Equal(Memory.Count(Mem.Campers), 1, "campers")
    Equal(Mem.Expect.JobId, "A", "expect")
end)

Test("FindSpawnTarget picks the soonest spawn inside the window", function()
    local Mem = Memory.Empty()
    local function Add(Id, SpawnIn, Fields)
        local Entry = { Until = NOW + 1, Reason = "FAR", SpawnAt = NOW + SpawnIn, Boss = "Boss" }

        for Key, Value in pairs(Fields or {}) do
            Entry[Key] = Value
        end

        Mem = Memory.WithServer(Mem, Id, Entry)
    end

    Add("TooSoon", Cfg.SPAWN_TARGET_MIN_SECONDS - 1)
    Add("TooLate", Cfg.SPAWN_TARGET_MAX_SECONDS + 1)
    Add("Later", Cfg.SPAWN_TARGET_MAX_SECONDS - 1)
    Add("Best", Cfg.SPAWN_TARGET_MIN_SECONDS + 5)
    Add("Camped", Cfg.SPAWN_TARGET_MIN_SECONDS + 1, { Reason = "CAMPED" })
    Add("Tried", Cfg.SPAWN_TARGET_MIN_SECONDS + 1, { Targeted = true })
    Add("OtherBoss", Cfg.SPAWN_TARGET_MIN_SECONDS + 1, { Boss = "Other" })
    Add("Current", Cfg.SPAWN_TARGET_MIN_SECONDS + 1)

    local JobId, SpawnIn = Memory.FindSpawnTarget(Mem, "Boss", "Current", NOW, Cfg)

    Equal(JobId, "Best", "target")
    Equal(SpawnIn, Cfg.SPAWN_TARGET_MIN_SECONDS + 5, "spawn in")
    Equal(Memory.FindSpawnTarget(Memory.Empty(), "Boss", "X", NOW, Cfg), nil, "empty memory")
end)

Test("a kill becomes a spawn target about one respawn later", function()
    local Mem = Memory.WithServer(Memory.Empty(), "A", Memory.LeaveEntry("KILLED", nil, "Boss", NOW, Cfg))
    local Arrive = NOW + Cfg.BOSS_RESPAWN_SECONDS - Cfg.SPAWN_TARGET_MAX_SECONDS + 1

    Equal(Memory.FindSpawnTarget(Mem, "Boss", "X", NOW + 60, Cfg), nil, "too early")
    Equal(Memory.FindSpawnTarget(Mem, "Boss", "X", Arrive, Cfg), "A", "in the window")
end)

Test("WithTargeted marks the server tried and expected", function()
    local Mem = Memory.WithServer(Memory.Empty(), "A", { Until = NOW, Reason = "FAR", SpawnAt = NOW + 60, Boss = "Boss" })
    local Marked = Memory.WithTargeted(Mem, "A")

    Equal(Marked.Servers.A.Targeted, true, "Targeted")
    Equal(Marked.Expect.JobId, "A", "Expect")
    Equal(Mem.Servers.A.Targeted, nil, "original untouched")
    Equal(Memory.WithoutExpect(Marked).Expect, nil, "WithoutExpect")
end)

Test("known campers are matched by UserId and zone", function()
    local Mem = Memory.WithCampers(Memory.Empty(), { { UserId = 42, Name = "Afk" } }, "Boss03", NOW)
    local Here = { { UserId = 1, Name = "Me" }, { UserId = 42, Name = "Afk" } }

    Equal(Memory.KnownCamper(Mem, Here, "Boss03"), "Afk", "same zone")
    Equal(Memory.KnownCamper(Mem, Here, "Boss04"), nil, "other zone")
    Equal(Memory.KnownCamper(Mem, { { UserId = 1, Name = "Me" } }, "Boss03"), nil, "not here")
end)

------------------------------------------------------------------------
--// ServerHop.Core
------------------------------------------------------------------------

local function Server(Id, Playing, MaxPlayers)
    return { id = Id, playing = Playing, maxPlayers = MaxPlayers or 10 }
end

local NoBans = function()
    return nil
end

Test("FilterPage drops this server, full ones and malformed ones", function()
    local Servers = Hop.FilterPage({
        Server("Here", 1),
        Server("Full", 10),
        Server("Open", 3),
        { id = 5, playing = 1, maxPlayers = 10 },
        { id = "NoCount" },
    }, "Here")

    Equal(#Servers, 1, "count")
    Equal(Servers[1].Id, "Open", "id")
end)

Test("Pick prefers unbanned roomy servers", function()
    local Servers = Hop.FilterPage({ Server("Tight", 9), Server("Banned", 1), Server("Roomy", 4) }, "")
    local Bans = { Banned = { Until = NOW + 1, Reason = "KILLED" } }
    local Picked, Tier = Hop.Pick(Servers, function(Id)
        return Bans[Id]
    end, Cfg, First)

    Equal(Picked.Id, "Roomy", "server")
    Equal(Tier, Hop.TIER_ROOMY, "tier")
end)

Test("Pick takes a tight server over a banned one", function()
    local Servers = Hop.FilterPage({ Server("Banned", 1), Server("Tight", 9) }, "")
    local Picked, Tier = Hop.Pick(Servers, function(Id)
        return Id == "Banned" and { Until = NOW, Reason = "KILLED" } or nil
    end, Cfg, First)

    Equal(Picked.Id, "Tight", "server")
    Equal(Tier, Hop.TIER_OPEN, "tier")
end)

Test("Pick falls back to the ban ending first, never a camped one", function()
    local Servers = Hop.FilterPage({ Server("Camped", 1), Server("Late", 1), Server("Soon", 1) }, "")
    local Bans = {
        Camped = { Until = NOW + 1, Reason = "CAMPED" },
        Late = { Until = NOW + 500, Reason = "KILLED" },
        Soon = { Until = NOW + 100, Reason = "FAR" },
    }
    local Picked, Tier = Hop.Pick(Servers, function(Id)
        return Bans[Id]
    end, Cfg, First)

    Equal(Picked.Id, "Soon", "server")
    Equal(Tier, Hop.TIER_BANNED, "tier")

    local OnlyCamped = Hop.FilterPage({ Server("Camped", 1) }, "")
    Equal(Hop.Pick(OnlyCamped, function()
        return Bans.Camped
    end, Cfg, First), nil, "only camped")
end)

Test("Pick picks at random among the best tier", function()
    local Servers = Hop.FilterPage({ Server("A", 1), Server("B", 1), Server("C", 1) }, "")
    local Picked = Hop.Pick(Servers, NoBans, Cfg, function(N)
        return N
    end)

    Equal(Picked.Id, "C", "last index")
    Equal(Hop.Pick({}, NoBans, Cfg, First), nil, "empty")
end)

Test("HasEnough counts only roomy unbanned servers", function()
    local Raw = {}

    for Index = 1, Cfg.HOP_POOL_TARGET do
        table.insert(Raw, Server("S" .. Index, 1))
    end

    local Servers = Hop.FilterPage(Raw, "")

    Equal(Hop.HasEnough(Servers, NoBans, Cfg), true, "enough")
    Equal(Hop.HasEnough(Servers, function(Id)
        return Id == "S1" and { Until = NOW, Reason = "X" } or nil
    end, Cfg), false, "one banned")
end)

Test("rate limits are recognised and backed off", function()
    Equal(Hop.IsRateLimited("HTTP 429 (Too Many Requests)"), true, "429")
    Equal(Hop.IsRateLimited("Too many requests"), true, "message")
    Equal(Hop.IsRateLimited("HTTP 500"), false, "500")

    local Wait = Hop.NextBackoff(0, Cfg)
    Equal(Wait, Cfg.HOP_RATE_LIMIT_DELAY, "first")
    Equal(Hop.NextBackoff(Wait, Cfg), math.min(Wait * 2, Cfg.HOP_RATE_LIMIT_MAX), "doubled")
    Equal(Hop.NextBackoff(Cfg.HOP_RATE_LIMIT_MAX, Cfg), Cfg.HOP_RATE_LIMIT_MAX, "capped")
end)

------------------------------------------------------------------------
--// CamperCheck.Core
------------------------------------------------------------------------

local Center = { X = 0, Z = 0 }

Test("Near keeps players inside the radius, X and Z only", function()
    local Near = Camper.Near({
        { UserId = 1, Name = "In", X = Cfg.CAMPER_RADIUS - 1, Z = 0 },
        { UserId = 2, Name = "Out", X = Cfg.CAMPER_RADIUS, Z = Cfg.CAMPER_RADIUS },
    }, Center, Cfg.CAMPER_RADIUS)

    Truthy(Near["1"], "in")
    Equal(Near["2"], nil, "out")
end)

Test("FindCampers keeps those who stayed and barely moved", function()
    local Before = Camper.Near({
        { UserId = 1, Name = "Afk", X = 5, Z = 5 },
        { UserId = 2, Name = "Walker", X = 0, Z = 0 },
        { UserId = 3, Name = "Leaver", X = 1, Z = 1 },
    }, Center, Cfg.CAMPER_RADIUS)
    local After = Camper.Near({
        { UserId = 1, Name = "Afk", X = 6, Z = 5 },
        { UserId = 2, Name = "Walker", X = Cfg.CAMPER_MOVE_TOLERANCE + 1, Z = 0 },
        { UserId = 4, Name = "Arrived", X = 0, Z = 0 },
    }, Center, Cfg.CAMPER_RADIUS)

    local Campers = Camper.FindCampers(Before, After, Cfg)

    Equal(#Campers, 1, "count")
    Equal(Campers[1].Name, "Afk", "name")
    Equal(Campers[1].UserId, "1", "user id")
    Equal(Camper.Names({ { Name = "A" }, { Name = "B" } }), "A, B", "names")
end)

------------------------------------------------------------------------
--// Settings.Core (kill counts)
------------------------------------------------------------------------

Test("AddKill counts per boss without changing the old table", function()
    local Before = { A = 2 }
    local After = SettingsCore.AddKill(SettingsCore.AddKill(Before, "A"), "B")

    Equal(After.A, 3, "A")
    Equal(After.B, 1, "B")
    Equal(Before.A, 2, "old A")
    Equal(Before.B, nil, "old B")
end)

Test("CleanKills keeps whole non-negative counts by boss name only", function()
    local Kills = SettingsCore.CleanKills({ A = 4, B = -1, C = 2.5, D = "7", [1] = 3 })

    Equal(Kills.A, 4, "A")
    Equal(Kills.B, nil, "negative")
    Equal(Kills.C, nil, "fraction")
    Equal(Kills.D, nil, "string")
    Equal(Kills[1], nil, "number key")
    Equal(next(SettingsCore.CleanKills("bad")), nil, "not a table")
end)

Test("IsHijacked: our own walk target is not a takeover", function()
    local Target = { X = 10, Z = 20 }

    Equal(Walk.IsHijacked({ X = 10.5, Z = 20 }, nil, Target, 1), false, "same point")
    Equal(Walk.IsHijacked({ X = 30, Z = 20 }, nil, Target, 1), true, "moved to a monster")
    Equal(Walk.IsHijacked({ X = 10, Z = 20 }, {}, Target, 1), true, "walks to a part")
end)

Test("Progress tells stuck, pulled away and walking apart", function()
    Equal(Walk.Progress(0.5, 50, 50, 1, 6), "stuck", "standing still")
    Equal(Walk.Progress(20, 50, 30, 1, 6), "ok", "walking closer")
    Equal(Walk.Progress(20, 50, 55, 1, 6), "pulled", "walking away")
    Equal(Walk.Progress(3, 50, 50, 1, 6), "ok", "sliding along a wall")
end)

Test("NextCheck presses again only after a quiet window, at most AUTO_CONFIRM_TRIES times", function()
    local Window = Cfg.AUTO_CONFIRM_SECONDS

    Equal(AutoCore.NextCheck({ Since = 0, Presses = 0 }, true, Window + 1, Cfg), "ok", "auto working")
    Equal(AutoCore.NextCheck({ Since = 0, Presses = 0 }, false, Window - 1, Cfg), "wait", "still in window")
    Equal(AutoCore.NextCheck({ Since = 0, Presses = 0 }, false, Window, Cfg), "press", "quiet window")
    Equal(AutoCore.NextCheck({ Since = 0, Presses = Cfg.AUTO_CONFIRM_TRIES }, false, Window, Cfg), "giveup", "out of tries")
end)

Test("AUTO_CONFIRM_TRIES is even, so re-presses end where the first press aimed", function()
    Equal(Cfg.AUTO_CONFIRM_TRIES % 2, 0, "even")
end)

Test("SpawnsSoon stays for a boss within the wait, not for an unknown or far one", function()
    Equal(HuntCore.SpawnsSoon(10, 30), true, "10s")
    Equal(HuntCore.SpawnsSoon(0, 30), true, "now")
    Equal(HuntCore.SpawnsSoon(31, 30), false, "far")
    Equal(HuntCore.SpawnsSoon(nil, 30), false, "unreadable")
end)

Test("NextDeadline follows the live timer, within the cap", function()
    local Grace = Cfg.BOSS_SPAWN_GRACE

    Equal(HuntCore.NextDeadline(0, 10, 0, 100, Cfg), 10 + Grace, "first reading")
    Equal(HuntCore.NextDeadline(10 + Grace, 15, 5, 100, Cfg), 20 + Grace, "timer ran slow: later")
    Equal(HuntCore.NextDeadline(50, 5, 5, 100, Cfg), 50, "never earlier")
    Equal(HuntCore.NextDeadline(50, 0, 45, 100, Cfg), 50, "timer at zero: grace left as is")
    Equal(HuntCore.NextDeadline(50, nil, 45, 100, Cfg), 50, "unreadable")
    Equal(HuntCore.NextDeadline(50, 500, 45, 100, Cfg), 100, "capped")
end)

print(string.format("%d passed, %d failed", Passed, Failed))

if Failed > 0 then
    process.exit(1)
end
