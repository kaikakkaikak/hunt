-- DungeonPoints keeps the points the player sets in the UI (stand there,
-- press SET MINIBOSS POINT / SET BOSS POINT; saved by Settings) and says
-- which one AutoDungeon should fly to next, once the ritual pillar is done:
--   1. the miniboss point, until it is reached; the miniboss spawns there;
--   2. once the miniboss has been seen and is dead: the boss door (opened
--      by AutoDungeon), then the boss point, until it is reached.
-- A point not set is skipped, and AutoDungeon falls back to the rooms.
local Core = {}

--// "miniboss", "boss" or nil: where to fly next. F = { SawPillar,
--// PillarAlive, MinibossSeen, MinibossAlive, MiniReached, BossReached,
--// HasMini, HasBoss }.
function Core.NextStage(F)
    if not F.SawPillar or F.PillarAlive then
        return nil
    end

    local MinibossDone = F.MinibossSeen and not F.MinibossAlive

    if not MinibossDone then
        if F.HasMini and not F.MiniReached then
            return "miniboss"
        end

        return nil
    end

    if F.HasBoss and not F.BossReached then
        return "boss"
    end

    return nil
end

--// A saved point as { X, Y, Z } numbers, or nil when it is not one.
function Core.CleanPoint(Saved)
    if type(Saved) ~= "table" then
        return nil
    end

    for _, Axis in ipairs({ "X", "Y", "Z" }) do
        if type(Saved[Axis]) ~= "number" or Saved[Axis] ~= Saved[Axis] then
            return nil
        end
    end

    return { X = Saved.X, Y = Saved.Y, Z = Saved.Z }
end

return {
    Name = "DungeonPoints",
    Dependencies = {"Config", "Settings", "DungeonTargets"},
    Core = Core,

    Start = function(Context)
        local Config = Context.Config
        local Settings = Context.Settings
        local Player = Context.Player
        local TargetCore = Context.DungeonTargets.Core

        local NAMES = { Miniboss = true, Boss = true }
        local STAGE_POINT = { miniboss = "Miniboss", boss = "Boss" }

        local Data = Settings.Data
        local DungeonPoints = {
            Name = "DungeonPoints",
            Core = Core,
            S = { Reached = {}, MinibossSeen = false },
        }
        local S = DungeonPoints.S

        --// The saved point Name ("Miniboss" or "Boss") as a Vector3, or nil.
        function DungeonPoints.Get(Name)
            local Point = Core.CleanPoint(Data.DungeonPoints[Name])
            return Point and Vector3.new(Point.X, Point.Y, Point.Z) or nil
        end

        --// Saves where the character stands as point Name. True when set.
        function DungeonPoints.Set(Name)
            local Character = Player.Character
            local Root = Character and Character:FindFirstChild("HumanoidRootPart")

            if not NAMES[Name] or not Root then
                return false
            end

            local Position = Root.Position
            local Points = table.clone(Data.DungeonPoints)
            Points[Name] = { X = Position.X, Y = Position.Y, Z = Position.Z }
            Data.DungeonPoints = Points
            Settings:Save()
            print(string.format("[AutoDungeon] %s point set: %d, %d, %d", Name, math.floor(Position.X), math.floor(Position.Y), math.floor(Position.Z)))
            return true
        end

        function DungeonPoints.Clear()
            Data.DungeonPoints = {}
            Settings:Save()
            print("[AutoDungeon] Points cleared")
        end

        function DungeonPoints.HasAny()
            return DungeonPoints.Get("Miniboss") ~= nil or DungeonPoints.Get("Boss") ~= nil
        end

        --// A new run: no point reached, no miniboss seen.
        function DungeonPoints.Reset()
            S.Reached, S.MinibossSeen = {}, false
        end

        function DungeonPoints.MarkReached(Stage)
            if not S.Reached[Stage] then
                print("[AutoDungeon] Reached the " .. Stage .. " point")
            end

            S.Reached[Stage] = true
        end

        --// Where to fly next from the last scan: the stage ("miniboss",
        --// "boss") and its point, or nil. Majors = the bosses alive.
        function DungeonPoints.Next(SawPillar, PillarAlive, Majors)
            local MinibossAlive = false

            for _, Major in ipairs(Majors) do
                if not TargetCore.IsFinalBoss(Major.Name, Config) then
                    MinibossAlive = true
                end
            end

            S.MinibossSeen = S.MinibossSeen or MinibossAlive

            local Stage = Core.NextStage({
                SawPillar = SawPillar,
                PillarAlive = PillarAlive,
                MinibossSeen = S.MinibossSeen,
                MinibossAlive = MinibossAlive,
                MiniReached = S.Reached.miniboss == true,
                BossReached = S.Reached.boss == true,
                HasMini = DungeonPoints.Get("Miniboss") ~= nil,
                HasBoss = DungeonPoints.Get("Boss") ~= nil,
            })

            return Stage, Stage and DungeonPoints.Get(STAGE_POINT[Stage]) or nil
        end

        return DungeonPoints
    end,
}
