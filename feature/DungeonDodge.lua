-- DungeonDodge acts on the boss's skill warnings for AutoDungeon
-- (SkillWatcher finds them): flies into the nearest green safe zone, or
-- out of the danger zones we stand in to the nearest safe spot that keeps
-- the boss within reach.
return {
    Name = "DungeonDodge",
    Dependencies = {"Config", "SafeMove", "SkillWatcher"},

    Start = function(Context)
        local Config = Context.Config
        local SafeMove = Context.SafeMove
        local SkillCore = Context.SkillWatcher.Core

        --// Within this of a safe zone's centre counts as inside it.
        local ZONE_ARRIVE = 1.5
        local SPOT_ARRIVE = 2

        local DungeonDodge = { Name = "DungeonDodge" }

        local function NearestMajor(Position, Majors)
            local Best, BestGap = nil, math.huge

            for _, Major in ipairs(Majors) do
                local Gap = (Position - Major.Position).Magnitude

                if Gap < BestGap then
                    Best, BestGap = Major, Gap
                end
            end

            return Best
        end

        --// One leg toward Point; a frame's rest when nothing was flown.
        local function Step(Point, Arrive)
            if SafeMove.StepToward(Point, Arrive) ~= "moved" then
                task.wait(Config.DUNGEON_TICK)
            end
        end

        local function EnterSafeZone(Zones, Position, SetStatus)
            if #Zones == 0 then
                return false
            end

            table.sort(Zones, function(Left, Right)
                return (Left.Position - Position).Magnitude < (Right.Position - Position).Magnitude
            end)

            SetStatus("SAFE ZONE")
            Step(Zones[1].Position, ZONE_ARRIVE)
            return true
        end

        local function LeaveDanger(Hazards, Position, Majors, SetStatus)
            if not SkillCore.InAny(Hazards, Position.X, Position.Z, Config.DUNGEON_DODGE_MARGIN) then
                return false
            end

            local Major = NearestMajor(Position, Majors)
            local Anchor = Major and { X = Major.Position.X, Z = Major.Position.Z }

            local X, Z = SkillCore.FindSafeSpot(Position.X, Position.Z, Hazards, Anchor, Config, function(PX, PZ)
                local Point = SafeMove.HoverPoint(Vector3.new(PX, Position.Y, PZ))
                return Point ~= nil and SafeMove.IsClear(Position, Point)
            end)

            if not X then
                SetStatus("DODGE: NO SAFE SPOT")
                return false
            end

            SetStatus("DODGING")
            Step(Vector3.new(X, Position.Y, Z), SPOT_ARRIVE)
            return true
        end

        --// Acts on the warnings: green Zones first, then the danger
        --// Hazards. True while it did (the fight waits this step).
        function DungeonDodge.Handle(Zones, Hazards, Position, Majors, SetStatus)
            return EnterSafeZone(Zones, Position, SetStatus) or LeaveDanger(Hazards, Position, Majors, SetStatus)
        end

        return DungeonDodge
    end,
}
