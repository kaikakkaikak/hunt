-- CamperCheck finds players camping a boss zone: within
-- Config.CAMPER_RADIUS studs of its centre (X and Z only) both when this
-- player arrives and Config.CAMPER_IDLE_SECONDS later, having moved no more
-- than Config.CAMPER_MOVE_TOLERANCE in between. Campers found are
-- remembered by ServerMemory, so a later server with one of them in it is
-- recognised on join (KnownHere) before any walking.
local Core = {}

--// Players (list of { UserId, Name, X, Z }) within Radius of Center
--// ({ X, Z }), as UserId -> { Name, X, Z }.
function Core.Near(Players, Center, Radius)
    local Near = {}

    for _, Player in ipairs(Players) do
        local DX, DZ = Player.X - Center.X, Player.Z - Center.Z

        if DX * DX + DZ * DZ <= Radius * Radius then
            Near[tostring(Player.UserId)] = { Name = Player.Name, X = Player.X, Z = Player.Z }
        end
    end

    return Near
end

--// Players near in both Before and After that barely moved, as a list of
--// { UserId, Name } sorted by name.
function Core.FindCampers(Before, After, Cfg)
    local Campers = {}

    for UserId, Now in pairs(After) do
        local Then = Before[UserId]

        if Then then
            local DX, DZ = Now.X - Then.X, Now.Z - Then.Z

            if DX * DX + DZ * DZ <= Cfg.CAMPER_MOVE_TOLERANCE * Cfg.CAMPER_MOVE_TOLERANCE then
                table.insert(Campers, { UserId = UserId, Name = Now.Name })
            end
        end
    end

    table.sort(Campers, function(A, B)
        return A.Name < B.Name
    end)

    return Campers
end

function Core.Names(Campers)
    local Names = {}

    for _, Camper in ipairs(Campers) do
        table.insert(Names, Camper.Name)
    end

    return table.concat(Names, ", ")
end

return {
    Name = "CamperCheck",
    Dependencies = {"Config", "ServerMemory", "ZoneWalk"},
    Core = Core,

    Start = function(Context)
        local Config = Context.Config
        local ServerMemory = Context.ServerMemory
        local ZoneWalk = Context.ZoneWalk
        local Lifetime = Context.Lifetime
        local Players = Context.Services.Players
        local LocalPlayer = Context.Player

        local CamperCheck = { Name = "CamperCheck", Core = Core }

        --// Every other player with a character, as { UserId, Name, X, Z }.
        local function ReadPlayers()
            local List = {}

            for _, Other in ipairs(Players:GetPlayers()) do
                local Character = Other ~= LocalPlayer and Other.Character
                local Root = Character and Character:FindFirstChild("HumanoidRootPart")

                if Root then
                    local Position = Root.Position
                    table.insert(List, { UserId = Other.UserId, Name = Other.Name, X = Position.X, Z = Position.Z })
                end
            end

            return List
        end

        local function ReadIdentities()
            local List = {}

            for _, Other in ipairs(Players:GetPlayers()) do
                if Other ~= LocalPlayer then
                    table.insert(List, { UserId = Other.UserId, Name = Other.Name })
                end
            end

            return List
        end

        --// The name of a player here known to camp Zone, or nil.
        function CamperCheck:KnownHere(Zone)
            return ServerMemory:KnownCamper(ReadIdentities(), Zone)
        end

        --// Who is near Zone now, to compare with later; nil when the zone
        --// cannot be found.
        function CamperCheck:Snapshot(Zone)
            local _, Info = ZoneWalk.FindZone(Zone)

            if not Info then
                return nil
            end

            local Center = { X = Info.Center.X, Z = Info.Center.Z }

            return {
                Zone = Zone,
                Center = Center,
                At = os.clock(),
                Near = Core.Near(ReadPlayers(), Center, Config.CAMPER_RADIUS),
            }
        end

        --// The campers of Snapshot's zone (list of { UserId, Name }), waiting
        --// out the rest of CAMPER_IDLE_SECONDS first; they are remembered.
        --// Yields.
        function CamperCheck:Finish(Snapshot)
            if not Snapshot or next(Snapshot.Near) == nil then
                return {}
            end

            local Deadline = Snapshot.At + Config.CAMPER_IDLE_SECONDS

            while os.clock() < Deadline and Lifetime.Alive do
                task.wait(Deadline - os.clock())
            end

            local After = Core.Near(ReadPlayers(), Snapshot.Center, Config.CAMPER_RADIUS)
            local Campers = Core.FindCampers(Snapshot.Near, After, Config)

            if #Campers > 0 then
                ServerMemory:NoteCampers(Campers, Snapshot.Zone)
            end

            return Campers
        end

        return CamperCheck
    end,
}
