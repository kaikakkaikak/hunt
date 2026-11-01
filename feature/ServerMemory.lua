-- ServerMemory remembers servers already visited, so a hop does not land
-- back on one whose boss is dead or camped:
--   * every server left is banned for a while, by why it was left
--     (Core.LeaveEntry): until shortly before its boss respawns when the
--     timer is known, longer when someone camps the boss;
--   * a known spawn time makes the server a spawn target: a later hop joins
--     it right before the boss spawns (Core.FindSpawnTarget);
--   * players seen camping a boss zone are remembered by UserId, so a server
--     with one of them in it is left at once next time.
-- Kept in autoHunt/memory.json and, for executors without file access,
-- handed to the next server as getgenv().AutoHuntMemory by the queued reload.
-- Times are os.time() (wall clock, seconds) so they hold across servers.
local Core = {}

--// A server entry: { Until, Reason, SpawnAt?, Boss?, Targeted? }.
--// A camper: { Name, Zone, Seen }.
--// Expect: the spawn target being joined, { JobId, SpawnAt }.
function Core.Empty()
    return { Servers = {}, Campers = {}, Expect = nil }
end

local function Copy(Table)
    local Result = {}

    for Key, Value in pairs(Table) do
        Result[Key] = Value
    end

    return Result
end

local function With(Map, Key, Value)
    local Result = Copy(Map)
    Result[Key] = Value
    return Result
end

local function WithField(Mem, Field, Value)
    local Result = Copy(Mem)
    Result[Field] = Value
    return Result
end

local function IsNumber(Value)
    return type(Value) == "number" and Value == Value
end

--// A memory from decoded JSON, with anything malformed left out.
function Core.Normalize(Raw)
    local Mem = Core.Empty()

    if type(Raw) ~= "table" then
        return Mem
    end

    if type(Raw.Servers) == "table" then
        for JobId, Entry in pairs(Raw.Servers) do
            if type(JobId) == "string" and type(Entry) == "table" and IsNumber(Entry.Until) then
                Mem.Servers[JobId] = {
                    Until = Entry.Until,
                    Reason = type(Entry.Reason) == "string" and Entry.Reason or "UNKNOWN",
                    SpawnAt = IsNumber(Entry.SpawnAt) and Entry.SpawnAt or nil,
                    Boss = type(Entry.Boss) == "string" and Entry.Boss or nil,
                    Targeted = Entry.Targeted == true or nil,
                }
            end
        end
    end

    if type(Raw.Campers) == "table" then
        for UserId, Camper in pairs(Raw.Campers) do
            if type(Camper) == "table" and IsNumber(Camper.Seen) and type(Camper.Zone) == "string" then
                Mem.Campers[tostring(UserId)] = {
                    Name = tostring(Camper.Name or UserId),
                    Zone = Camper.Zone,
                    Seen = Camper.Seen,
                }
            end
        end
    end

    local Expect = Raw.Expect

    if type(Expect) == "table" and type(Expect.JobId) == "string" and IsNumber(Expect.SpawnAt) then
        Mem.Expect = { JobId = Expect.JobId, SpawnAt = Expect.SpawnAt }
    end

    return Mem
end

--// When an entry stops mattering: its ban is over and its spawn is past.
local function EntryEnd(Entry, Cfg)
    return math.max(Entry.Until, Entry.SpawnAt and Entry.SpawnAt + Cfg.SPAWN_TARGET_MIN_SECONDS or 0)
end

--// Mem without expired servers and campers, and at most
--// Cfg.MEMORY_MAX_SERVERS servers (the ones that last longest are kept).
function Core.Prune(Mem, Now, Cfg)
    local Kept = {}

    for JobId, Entry in pairs(Mem.Servers) do
        if EntryEnd(Entry, Cfg) > Now then
            table.insert(Kept, { JobId = JobId, Entry = Entry, End = EntryEnd(Entry, Cfg) })
        end
    end

    table.sort(Kept, function(A, B)
        return A.End > B.End
    end)

    local Servers = {}

    for Index = 1, math.min(#Kept, Cfg.MEMORY_MAX_SERVERS) do
        Servers[Kept[Index].JobId] = Kept[Index].Entry
    end

    local Campers = {}

    for UserId, Camper in pairs(Mem.Campers) do
        if Now - Camper.Seen < Cfg.CAMPER_MEMORY_SECONDS then
            Campers[UserId] = Camper
        end
    end

    local Expect = Mem.Expect

    if Expect and Expect.SpawnAt + Cfg.TARGET_WAIT_MAX_SECONDS <= Now then
        Expect = nil
    end

    return { Servers = Servers, Campers = Campers, Expect = Expect }
end

--// The entry for a server left for Reason. SpawnIn: the boss timer's
--// seconds when it was read, or nil.
function Core.LeaveEntry(Reason, SpawnIn, Boss, Now, Cfg)
    if Reason == "CAMPED" then
        return { Until = Now + Cfg.BAN_CAMPED_SECONDS, Reason = Reason }
    end

    local Spawn = IsNumber(SpawnIn) and SpawnIn or nil

    --// Right after a kill the timer may not have reset yet.
    if Reason == "KILLED" and not (Spawn and Spawn >= Cfg.SPAWN_TIMER_MIN_SECONDS) then
        Spawn = Cfg.BOSS_RESPAWN_SECONDS
    end

    --// A reading outside one respawn cycle is not trusted.
    if Spawn and (Spawn <= 0 or Spawn > Cfg.BOSS_RESPAWN_SECONDS * 1.5) then
        Spawn = nil
    end

    if Spawn then
        return {
            Until = Now + math.max(Cfg.BAN_MIN_SECONDS, Spawn - Cfg.SPAWN_LEAD_SECONDS),
            Reason = Reason,
            SpawnAt = Now + Spawn,
            Boss = Boss,
        }
    end

    return { Until = Now + Cfg.BAN_UNKNOWN_SECONDS, Reason = Reason }
end

function Core.WithServer(Mem, JobId, Entry)
    return WithField(Mem, "Servers", With(Mem.Servers, JobId, Entry))
end

--// Mem with JobId banned for at least Seconds more; the rest of its entry
--// (a known spawn time) is kept.
function Core.WithBan(Mem, JobId, Seconds, Reason, Now)
    local Entry = Copy(Mem.Servers[JobId] or { Until = Now })
    Entry.Until = math.max(Entry.Until, Now + Seconds)
    Entry.Reason = Reason
    return Core.WithServer(Mem, JobId, Entry)
end

--// The entry banning JobId now, or nil.
function Core.GetBan(Mem, JobId, Now)
    local Entry = Mem.Servers[JobId]
    return Entry and Entry.Until > Now and Entry or nil
end

--// The JobId of a server whose Boss spawns within the target window, not
--// camped, not tried yet and not Current; the soonest one. Or nil.
function Core.FindSpawnTarget(Mem, Boss, Current, Now, Cfg)
    local BestId, BestIn

    for JobId, Entry in pairs(Mem.Servers) do
        local SpawnIn = Entry.SpawnAt and Entry.SpawnAt - Now

        if JobId ~= Current and Entry.Boss == Boss and SpawnIn
            and Entry.Reason ~= "CAMPED" and not Entry.Targeted
            and SpawnIn >= Cfg.SPAWN_TARGET_MIN_SECONDS and SpawnIn <= Cfg.SPAWN_TARGET_MAX_SECONDS
            and (not BestIn or SpawnIn < BestIn)
        then
            BestId, BestIn = JobId, SpawnIn
        end
    end

    return BestId, BestIn
end

--// Mem with JobId marked as tried, and expected on the next server.
function Core.WithTargeted(Mem, JobId)
    local Entry = Mem.Servers[JobId]

    if not Entry then
        return Mem
    end

    local Marked = Copy(Entry)
    Marked.Targeted = true

    local Result = Core.WithServer(Mem, JobId, Marked)
    return WithField(Result, "Expect", { JobId = JobId, SpawnAt = Entry.SpawnAt })
end

function Core.WithoutExpect(Mem)
    return WithField(Mem, "Expect", nil)
end

--// Players: list of { UserId, Name }.
function Core.WithCampers(Mem, Players, Zone, Now)
    local Campers = Copy(Mem.Campers)

    for _, Camper in ipairs(Players) do
        Campers[tostring(Camper.UserId)] = { Name = Camper.Name, Zone = Zone, Seen = Now }
    end

    return WithField(Mem, "Campers", Campers)
end

--// The name of the first of Players (list of { UserId, Name }) known to
--// camp Zone, or nil.
function Core.KnownCamper(Mem, Players, Zone)
    for _, Player in ipairs(Players) do
        local Camper = Mem.Campers[tostring(Player.UserId)]

        if Camper and Camper.Zone == Zone then
            return Player.Name
        end
    end

    return nil
end

function Core.Count(Map)
    local Count = 0

    for _ in pairs(Map) do
        Count += 1
    end

    return Count
end

return {
    Name = "ServerMemory",
    Dependencies = {"Config"},
    Core = Core,

    Start = function(Context)
        local Config = Context.Config
        local HttpService = Context.Services.HttpService
        local Lifetime = Context.Lifetime

        local FOLDER = "autoHunt"
        local FILE = FOLDER .. "/memory.json"

        local ServerMemory = { Name = "ServerMemory", Mem = Core.Empty() }

        local function Decode(Text)
            local Ok, Value = pcall(function()
                return HttpService:JSONDecode(Text)
            end)

            return Ok and Value or nil
        end

        local function ReadFile()
            if type(readfile) ~= "function" or type(isfile) ~= "function" then
                return nil
            end

            local Ok, Text = pcall(function()
                return isfile(FILE) and readfile(FILE) or nil
            end)

            return Ok and Text or nil
        end

        function ServerMemory:Encode()
            return HttpService:JSONEncode(self.Mem)
        end

        local function Save()
            if type(writefile) ~= "function" then
                return
            end

            local Ok, Error = pcall(function()
                if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder(FOLDER) then
                    makefolder(FOLDER)
                end

                writefile(FILE, ServerMemory:Encode())
            end)

            if not Ok then
                warn("[AutoHunt] Could not save the server memory:", Error)
            end
        end

        --// Every change goes through here: prune, keep, save.
        local function Set(Mem)
            ServerMemory.Mem = Core.Prune(Mem, os.time(), Config)
            Save()
        end

        --// The file wins, as in Settings: it is always the newest.
        local function Load()
            local Env = Lifetime.Env
            local Resume = Env and Env.AutoHuntMemory

            if Env then
                Env.AutoHuntMemory = nil
            end

            local Text = ReadFile() or (type(Resume) == "string" and Resume or nil)
            ServerMemory.Mem = Core.Prune(Core.Normalize(Text and Decode(Text)), os.time(), Config)
        end

        --// Records leaving JobId for Reason (see Core.LeaveEntry).
        function ServerMemory:Leave(JobId, Reason, SpawnIn, Boss)
            local Entry = Core.LeaveEntry(Reason, SpawnIn, Boss, os.time(), Config)
            Set(Core.WithServer(self.Mem, JobId, Entry))
            return Entry
        end

        --// A teleport there failed (full, closed): leave it alone a while.
        function ServerMemory:BanUnjoinable(JobId)
            Set(Core.WithBan(self.Mem, JobId, Config.BAN_UNJOINABLE_SECONDS, "UNJOINABLE", os.time()))
        end

        function ServerMemory:GetBan(JobId)
            return Core.GetBan(self.Mem, JobId, os.time())
        end

        function ServerMemory:FindSpawnTarget(Boss, Current)
            return Core.FindSpawnTarget(self.Mem, Boss, Current, os.time(), Config)
        end

        function ServerMemory:MarkTargeted(JobId)
            Set(Core.WithTargeted(self.Mem, JobId))
        end

        --// True once when this server was joined as a spawn target.
        function ServerMemory:TakeExpect(JobId)
            local Expect = self.Mem.Expect

            if not Expect then
                return false
            end

            Set(Core.WithoutExpect(self.Mem))
            return Expect.JobId == JobId
        end

        function ServerMemory:NoteCampers(Players, Zone)
            Set(Core.WithCampers(self.Mem, Players, Zone, os.time()))
        end

        function ServerMemory:KnownCamper(Players, Zone)
            return Core.KnownCamper(self.Mem, Players, Zone)
        end

        function ServerMemory:Summary()
            return string.format("%d servers, %d campers", Core.Count(self.Mem.Servers), Core.Count(self.Mem.Campers))
        end

        Load()
        return ServerMemory
    end,
}
