-- AutoDungeon clears the Halloween dungeon by flying (SafeMove) and using
-- skills, without the game's own auto:
--   rooms' monsters -> ritual pillar -> miniboss -> boss door -> boss,
-- hitting every monster on the way (DungeonTargets.Pick decides).
--
-- Attacking: skill Config.DUNGEON_SKILL_KEY every DUNGEON_SKILL_INTERVAL and
-- the buff Config.DUNGEON_BUFF_KEY every DUNGEON_BUFF_INTERVAL, while the
-- target is within Config.DUNGEON_ATTACK_RANGE.
--
-- While a miniboss or the boss is alive, its skill warnings (SkillWatcher)
-- come first: a green safe zone is flown into, a danger zone we stand in is
-- left for the nearest safe spot that keeps us close, and we do not fly into
-- one on the way to a target. Normal monsters' skills are not dodged.
return {
    Name = "AutoDungeon",
    Dependencies = {"Config", "Settings", "SafeMove", "SkillWatcher", "DungeonTargets", "KeyPress", "GameAuto", "AutoHunt"},

    Start = function(Context)
        local Config = Context.Config
        local Settings = Context.Settings
        local SafeMove = Context.SafeMove
        local SkillWatcher = Context.SkillWatcher
        local DungeonTargets = Context.DungeonTargets
        local KeyPress = Context.KeyPress
        local GameAuto = Context.GameAuto
        local AutoHunt = Context.AutoHunt
        local Lifetime = Context.Lifetime
        local SkillCore = SkillWatcher.Core
        local TargetCore = DungeonTargets.Core

        --// Within this of a safe zone's centre counts as inside it.
        local ZONE_ARRIVE = 1.5
        --// Within this of the point next to the target counts as there.
        local APPROACH_ARRIVE = 2
        local IDLE_WAIT = 0.5

        local Data = Settings.Data

        local AutoDungeon = {
            Name = "AutoDungeon",
            S = {
                Status = "STOPPED",
                --// The scan entry being fought, or nil.
                Target = nil,
                --// Model -> os.clock() until which it is left alone.
                SkipUntil = setmetatable({}, { __mode = "k" }),
                --// Model -> blocked steps toward it in a row.
                Blocked = setmetatable({}, { __mode = "k" }),
                DoorTries = 0,
                --// Majors alive in the last scan (for SourceIsMajor).
                Majors = {},
                --// Mobs alive in the last scan.
                Mobs = {},
                SawMajor = false,
                IdleSince = nil,
            },
        }

        local S = AutoDungeon.S

        local function SetStatus(Text)
            S.Status = Text
        end

        function AutoDungeon:GetStatus()
            return S.Status
        end

        function AutoDungeon:IsRunning()
            return Data.Dungeon == true
        end

        local function IsActive()
            return Lifetime.Alive and Data.Dungeon
        end

        local function Flat(Vector)
            return { X = Vector.X, Y = Vector.Y, Z = Vector.Z }
        end

        local function Distance(A, B)
            return (A - B).Magnitude
        end

        ------------------------------------------------------------------------
        --// Whose skill is it
        ------------------------------------------------------------------------

        --// Inside a boss's model, or (outside any model) nearer a living
        --// boss or miniboss than to any monster.
        SkillWatcher.SourceIsMajor = function(Part)
            for _, Major in ipairs(S.Majors) do
                if Part:IsDescendantOf(Major.Model) then
                    return true
                end
            end

            for _, Mob in ipairs(S.Mobs) do
                if Part:IsDescendantOf(Mob.Model) then
                    return false
                end
            end

            local Nearest, NearestIsMajor = math.huge, false

            for _, List in ipairs({ S.Majors, S.Mobs }) do
                for _, Entry in ipairs(List) do
                    local Gap = Distance(Part.Position, Entry.Position)

                    if Gap < Nearest then
                        Nearest, NearestIsMajor = Gap, List == S.Majors
                    end
                end
            end

            return NearestIsMajor
        end

        --// A new warning stops the leg being flown, so the dodge starts now.
        SkillWatcher.OnWarning = SafeMove.Cancel

        ------------------------------------------------------------------------
        --// Attacking
        ------------------------------------------------------------------------

        local function TargetInRange()
            local Target = S.Target
            local Position = SafeMove.GetPosition()

            if not Target or not Position or not Target.Model.Parent or not DungeonTargets.IsAlive(Target.Model) then
                return false
            end

            local Live = DungeonTargets.GetPosition(Target.Model) or Target.Position
            return Distance(Position, Live) - Target.Radius <= Config.DUNGEON_ATTACK_RANGE
        end

        task.spawn(function()
            local SkillKey = Enum.KeyCode[Config.DUNGEON_SKILL_KEY]
            local BuffKey = Enum.KeyCode[Config.DUNGEON_BUFF_KEY]
            local LastBuff = -math.huge

            while Lifetime.Alive do
                if IsActive() and TargetInRange() then
                    if os.clock() - LastBuff >= Config.DUNGEON_BUFF_INTERVAL then
                        LastBuff = os.clock()
                        KeyPress.Tap(BuffKey)
                    end

                    KeyPress.Tap(SkillKey)
                end

                task.wait(Config.DUNGEON_SKILL_INTERVAL)
            end
        end)

        ------------------------------------------------------------------------
        --// Dodging
        ------------------------------------------------------------------------

        local function NearestMajor(Position)
            local Best, BestGap = nil, math.huge

            for _, Major in ipairs(S.Majors) do
                local Gap = Distance(Position, Major.Position)

                if Gap < BestGap then
                    Best, BestGap = Major, Gap
                end
            end

            return Best
        end

        --// Flies into the nearest green zone. True when there was one.
        local function EnterSafeZone(Zones, Position)
            if #Zones == 0 then
                return false
            end

            table.sort(Zones, function(Left, Right)
                return Distance(Left.Position, Position) < Distance(Right.Position, Position)
            end)

            SetStatus("SAFE ZONE")

            if SafeMove.StepToward(Zones[1].Position, ZONE_ARRIVE) ~= "moved" then
                task.wait(Config.DUNGEON_TICK)
            end

            return true
        end

        --// Leaves the danger zones we stand in. True while dodging.
        local function Dodge(Hazards, Position)
            if not SkillCore.InAny(Hazards, Position.X, Position.Z, Config.DUNGEON_DODGE_MARGIN) then
                return false
            end

            local Major = NearestMajor(Position)
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

            if SafeMove.StepToward(Vector3.new(X, Position.Y, Z), APPROACH_ARRIVE) ~= "moved" then
                task.wait(Config.DUNGEON_TICK)
            end

            return true
        end

        ------------------------------------------------------------------------
        --// Fighting
        ------------------------------------------------------------------------

        --// Next to the target, on our side of it, Gap (default
        --// ATTACK_DISTANCE) from its edge.
        local function ApproachPoint(Target, Position, Gap)
            local Away = Vector3.new(Position.X - Target.Position.X, 0, Position.Z - Target.Position.Z)

            if Away.Magnitude < 0.1 then
                Away = Vector3.new(1, 0, 0)
            end

            return Target.Position + Away.Unit * (Target.Radius + (Gap or Config.DUNGEON_ATTACK_DISTANCE))
        end

        local function NoteBlocked(Target, Why)
            print(string.format("[AutoDungeon] Blocked on the way to %s: %s", Target.Name, tostring(Why)))
            local Count = (S.Blocked[Target.Model] or 0) + 1
            S.Blocked[Target.Model] = Count

            if Count >= Config.DUNGEON_BLOCKED_TRIES then
                S.Blocked[Target.Model] = nil
                S.SkipUntil[Target.Model] = os.clock() + Config.DUNGEON_UNREACHABLE_SECONDS
                print(string.format("[AutoDungeon] Cannot reach %s (%s): skipped for %ds", Target.Name, tostring(Why), Config.DUNGEON_UNREACHABLE_SECONDS))
            end
        end

        local function Fight(Target, Position, Hazards)
            S.Target = Target
            SafeMove.SetFacing(Target.Position)
            SetStatus(string.format("FIGHTING %s (%s)", Target.Name, Target.Kind))

            local Point = ApproachPoint(Target, Position)

            --// Never fly into a warning: wait it out where we are.
            if SkillCore.InAny(Hazards, Point.X, Point.Z, Config.DUNGEON_DODGE_MARGIN) then
                SetStatus("WAITING OUT A SKILL")
                task.wait(Config.DUNGEON_TICK)
                return
            end

            local Result, Why = SafeMove.StepToward(Point, APPROACH_ARRIVE)

            if Result == "blocked" then
                --// Our own death is not the target's fault.
                if Why ~= "no character" then
                    NoteBlocked(Target, Why)
                end

                task.wait(Config.DUNGEON_TICK)
                return
            end

            S.Blocked[Target.Model] = nil

            if Result == "arrived" then
                task.wait(Config.DUNGEON_TICK)
            end
        end

        --// Flies in front of the door (our side: the door itself is a wall)
        --// and holds its prompt once in range.
        local function OpenDoor(Prompt, Position)
            local DoorPosition = DungeonTargets.GetPosition(Prompt.Parent)
            local Reach = math.max(Prompt.MaxActivationDistance * 0.6, 2)

            S.Target = nil
            SafeMove.SetFacing(DoorPosition)

            if Distance(Position, DoorPosition) > Prompt.MaxActivationDistance - 0.5 then
                SetStatus("FLYING TO THE BOSS DOOR")
                local Front = ApproachPoint({ Position = DoorPosition, Radius = 0 }, Position, Reach)
                local Result, Why = SafeMove.StepToward(Front, APPROACH_ARRIVE)

                if Result == "blocked" then
                    SetStatus("BOSS DOOR UNREACHABLE: " .. tostring(Why))
                    print("[AutoDungeon] Boss door unreachable: " .. tostring(Why))
                    task.wait(IDLE_WAIT)
                end

                --// Arrived but the prompt's part sits high: try anyway.
                if Result ~= "arrived" then
                    return
                end
            end

            S.DoorTries += 1
            SetStatus("OPENING THE BOSS DOOR (try " .. S.DoorTries .. ")")
            DungeonTargets.OpenDoor(Prompt, S.DoorTries)
        end

        ------------------------------------------------------------------------
        --// Main loop
        ------------------------------------------------------------------------

        local function Scan()
            local Now = os.clock()
            local Found = DungeonTargets.Scan()
            local Models, Majors, Mobs, Targets = {}, {}, {}, {}

            for _, Entry in ipairs(Found) do
                table.insert(Models, Entry.Model)

                if Entry.Kind == "major" then
                    table.insert(Majors, Entry)
                elseif Entry.Kind == "mob" then
                    table.insert(Mobs, Entry)
                end

                local Pickable = Flat(Entry.Position)
                Pickable.Kind = Entry.Kind
                Pickable.Entry = Entry
                Pickable.Skipped = (S.SkipUntil[Entry.Model] or 0) > Now
                table.insert(Targets, Pickable)
            end

            S.Majors, S.Mobs = Majors, Mobs
            SafeMove.SetIgnore(Models)
            return Targets
        end

        local function CountSkipped(Targets)
            local Count = 0

            for _, Target in ipairs(Targets) do
                if Target.Skipped then
                    Count += 1
                end
            end

            return Count
        end

        local function Idle(Text)
            S.Target = nil
            SafeMove.Release()
            SetStatus(Text)
            task.wait(IDLE_WAIT)
        end

        local function Step()
            if not IsActive() then
                SkillWatcher.SetEnabled(false)
                return Idle(Lifetime.Alive and "STOPPED" or "UNLOADED")
            end

            if not DungeonTargets.GetRoot() then
                return Idle("WAITING FOR THE DUNGEON (" .. Config.DUNGEON_ROOT_NAME .. " not in workspace)")
            end

            local Position = SafeMove.GetPosition()

            if not Position then
                return Idle("WAITING FOR THE CHARACTER")
            end

            local Targets = Scan()
            SkillWatcher.SetEnabled(#S.Majors > 0)
            S.SawMajor = S.SawMajor or #S.Majors > 0

            local Hazards, Zones = SkillWatcher.GetActive()

            if EnterSafeZone(Zones, Position) or Dodge(Hazards, Position) then
                return
            end

            local Picked = TargetCore.Pick(Targets, Flat(Position), Config)

            if Picked then
                S.IdleSince, S.DoorLogged = nil, false
                return Fight(Picked.Entry, Position, Hazards)
            end

            local Door = DungeonTargets.FindDoor()

            if Door then
                S.IdleSince = nil

                if not S.DoorLogged then
                    S.DoorLogged = true
                    print(string.format("[AutoDungeon] No monster, pillar or boss found (%d in the scan, %d skipped): going to the boss door %s",
                        #Targets, CountSkipped(Targets), Door:GetFullName()))
                end

                return OpenDoor(Door, Position)
            end

            S.IdleSince = S.IdleSince or os.clock()

            if S.SawMajor and os.clock() - S.IdleSince >= Config.DUNGEON_DONE_SECONDS then
                return Idle("DUNGEON CLEARED")
            end

            Idle("NOTHING TO FIGHT")
        end

        --// Only one of AutoHunt and AutoDungeon drives the character.
        function AutoDungeon:SetRunning(Running)
            Data.Dungeon = Running == true

            if Data.Dungeon then
                AutoHunt:SetRunning(false)
                GameAuto:Disable()
                S.SawMajor, S.IdleSince, S.DoorTries = false, nil, 0
            end

            Settings:Save()

            if not Data.Dungeon then
                S.Target = nil
                SafeMove.Release()
            end
        end

        if Data.Dungeon and Data.Running then
            AutoHunt:SetRunning(false)
        end

        task.spawn(function()
            while Lifetime.Alive do
                local Ok, Error = pcall(Step)

                if not Ok then
                    warn("[AutoDungeon] Step failed:", Error)
                    SetStatus("ERROR (see console)")
                    SafeMove.Release()
                    task.wait(IDLE_WAIT)
                end

                --// At least a frame per step, whatever Step did.
                task.wait()
            end
        end)

        return AutoDungeon
    end,
}
