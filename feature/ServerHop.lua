-- ServerHop moves between servers, ported from
-- Automated-Industry-Complex/Features/ServerHop.lua:
--   Rejoin this server, Hop to a random public server with a free slot, and
--   Join a server by Job ID. The danger-group, join-alert and player-log
--   parts of the original are left out.
return {
    Name = "ServerHop",
    Dependencies = {},

    Start = function(Context)
        local HttpService = Context.Services.HttpService
        local TeleportService = game:GetService("TeleportService")
        local Player = Context.Player
        local NotifyAction = Context.NotifyAction

        --// Pages of the public server list a hop reads before giving up.
        local HOP_MAX_PAGES = 4
        --// The same notice is not shown again within this.
        local NOTICE_COOLDOWN = 8
        local SERVER_LIST_URL = "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"

        local ServerHop = {
            Name = "ServerHop",
            S = {
                Teleporting = false,
                --// A hop is reading the server list.
                Finding = false,
                Status = "IDLE",
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

        --// A teleport that never finished nor failed: let the next try through.
        function ServerHop:CancelTeleport()
            S.Teleporting = false
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
            SetStatus(Status)

            task.spawn(function()
                local Success, Error = pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, JobId, Player)
                end)

                if not Success then
                    S.Teleporting = false
                    SetStatus("TELEPORT FAILED")
                    Notify("SERVER", tostring(Error), 6)
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
                return nil, nil, "The public server list response was invalid"
            end

            local Servers = {}

            for _, Server in ipairs(Payload.data) do
                local Playing = tonumber(Server.playing)
                local MaxPlayers = tonumber(Server.maxPlayers)

                if type(Server.id) == "string" and Server.id ~= game.JobId
                    and Playing and MaxPlayers and Playing < MaxPlayers
                then
                    table.insert(Servers, {
                        Id = Server.id,
                        Playing = Playing,
                        MaxPlayers = MaxPlayers,
                        Ping = tonumber(Server.ping),
                        FPS = tonumber(Server.fps),
                    })
                end
            end

            local NextCursor = type(Payload.nextPageCursor) == "string" and Payload.nextPageCursor or nil
            return Servers, NextCursor
        end

        --// The Job ID of a random public server with a free slot other than
        --// this one, or nil and why (nil error: there is none). Yields.
        local function FindOtherServer()
            local Cursor

            for _ = 1, HOP_MAX_PAGES do
                local Servers, NextCursor, ReadError = ServerHop:ReadPublicServers(Cursor)

                if not Servers then
                    return nil, ReadError
                end

                if #Servers > 0 then
                    return Servers[math.random(1, #Servers)].Id
                end

                Cursor = NextCursor

                if not Cursor then
                    break
                end
            end

            return nil, nil
        end

        function ServerHop:Hop()
            --// A second call while one is finding or teleporting does nothing.
            if S.Teleporting or S.Finding then
                return false
            end

            S.Finding = true
            SetStatus("FINDING SERVER")

            task.spawn(function()
                local Target, Error = FindOtherServer()

                S.Finding = false

                if Target then
                    Notify("SERVER HOP", "Joining another public server...")
                    TeleportToInstance(Target, "HOPPING")
                elseif Error then
                    SetStatus("HOP FAILED")
                    Notify("SERVER HOP", "Could not read the server list: " .. tostring(Error), 6)
                else
                    SetStatus("NO OTHER SERVER")
                    Notify("SERVER HOP", "No other public server with a free slot was found", 6)
                end
            end)

            return true
        end

        Context.Connect(TeleportService.TeleportInitFailed, function(Who, _, ErrorMessage)
            --// Only a teleport of ours is reported here.
            if Who ~= Player or not S.Teleporting then
                return
            end

            S.Teleporting = false
            SetStatus("TELEPORT FAILED")
            Notify("SERVER", tostring(ErrorMessage or "Teleport failed"), 6)
        end)

        return ServerHop
    end,
}
