-- AutoDungeon clears the Halloween dungeon by flying (SafeMove) and
-- fighting (the game's auto, switched on once per dungeon):
--   rooms' monsters -> ritual pillar -> miniboss -> boss door -> boss,
-- in the order DungeonTargets.Pick gives (pillar, boss or miniboss, then
-- monsters), hitting any monster in range on the way. Bosses and minibosses
-- are hit from behind. With
-- nothing in sight it flies into the next room not visited yet
-- (DungeonRooms), since monsters only spawn once someone gets there, and
-- waits there Config.DUNGEON_ROOM_WAIT for them.
--
-- Attacking (DungeonAttack), while something is within ATTACK_RANGE: the
-- game's own auto (Config.DUNGEON_ATTACK_MODE "auto"), or skill
-- DUNGEON_SKILL_KEY every DUNGEON_SKILL_INTERVAL and the buff
-- DUNGEON_BUFF_KEY every DUNGEON_BUFF_INTERVAL ("keys").
--
-- Once a room is cleared, the boxes in it are collected (their prompt is
-- used) before the next room. Checking rooms and collecting boxes can each
-- be switched off in the UI (Settings.Data.DungeonRooms / DungeonLoot).
--
-- The end: once the final boss (Config.DUNGEON_FINAL_BOSS_NAMES) has been
-- seen and is dead, the end chest is flown to and opened (always, whatever
-- COLLECT BOXES says), then Replay is pressed on the summary that follows
-- (DungeonEnd) and the next run starts from the first room.
--
-- While a miniboss or the boss is alive, its skill warnings (SkillWatcher)
-- come first, as picked in the UI: GREEN SAFE ZONE (on by default) flies
-- into the green zone; DODGE BOSS SKILLS (off by default) leaves any other
-- warning we stand in. With both off the fight goes on behind the boss.
return {
    Name = "AutoDungeon",
    Dependencies = {"Config", "Settings", "SafeMove", "SkillWatcher", "DungeonTargets", "DungeonRooms", "DungeonEnd", "DungeonAttack", "DungeonPoints", "DungeonDodge", "GameAuto", "AutoHunt"},

    Start = function(Context)
        local Config = Context.Config
        local Settings = Context.Settings
        local SafeMove = Context.SafeMove
        local SkillWatcher = Context.SkillWatcher
        local DungeonTargets = Context.DungeonTargets
        local DungeonRooms = Context.DungeonRooms
        local DungeonEnd = Context.DungeonEnd
        local DungeonAttack = Context.DungeonAttack
        local DungeonPoints = Context.DungeonPoints
        local DungeonDodge = Context.DungeonDodge
        local GameAuto = Context.GameAuto
        local AutoHunt = Context.AutoHunt
        local Lifetime = Context.Lifetime
        local SkillCore = SkillWatcher.Core
        local TargetCore = DungeonTargets.Core

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
                --// Model -> which side of it is tried (TurnEighths).
                Side = setmetatable({}, { __mode = "k" }),
                --// Prompt -> times it was used (boxes, the door).
                PromptTries = {},
                --// Majors alive in the last scan (for SourceIsMajor).
                Majors = {},
                --// Mobs alive in the last scan.
                Mobs = {},
                SawMajor = false,
                --// The final boss was seen alive this run.
                SawFinal = false,
                --// The pillar was a target this run: walls may be flown through.
                SawPillar = false,
                --// The run's end: { Since, ChestUsed, Clicks, ClickedAt }, or nil.
                Ending = nil,
                --// The dungeon folder this run is in.
                RunRoot = nil,
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

        local function InRange(Entry, Position)
            if not Entry.Model.Parent or not DungeonTargets.IsAlive(Entry.Model) then
                return false
            end

            local Live = DungeonTargets.GetPosition(Entry.Model) or Entry.Position
            return Distance(Position, Live) - Entry.Radius <= Config.DUNGEON_ATTACK_RANGE
        end

        --// The target, or any boss or monster we pass by, is in reach.
        local function TargetInRange()
            local Position = SafeMove.GetPosition()

            if not Position then
                return false
            end

            if S.Target and InRange(S.Target, Position) then
                return true
            end

            for _, List in ipairs({ S.Majors, S.Mobs }) do
                for _, Entry in ipairs(List) do
                    if InRange(Entry, Position) then
                        return true
                    end
                end
            end

            return false
        end

        DungeonAttack.Run(IsActive, TargetInRange, function()
            return S.Target and S.Target.Kind
        end)

        ------------------------------------------------------------------------
        --// Fighting
        ------------------------------------------------------------------------

        --// Next to the target, Gap (default ATTACK_DISTANCE) from its edge:
        --// behind a boss or miniboss, on our side of anything else.
        --// A side we could not reach is replaced by the next one round it
        --// (S.Side), so a spot inside a wall or over a gap is not retried.
        local UsePrompt

        --// A prompt by its path: the game can remake a box's prompt, which
        --// would start its tries over every time.
        local function PromptKey(Prompt)
            return Prompt:GetFullName()
        end
        local SightedApproach

        local function ApproachPoint(Target, Position, Gap, SideOverride)
            local Away = Vector3.new(Position.X - Target.Position.X, 0, Position.Z - Target.Position.Z)

            if Target.Kind == "major" and Target.Look and Data.DungeonBackstab then
                Away = -Target.Look
            elseif Away.Magnitude < 0.1 then
                Away = Vector3.new(1, 0, 0)
            end

            local Side = SideOverride or (Target.Model and S.Side[Target.Model]) or 0
            local X, Z = TargetCore.TurnEighths(Away.Unit.X, Away.Unit.Z, Side)
            return Target.Position + Vector3.new(X, 0, Z) * (Target.Radius + (Gap or Config.DUNGEON_ATTACK_DISTANCE))
        end

        --// The spot to hit Target from, starting at the wanted side and
        --// going round it until one has floor and the target in sight: a
        --// spot behind a wall from it would never hit it.
        function SightedApproach(Target, Position)
            local First = Target.Model and S.Side[Target.Model] or 0

            for Turn = 0, 7 do
                local Point = ApproachPoint(Target, Position, nil, First + Turn)
                local Hover = SafeMove.HoverPoint(Point)

                if Hover and SafeMove.CanSee(Hover, Target.Position) then
                    if Turn > 0 and Target.Model then
                        S.Side[Target.Model] = First + Turn
                    end

                    return Point
                end
            end

            return ApproachPoint(Target, Position)
        end

        local function NoteBlocked(Target, Why)
            print(string.format("[AutoDungeon] Blocked on the way to %s: %s", Target.Name, tostring(Why)))
            SetStatus(string.format("CAN'T REACH %s: %s", Target.Name, tostring(Why)))
            S.Side[Target.Model] = (S.Side[Target.Model] or 0) + 1
            local Count = (S.Blocked[Target.Model] or 0) + 1
            S.Blocked[Target.Model] = Count

            if Count >= Config.DUNGEON_BLOCKED_TRIES then
                S.Blocked[Target.Model] = nil
                S.SkipUntil[Target.Model] = os.clock() + Config.DUNGEON_UNREACHABLE_SECONDS
                print(string.format("[AutoDungeon] Cannot reach %s (%s): skipped for %ds", Target.Name, tostring(Why), Config.DUNGEON_UNREACHABLE_SECONDS))
            end
        end

        local function Fight(Target, Position, Hazards)
            if not S.Target or S.Target.Model ~= Target.Model then
                print(string.format("[AutoDungeon] Target: %s (%s)", Target.Name, Target.Kind))

                if Target.Kind == "pillar" and not S.SawPillar then
                    S.SawPillar = true
                    SafeMove.SetFlyThrough(true)
                    print("[AutoDungeon] Pillar reached: walls may be flown through from now on")
                end
                S.Side[Target.Model] = nil

                if Target.Kind == "major" and Data.DungeonBackstab then
                    print(Target.Look and ("[AutoDungeon] Hitting " .. Target.Name .. " from behind")
                        or ("[AutoDungeon] " .. Target.Name .. " has no facing to get behind (no HumanoidRootPart / PrimaryPart)"))
                end
            end

            S.Target = Target
            SafeMove.SetFacing(Target.Position)
            SetStatus(string.format("FIGHTING %s (%s)", Target.Name, Target.Kind))

            local Point = SightedApproach(Target, Position)

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
                --// Reached: the next spot is the wanted side again (behind a
                --// boss), not the one a blocked try turned to.
                S.Side[Target.Model] = nil
                task.wait(Config.DUNGEON_TICK)
            end
        end

        --// Flies in front of a prompt's part (our side: a door is a wall)
        --// and uses the prompt once in range: the boss door, a box.
        function UsePrompt(Prompt, Position, Label)
            local PromptPosition = DungeonTargets.GetPosition(Prompt.Parent)
            local Reach = math.max(Prompt.MaxActivationDistance * 0.6, 2)

            S.Target = nil
            SafeMove.SetFacing(PromptPosition)

            if Distance(Position, PromptPosition) > Prompt.MaxActivationDistance - 0.5 then
                SetStatus(Label)
                local Front = ApproachPoint({ Position = PromptPosition, Radius = 0 }, Position, Reach)
                local Result, Why = SafeMove.StepToward(Front, APPROACH_ARRIVE)

                if Result == "blocked" then
                    SetStatus(Label .. ": UNREACHABLE (" .. tostring(Why) .. ")")
                    print(string.format("[AutoDungeon] %s unreachable: %s", Label, tostring(Why)))
                    --// Counts as a try, so an unreachable box is given up on.
                    S.PromptTries[PromptKey(Prompt)] = (S.PromptTries[PromptKey(Prompt)] or 0) + 1
                    task.wait(IDLE_WAIT)
                end

                --// Arrived but the prompt's part sits high: try anyway.
                if Result ~= "arrived" then
                    return
                end
            end

            local Try = (S.PromptTries[PromptKey(Prompt)] or 0) + 1
            S.PromptTries[PromptKey(Prompt)] = Try
            SetStatus(string.format("%s (try %d)", Label, Try))
            print(string.format("[AutoDungeon] %s: %s, try %d", Label, Prompt:GetFullName(), Try))
            DungeonTargets.UsePrompt(Prompt, Try)
        end

        local function OpenDoor(Prompt, Position)
            UsePrompt(Prompt, Position, "OPENING THE BOSS DOOR")
        end

        ------------------------------------------------------------------------
        --// Main loop
        ------------------------------------------------------------------------

        local function Scan(Position)
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
                Pickable.Id = Entry.Model
                Pickable.Skipped = (S.SkipUntil[Entry.Model] or 0) > Now
                --// Only close monsters are asked (a ray each).
                Pickable.Visible = Entry.Kind == "mob"
                    and Distance(Position, Entry.Position) <= Config.DUNGEON_ENGAGE_RADIUS
                    and SafeMove.CanSee(Position, Entry.Position)
                table.insert(Targets, Pickable)
            end

            S.Majors, S.Mobs = Majors, Mobs
            SafeMove.SetIgnore(Models)
            return Targets
        end

        --// Flies into Room; once there, waits up to DUNGEON_ROOM_WAIT for
        --// its monsters to spawn.
        --// Flies to Point (a room, a point set in the UI); once there,
        --// waits up to DUNGEON_ROOM_WAIT for what spawns there. Hooks:
        --// OnBlocked(Why), OnMoved(), OnArrived().
        local function FlyAndWait(Point, Label, Hooks)
            S.Target = nil
            SafeMove.SetFacing(nil)
            SetStatus(Label)

            local Result, Why = SafeMove.StepToward(Point, Config.DUNGEON_ROOM_ARRIVE)

            if Result == "blocked" then
                if Why ~= "no character" then
                    print(string.format("[AutoDungeon] Blocked on the way to %s: %s", Label, tostring(Why)))
                    Hooks.OnBlocked(Why)
                end

                task.wait(Config.DUNGEON_TICK)
                return
            end

            if Result ~= "arrived" then
                Hooks.OnMoved()
                return
            end

            Hooks.OnArrived()
            SetStatus("WAITING FOR MONSTERS: " .. Label)
            local Deadline = os.clock() + Config.DUNGEON_ROOM_WAIT

            while IsActive() and os.clock() < Deadline and #DungeonTargets.Scan() == 0 do
                task.wait(Config.DUNGEON_TICK)
            end
        end

        local function VisitRoom(Room)
            FlyAndWait(DungeonRooms.AimPoint(Room), "ROOM " .. Room.Name, {
                OnBlocked = function(Why)
                    DungeonRooms.NoteBlocked(Room, Why)
                end,
                OnMoved = function()
                    DungeonRooms.NoteMoved(Room)
                end,
                OnArrived = function()
                    DungeonRooms.MarkDone(Room)
                end,
            })
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

        local function IsFinalAlive()
            for _, Major in ipairs(S.Majors) do
                if TargetCore.IsFinalBoss(Major.Name, Config) then
                    return true
                end
            end

            return false
        end

        --// A new run: every room and box start over. The game's auto is
        --// left as it is (pressing it here would toggle it off).
        local function ResetRun()
            S.SawMajor, S.SawFinal, S.SawPillar, S.Ending, S.IdleSince = false, false, false, nil, nil
            SafeMove.SetFlyThrough(false)
            S.Target = nil
            S.PromptTries = {}
            S.RunRoot = DungeonTargets.GetRoot()
            DungeonRooms.Reset()
            DungeonPoints.Reset()
        end

        --// A point set in the UI (the miniboss's, the boss's room).
        local function GoToPoint(Stage, Point)
            FlyAndWait(Point, "THE " .. string.upper(Stage) .. " POINT", {
                OnBlocked = function() end,
                OnMoved = function() end,
                OnArrived = function()
                    DungeonPoints.MarkReached(Stage)
                end,
            })
        end

        --// Opens the end chest, then presses Replay on the summary.
        local function FinishRun(Position)
            local Ending = S.Ending

            if not Ending.ChestUsed then
                --// The nearest box once the boss is down is the end chest;
                --// it is kept, so other rooms' boxes are not flown to.
                Ending.Chest = Ending.Chest or DungeonTargets.FindLoot(Position, function(Prompt)
                    return (S.PromptTries[PromptKey(Prompt)] or 0) < Config.DUNGEON_LOOT_TRIES
                end, Config.DUNGEON_END_CHEST_RADIUS)

                local Chest = Ending.Chest

                if Chest then
                    local Tries = S.PromptTries[PromptKey(Chest)] or 0

                    --// Opened (its prompt gone or switched off), or given up.
                    if not Chest.Parent or not Chest.Enabled or Tries >= Config.DUNGEON_LOOT_TRIES then
                        print("[AutoDungeon] End chest done")
                        Ending.ChestUsed = true
                        return
                    end

                    UsePrompt(Chest, Position, "OPENING THE END CHEST")
                    return
                end

                --// The chest may take a moment to show up.
                if os.clock() - Ending.Since < Config.DUNGEON_END_CHEST_WAIT then
                    SafeMove.Release()
                    SetStatus("WAITING FOR THE END CHEST")
                    task.wait(IDLE_WAIT)
                    return
                end

                Ending.ChestUsed = true
            end

            SafeMove.Release()
            local Button = DungeonEnd.FindReplay()

            if not Button then
                if Ending.Clicks > 0 then
                    --// The summary closed after our press: the next run.
                    print("[AutoDungeon] Replay pressed: starting the next run")
                    return ResetRun()
                end

                if os.clock() - Ending.Since >= Config.DUNGEON_REPLAY_WAIT then
                    return Idle("DUNGEON CLEARED (no Replay button)")
                end

                SetStatus("WAITING FOR THE SUMMARY")
                task.wait(IDLE_WAIT)
                return
            end

            if Ending.Clicks >= Config.DUNGEON_REPLAY_CLICKS then
                return Idle("REPLAY DOES NOT RESPOND")
            end

            if os.clock() - Ending.ClickedAt < Config.DUNGEON_REPLAY_RETRY then
                task.wait(IDLE_WAIT)
                return
            end

            --// Replay may teleport us: run again on the other side.
            AutoHunt:QueueReload()
            Ending.Clicks += 1
            Ending.ClickedAt = os.clock()
            SetStatus("PRESSING REPLAY (try " .. Ending.Clicks .. ")")
            print("[AutoDungeon] Pressing Replay: " .. Button:GetFullName() .. " via " .. tostring(DungeonEnd.Press(Button)))
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

            --// The game swaps the dungeon's folder as it loads the next part
            --// (after the pillar): the same run goes on, rooms stay done.
            if DungeonTargets.GetRoot() ~= S.RunRoot then
                S.RunRoot = DungeonTargets.GetRoot()
                print("[AutoDungeon] The dungeon's folder changed: going on")
            end

            local Targets = Scan(Position)
            SkillWatcher.SetEnabled(#S.Majors > 0 and (Data.DungeonDodge or Data.DungeonSafeZone))
            S.SawMajor = S.SawMajor or #S.Majors > 0

            local FinalAlive = IsFinalAlive()
            S.SawFinal = S.SawFinal or FinalAlive

            if S.SawFinal and not FinalAlive and not S.Ending then
                print("[AutoDungeon] Final boss down: opening the end chest")
                S.Ending = { Since = os.clock(), ChestUsed = false, Clicks = 0, ClickedAt = -math.huge }
            end

            if S.Ending then
                return FinishRun(Position)
            end

            local Hazards, Zones = SkillWatcher.GetActive()

            --// Picked in the UI (DODGE BOSS SKILLS, GREEN SAFE ZONE).
            if not Data.DungeonDodge then
                Hazards = {}
            end

            if not Data.DungeonSafeZone then
                Zones = {}
            end

            if DungeonDodge.Handle(Zones, Hazards, Position, S.Majors, SetStatus) then
                return
            end

            local Picked = TargetCore.Pick(Targets, Flat(Position), S.Target and S.Target.Model, Config)

            if Picked then
                S.IdleSince, S.DoorLogged, S.NothingLogged = nil, false, false
                return Fight(Picked.Entry, Position, Hazards)
            end

            --// Both can be switched off in the UI (CHECK ROOMS, COLLECT BOXES).
            --// Only boxes close by (the room we are in): one across the map
            --// would pull us past rooms not done yet.
            local Loot = Data.DungeonLoot and DungeonTargets.FindLoot(Position, function(Prompt)
                return (S.PromptTries[PromptKey(Prompt)] or 0) < Config.DUNGEON_LOOT_TRIES
            end, Config.DUNGEON_LOOT_RADIUS)

            if Loot then
                S.IdleSince = nil

                if S.LootLogged ~= Loot then
                    S.LootLogged = Loot
                    local Gap = Distance(Position, DungeonTargets.GetPosition(Loot.Parent))
                    print(string.format("[AutoDungeon] Box: %s (%d studs)", Loot:GetFullName(), math.floor(Gap)))
                end

                return UsePrompt(Loot, Position, "COLLECTING " .. Loot.Parent.Name)
            end

            --// Past the pillar: the points set in the UI lead on (the
            --// miniboss's room, then the boss door and the boss's room).
            local PillarAlive = false

            for _, Target in ipairs(Targets) do
                PillarAlive = PillarAlive or Target.Kind == "pillar"
            end

            local Stage, Point = DungeonPoints.Next(S.SawPillar, PillarAlive, S.Majors)
            local StageDoor = Stage == "boss" and DungeonTargets.FindDoor()

            if StageDoor then
                S.IdleSince = nil
                return OpenDoor(StageDoor, Position)
            end

            if Stage then
                S.IdleSince = nil
                return GoToPoint(Stage, Point)
            end

            local Room = nil

            --// With points set, rooms are only explored before the pillar:
            --// after it they would lead back.
            if Data.DungeonRooms and not (S.SawPillar and DungeonPoints.HasAny()) then
                DungeonRooms.MarkNearby(Position)
                Room = DungeonRooms.Next(Position)
            end

            if Room then
                S.IdleSince = nil
                return VisitRoom(Room)
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

            if not S.NothingLogged then
                S.NothingLogged = true
                print("[AutoDungeon] Nothing to fight, no room, box or door left: waiting")
            end

            Idle("NOTHING TO FIGHT")
        end

        --// Only one of AutoHunt and AutoDungeon drives the character.
        function AutoDungeon:SetRunning(Running)
            Data.Dungeon = Running == true

            if Data.Dungeon then
                --// Off on entering: believed, not pressed, so stopping the
                --// hunt below cannot toggle it on by mistake.
                GameAuto:AssumeOff()
                DungeonAttack.Reset()
                AutoHunt:SetRunning(false)
                ResetRun()
            end

            Settings:Save()

            if not Data.Dungeon then
                S.Target = nil
                SafeMove.Release()
                GameAuto:Disable()
            end
        end

        Lifetime.OnEnd(function()
            if Data.Dungeon then
                GameAuto:Disable()
            end
        end)

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
