-- ServerHop moves between servers, ported from
-- Automated-Industry-Complex/Features/ServerHop.lua:
--   Rejoin this server, Hop to another public server, and Join a server by
--   Job ID. The danger-group, join-alert and player-log parts of the
--   original are left out.
--
-- A hop goes, in order:
--   1. to a remembered server whose selected boss spawns soon
--      (ServerMemory spawn target);
--   2. otherwise to a random server from the public list, read over up to
--      Config.HOP_MAX_PAGES pages, picked by Core.Pick: never this one, and
--      servers left recently (ServerMemory bans) only when nothing else is
--      open.
-- A teleport that fails bans that server for a short while.
local Core = {}

--// Tiers Core.Pick tries in order.
Core.TIER_ROOMY = 1
Core.TIER_OPEN = 2
Core.TIER_BANNED = 3

--// The servers of one list page with a free slot, other than Current.
function Core.FilterPage(Data, Current)
    local Servers = {}

    for _, Server in ipairs(Data) do
        local Playing = tonumber(Server.playing)
        local MaxPlayers = tonumber(Server.maxPlayers)

        if type(Server.id) == "string" and Server.id ~= Current
            and Playing and MaxPlayers and Playing < MaxPlayers
        then
            table.insert(Servers, {
                Id = Server.id,
                Playing = Playing,
                MaxPlayers = MaxPlayers,
            })
        end
    end

    return Servers
end

local function IsRoomy(Server, Cfg)
    return Server.MaxPlayers - Server.Playing >= Cfg.HOP_FREE_SLOTS
end

--// The server to hop to and its tier, or nil. GetBan(JobId): the entry
--// banning it, or nil. RandomInt(N): 1..N.
--//   TIER_ROOMY:  not banned, at least HOP_FREE_SLOTS free;
--//   TIER_OPEN:   not banned;
--//   TIER_BANNED: banned but not camped, the one whose ban ends first.
function Core.Pick(Servers, GetBan, Cfg, RandomInt)
    local Roomy, Open, Banned = {}, {}, nil

    for _, Server in ipairs(Servers) do
        local Ban = GetBan(Server.Id)

        if not Ban then
            table.insert(Open, Server)

            if IsRoomy(Server, Cfg) then
                table.insert(Roomy, Server)
            end
        elseif Ban.Reason ~= "CAMPED" and (not Banned or Ban.Until < Banned.Until) then
            Banned = { Server = Server, Until = Ban.Until }
        end
    end

    if #Roomy > 0 then
        return Roomy[RandomInt(#Roomy)], Core.TIER_ROOMY
    end

    if #Open > 0 then
        return Open[RandomInt(#Open)], Core.TIER_OPEN
    end

    if Banned then
        return Banned.Server, Core.TIER_BANNED
    end

    return nil
end

--// Enough roomy, unbanned servers to stop reading pages.
function Core.HasEnough(Servers, GetBan, Cfg)
    local Count = 0

    for _, Server in ipairs(Servers) do
        if IsRoomy(Server, Cfg) and not GetBan(Server.Id) then
            Count += 1
        end
    end

    return Count >= Cfg.HOP_POOL_TARGET
end

function Core.IsRateLimited(Error)
    local Text = string.lower(tostring(Error))
    return string.find(Text, "429", 1, true) ~= nil or string.find(Text, "too many", 1, true) ~= nil
end

--// The wait after a rate limit: doubles each time, within the limits.
function Core.NextBackoff(Current, Cfg)
    return math.min(math.max(Current * 2, Cfg.HOP_RATE_LIMIT_DELAY), Cfg.HOP_RATE_LIMIT_MAX)
end

return {
    Name = "ServerHop",
    Dependencies = {"Config", "Settings", "ServerMemory"},
    Core = Core,

    Start = function(Context)
        local Config = Context.Config
        local Settings = Context.Settings
        local ServerMemory = Context.ServerMemory
        local HttpService = Context.Services.HttpService
        local TeleportService = game:GetService("TeleportService")
        local Player = Context.Player
        local NotifyAction = Context.NotifyAction

        --// The same notice is not shown again within this.
        local NOTICE_COOLDOWN = 8
        local SERVER_LIST_URL = "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"

        local ServerHop = {
            Name = "ServerHop",
            S = {
                Teleporting = false,
                --// A hop is reading the server list.
                Finding = false,
                Status = "IDLE",
                --// The server being teleported to.
                TargetJobId = nil,
                --// Extra wait before the next hop after a rate limit.
                Backoff = 0,
                --// Called right before every teleport (AutoHunt queues
                --// itself for the next server there).
                BeforeTeleport = nil,
                --// Notice key -> os.clock() it was last shown.
                NoticeAt = {},
            },
        }

        local S = ServerHop.S

        local function SetStatus(Text)
            S.Status = Text
        end

        --// A repeat of the same notice within NOTICE_COOLDOWN is dropped.
        local function Notify(Title, Message, Duration)
            local Key = Title .. "|" .. Message
            local now = os.clock()

            if now - (S.NoticeAt[Key] or -math.huge) < NOTICE_COOLDOWN then
                return
            end

            S.NoticeAt[Key] = now
            NotifyAction(Title, Message, Duration)
        end

        function ServerHop:GetStatus()
            return S.Status
        end

        --// Finding a server or waiting on a teleport.
        function ServerHop:IsBusy()
            return S.Finding or S.Teleporting
        end

        --// How long to wait before trying a failed hop again.
        function ServerHop:GetRetryDelay()
            return math.max(Config.HOP_RETRY_DELAY, S.Backoff)
        end

        function ServerHop:SetBeforeTeleport(Callback)
            S.BeforeTeleport = Callback
        end

        --// The teleport to TargetJobId did not happen.
        local function TeleportFailed(Message)
            if S.TargetJobId and S.TargetJobId ~= game.JobId then
                ServerMemory:BanUnjoinable(S.TargetJobId)
            end

            S.Teleporting = false
            S.TargetJobId = nil
            SetStatus("TELEPORT FAILED")
            Notify("SERVER", tostring(Message), 6)
        end

        --// A teleport that never finished nor failed: let the next try through.
        function ServerHop:CancelTeleport()
            if S.TargetJobId and S.TargetJobId ~= game.JobId then
                ServerMemory:BanUnjoinable(S.TargetJobId)
            end

            S.Teleporting = false
            S.TargetJobId = nil
            SetStatus("TELEPORT TIMED OUT")
        end

        ------------------------------------------------------------------------
        --// Teleports
        ------------------------------------------------------------------------

        local function TeleportToInstance(JobId, Status)
            if S.Teleporting then
                return false
            end

            S.Teleporting = true
            S.TargetJobId = JobId
            SetStatus(Status)

            if S.BeforeTeleport then
                local Ok, Error = pcall(S.BeforeTeleport)

                if not Ok then
                    warn("[AutoHunt] Before teleport failed:", Error)
                end
            end

            task.spawn(function()
                local Success, Error = pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, JobId, Player)
                end)

                if not Success then
                    TeleportFailed(Error)
                end
            end)

            return true
        end

        function ServerHop:Rejoin()
            local JobId = tostring(game.JobId or "")

            if JobId == "" then
                Notify("SERVER", "This server has no Job ID, so Rejoin is unavailable", 4)
                return false
            end

            Notify("SERVER", "Rejoining this server...")
            return TeleportToInstance(JobId, "REJOINING")
        end

        function ServerHop:Join(JobId)
            JobId = tostring(JobId or ""):gsub("%s+", "")

            if JobId == "" or JobId == game.JobId then
                Notify("SERVER", "That Job ID is empty or is this server", 4)
                return false
            end

            return TeleportToInstance(JobId, "JOINING SERVER")
        end

        --// One page of public servers with a free slot, other than this one.
        --// Returns the servers and the next page's cursor, or nil, nil and an
        --// error.
        function ServerHop:ReadPublicServers(Cursor)
            local Url = string.format(SERVER_LIST_URL, game.PlaceId)

            if type(Cursor) == "string" and Cursor ~= "" then
                Url ..= "&cursor=" .. HttpService:UrlEncode(Cursor)
            end

            local Success, Body = pcall(function()
                return game:HttpGet(Url)
            end)

            if not Success then
                return nil, nil, Body
            end

            local Decoded, Payload = pcall(function()
                return HttpService:JSONDecode(Body)
            end)

            if not Decoded or type(Payload) ~= "table" or type(Payload.data) ~= "table" then
                --// A rate limit can come back as an error body instead.
                local Errors = Decoded and type(Payload) == "table" and Payload.errors
                local Message = type(Errors) == "table" and type(Errors[1]) == "table" and Errors[1].message

                return nil, nil, Message or "The public server list response was invalid"
            end

            local NextCursor = type(Payload.nextPageCursor) == "string" and Payload.nextPageCursor or nil
            return Core.FilterPage(Payload.data, game.JobId), NextCursor
        end

        local function GetBan(JobId)
            return ServerMemory:GetBan(JobId)
        end

        --// Public servers over up to HOP_MAX_PAGES pages (fewer once there
        --// are enough), or nil and the error of the first page. Yields.
        local function ReadServerPool()
            local Pool, Cursor = {}, nil

            for Page = 1, Config.HOP_MAX_PAGES do
                local Servers, NextCursor, ReadError = ServerHop:ReadPublicServers(Cursor)

                if not Servers then
                    if Page == 1 then
                        return nil, ReadError
                    end

                    --// A later page failing still leaves the ones read.
                    warn("[AutoHunt] Server list page " .. Page .. " failed:", ReadError)
                    break
                end

                table.move(Servers, 1, #Servers, #Pool + 1, Pool)
                Cursor = NextCursor

                if not Cursor or Core.HasEnough(Pool, GetBan, Config) then
                    break
                end
            end

            return Pool
        end

        local function HopToSpawnTarget()
            local Boss = Settings:GetSelected()
            local JobId, SpawnIn = Boss and ServerMemory:FindSpawnTarget(Boss, game.JobId)

            if not JobId then
                return false
            end

            ServerMemory:MarkTargeted(JobId)
            print(string.format("[AutoHunt] Joining a known server: %s spawns in %ds", Boss, math.floor(SpawnIn)))
            Notify("SERVER HOP", string.format("%s spawns in %ds on a known server, joining", Boss, math.floor(SpawnIn)))
            return TeleportToInstance(JobId, "JOINING SPAWN TARGET")
        end

        local function HopToRandom()
            local Pool, ReadError = ReadServerPool()

            if not Pool then
                if Core.IsRateLimited(ReadError) then
                    S.Backoff = Core.NextBackoff(S.Backoff, Config)
                    SetStatus("RATE LIMITED, WAIT " .. S.Backoff .. "s")
                else
                    SetStatus("HOP FAILED")
                end

                Notify("SERVER HOP", "Could not read the server list: " .. tostring(ReadError), 6)
                return
            end

            S.Backoff = 0

            local Server, Tier = Core.Pick(Pool, GetBan, Config, math.random)

            if not Server then
                SetStatus("NO OTHER SERVER")
                Notify("SERVER HOP", "No other public server with a free slot was found", 6)
                return
            end

            print(string.format("[AutoHunt] Hop pool %d, tier %d, %d/%d players", #Pool, Tier, Server.Playing, Server.MaxPlayers))
            Notify("SERVER HOP", Tier == Core.TIER_BANNED and "Only visited servers left, joining the oldest" or "Joining another public server...")
            TeleportToInstance(Server.Id, "HOPPING")
        end

        function ServerHop:Hop()
            --// A second call while one is finding or teleporting does nothing.
            if S.Teleporting or S.Finding then
                return false
            end

            if HopToSpawnTarget() then
                return true
            end

            S.Finding = true
            SetStatus("FINDING SERVER")

            task.spawn(function()
                local Ok, Error = pcall(HopToRandom)
                S.Finding = false

                if not Ok then
                    SetStatus("HOP FAILED")
                    warn("[AutoHunt] Hop failed:", Error)
                end
            end)

            return true
        end

        Context.Connect(TeleportService.TeleportInitFailed, function(Who, _, ErrorMessage)
            --// Only a teleport of ours is reported here.
            if Who ~= Player or not S.Teleporting then
                return
            end

            TeleportFailed(ErrorMessage or "Teleport failed")
        end)

        return ServerHop
    end,
}
