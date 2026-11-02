-- AutoHunt is the main loop. While running, with at least one boss selected:
--   1. after joining, wait for the server to load (Config.JOIN_SETTLE_SECONDS);
--      a player known to camp the boss's zone here, with no boss alive:
--      hop at once (CamperCheck);
--   2. walk to the selected boss's zone (Config.BOSS_ZONES) with the game's
--      auto off; nothing below runs until arrived (walk again, or hop after
--      Config.WALK_FAILS_BEFORE_HOP failed walks). The game's auto taking
--      over the walk means it was left on: it is pressed off and the walk
--      retried, up to Config.AUTO_OFF_TRIES times without counting as failed;
--   3. look for a selected boss, Config.SCAN_TRIES times, noting who stands
--      near the zone meanwhile;
--   4. found: switch the game's auto-fight on and wait until the boss is dead
--      or gone, give Config.LOOT_WAIT_SECONDS to pick up the drops, then hop
--      for the next one (Hop After Kill) or keep scanning; each kill is
--      counted per boss in Settings (saved);
--   5. not found: when a selected boss's timer says it spawns within
--      Config.BOSS_WAIT_MAX_SECONDS (TARGET_WAIT_MAX_SECONDS on a server
--      joined as a spawn target), wait for it here, campers or not: a boss
--      about to spawn beats any other server. The wait follows the live
--      timer, so a boss that shows up a little late is not missed;
--   6. not found and someone camps the zone: hop;
--   7. otherwise (no timer, unreadable, or too long): hop.
-- The known-camper check on join and the retry of a failed hop also stay
-- when the boss spawns soon.
-- Every hop first tells ServerMemory why this server was left and when its
-- boss spawns, so it is not hopped back to too soon, and this script is
-- queued to run again on the next server. A hop that fails is retried as is
-- (no walk or scan in between), unless a selected boss is alive by then.
local Core = {}

--// The boss spawning in Seconds is worth staying for.
function Core.SpawnsSoon(Seconds, MaxWait)
    return Seconds ~= nil and Seconds <= MaxWait
end

--// The wait's deadline after a timer reading Left (or nil) at Now: moved
--// to Left + BOSS_SPAWN_GRACE from now while the timer still counts, never
--// past Cap (so a stuck timer cannot hold us forever), never earlier.
function Core.NextDeadline(Deadline, Left, Now, Cap, Cfg)
    if Left and Left > 0 then
        return math.min(math.max(Deadline, Now + Left + Cfg.BOSS_SPAWN_GRACE), Cap)
    end

    return Deadline
end

return {
    Name = "AutoHunt",
    Core = Core,
    Dependencies = {"Config", "Settings", "ServerMemory", "ServerHop", "BossFinder", "BossTimer", "ZoneWalk", "GameAuto", "CamperCheck"},

    Start = function(Context)
        local Config = Context.Config
        local Settings = Context.Settings
        local ServerMemory = Context.ServerMemory
        local ServerHop = Context.ServerHop
        local CamperCheck = Context.CamperCheck
        local BossFinder = Context.BossFinder
        local BossTimer = Context.BossTimer
        local ZoneWalk = Context.ZoneWalk
        local GameAuto = Context.GameAuto
        local Lifetime = Context.Lifetime
        local NotifyAction = Context.NotifyAction

        local IDLE_WAIT = 0.5

        local AutoHunt = {
            Name = "AutoHunt",
            S = {
                Status = "STOPPED",
                --// The boss being fought, or nil.
                Target = nil,
                --// The reload is queued for the next server already.
                Queued = false,
                --// Walks to the zone that failed in a row.
                WalkFails = 0,
                --// The known-camper check on join is done.
                JoinChecked = false,
                --// This server was joined as a spawn target: wait longer.
                Expected = false,
                --// The game's auto pressed off this server after it took
                --// over a walk.
                AutoOffs = 0,
                --// A hop that failed, to retry: { Reason, Detail }, or nil.
                PendingHop = nil,
            },
        }

        local S = AutoHunt.S
        local Data = Settings.Data

        local function SetStatus(Text)
            S.Status = Text
        end

        function AutoHunt:GetStatus()
            return S.Status
        end

        local function IsActive()
            return Lifetime.Alive and Data.Running
        end

        local function HasSelection()
            return next(Data.Selected) ~= nil
        end

        local function GetQueueFunction()
            return (type(queue_on_teleport) == "function" and queue_on_teleport)
                or (type(queueonteleport) == "function" and queueonteleport)
                or (type(syn) == "table" and syn.queue_on_teleport)
                or (type(fluxus) == "table" and fluxus.queue_on_teleport)
                or nil
        end

        --// Runs this script again on the next server with the same settings
        --// and server memory. Queued once per server, from ServerHop right
        --// before its first teleport (after this server was remembered).
        local function QueueReload()
            if S.Queued then
                return true
            end

            local Queue = GetQueueFunction()

            if not Queue or not Context.ReloadSource then
                return false
            end

            local Source = string.format(
                "getgenv().AutoHuntResume = %q\ngetgenv().AutoHuntMemory = %q\n%s",
                Settings:Encode(),
                ServerMemory:Encode(),
                Context.ReloadSource
            )
            local Ok, Error = pcall(Queue, Source)

            if not Ok then
                warn("[AutoHunt] queue_on_teleport failed:", Error)
                return false
            end

            S.Queued = true
            return true
        end

        --// A selected boss after up to SCAN_TRIES looks, or nil.
        local function Scan()
            for Try = 1, Config.SCAN_TRIES do
                if not IsActive() then
                    return nil
                end

                SetStatus(string.format("SCANNING  %d / %d", Try, Config.SCAN_TRIES))

                local Boss = BossFinder.Find(Data.Selected)

                if Boss then
                    return Boss
                end

                task.wait(Config.SCAN_INTERVAL)
            end

            return nil
        end

        local function GetMaxWait()
            return S.Expected and Config.TARGET_WAIT_MAX_SECONDS or Config.BOSS_WAIT_MAX_SECONDS
        end

        --// The soonest selected boss's seconds and name when it spawns
        --// within the wait allowed here, or nil.
        local function SoonestSpawn()
            local Seconds, Name = BossTimer.GetSoonest(Data.Selected)

            if Core.SpawnsSoon(Seconds, GetMaxWait()) then
                return Seconds, Name
            end

            return nil
        end

        --// Waits here when the soonest selected boss spawns within
        --// BOSS_WAIT_MAX_SECONDS (TARGET_WAIT_MAX_SECONDS on a spawn target).
        --// The boss when it showed up, or nil, the ServerMemory reason to
        --// hop and a description.
        local function WaitForSpawn()
            local Seconds, Name = BossTimer.GetSoonest(Data.Selected)
            local MaxWait = GetMaxWait()

            if not Seconds then
                return nil, "NO_TIMER", "no readable timer"
            end

            if not Core.SpawnsSoon(Seconds, MaxWait) then
                return nil, "FAR", string.format("%s in %ds (> %ds)", Name, math.floor(Seconds), MaxWait)
            end

            print(string.format("[AutoHunt] %s spawns in %ds, waiting", Name, math.floor(Seconds)))

            local Now = os.clock()
            local Cap = Now + MaxWait + Config.BOSS_SPAWN_GRACE
            local Deadline = Core.NextDeadline(Now, Seconds, Now, Cap, Config)

            while IsActive() and os.clock() < Deadline do
                local Boss = BossFinder.Find(Data.Selected)

                if Boss then
                    return Boss
                end

                local Left = BossTimer.GetSeconds(Name)
                Deadline = Core.NextDeadline(Deadline, Left, os.clock(), Cap, Config)
                SetStatus(string.format("WAITING  %s  //  %s s", Name, Left and tostring(math.floor(Left)) or "?"))
                task.wait(Config.WATCH_INTERVAL)
            end

            return nil, "NO_SPAWN", Name .. " did not spawn"
        end

        --// Names a game may keep the boss's health under, as an attribute
        --// on the model or a NumberValue / IntValue inside it.
        local HEALTH_NAMES = { "Health", "HP", "CurrentHealth", "Hp" }

        --// Every health reading found on the boss (source -> number): the
        --// Humanoid's and any custom one, since games often leave the
        --// Humanoid at full health and track the real one elsewhere.
        local function ReadHealths(Boss)
            local Healths = {}
            local Humanoid = Boss:FindFirstChildOfClass("Humanoid")

            if Humanoid then
                Healths.Humanoid = Humanoid.Health
            end

            for _, Name in ipairs(HEALTH_NAMES) do
                local Attribute = Boss:GetAttribute(Name)

                if type(Attribute) == "number" then
                    Healths["@" .. Name] = Attribute
                end

                local Value = Boss:FindFirstChild(Name, true)

                if Value and (Value:IsA("NumberValue") or Value:IsA("IntValue")) then
                    Healths[Name] = Value.Value
                end
            end

            return Healths
        end

        --// True when any reading in Now is lower than the same one in Before.
        local function TookDamage(Before, Now)
            for Source, Health in pairs(Now) do
                if Before[Source] and Health < Before[Source] then
                    return true
                end
            end

            return false
        end

        --// Where our character stands, faces and walks to, or nil.
        local function ReadPose()
            local Character = Context.Player.Character
            local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
            local Root = Character and Character:FindFirstChild("HumanoidRootPart")

            if not Humanoid or not Root then
                return nil
            end

            return { Position = Root.Position, Look = Root.CFrame.LookVector, WalkTo = Humanoid.WalkToPoint }
        end

        local function FlatDistance(A, B)
            return Vector3.new(A.X - B.X, 0, A.Z - B.Z).Magnitude
        end

        --// Our character moved, turned or got a new walk target since
        --// Before: something (the game's auto) is driving it.
        local function PoseChanged(Before, Now)
            if not Before or not Now then
                return false
            end

            return FlatDistance(Before.Position, Now.Position) >= Config.AUTO_ACTIVE_MOVE
                or FlatDistance(Before.WalkTo, Now.WalkTo) > 1
                or Before.Look:Dot(Now.Look) < 0.95
        end

        --// Keeps the game's auto on during a fight:
        --//   - retries a press that failed (button not on screen yet);
        --//   - checks every press (GameAuto.Core.NextCheck): no movement,
        --//     turn or damage within AUTO_CONFIRM_SECONDS means the press
        --//     turned auto off (it was on already), so press again;
        --//   - presses again when the boss stops taking damage for
        --//     AUTO_STALL_SECONDS (the game turned its auto off). Only after
        --//     damage was seen: a health we cannot read never drops.
        local function NewAutoKeeper(Boss)
            local LastHealths = ReadHealths(Boss)
            local LastDamageAt = os.clock()
            local SawDamage = false
            local Warned = false
            --// The press being checked: { Since, Presses, Pose }, or nil.
            local Check = nil

            local function StartCheck(Presses)
                Check = { Since = os.clock(), Presses = Presses, Pose = ReadPose() }
            end

            local function Confirm(Damaged)
                if not Check then
                    return
                end

                local Active = Damaged or PoseChanged(Check.Pose, ReadPose())
                local Action = GameAuto.Core.NextCheck(Check, Active, os.clock(), Config)

                if Action == "press" then
                    print(string.format("[AutoHunt] Auto shows no effect, pressing again (%d / %d)", Check.Presses + 1, Config.AUTO_CONFIRM_TRIES))
                    GameAuto:Repress()
                    StartCheck(Check.Presses + 1)
                    LastDamageAt = os.clock()
                elseif Action ~= "wait" then
                    Check = nil
                end
            end

            return function()
                if not GameAuto:IsEnabled() then
                    local Enabled, Error = GameAuto:Enable()

                    if not Enabled and not Warned then
                        Warned = true
                        NotifyAction("AUTO HUNT", "Auto mode: " .. tostring(Error) .. ", retrying", 6)
                    end

                    if Enabled then
                        StartCheck(0)
                    end

                    LastDamageAt = os.clock()
                    return
                end

                local Healths = ReadHealths(Boss)
                local Damaged = TookDamage(LastHealths, Healths)

                if Damaged then
                    SawDamage = true
                    LastDamageAt = os.clock()
                end

                LastHealths = Healths
                Confirm(Damaged)

                if not Check and SawDamage and os.clock() - LastDamageAt >= Config.AUTO_STALL_SECONDS then
                    print("[AutoHunt] " .. Boss.Name .. " stopped taking damage, pressing auto again")
                    GameAuto:Repress()
                    StartCheck(0)
                    SawDamage = false
                    LastDamageAt = os.clock()
                end
            end
        end

        local function Fight(Boss)
            S.Target = Boss
            SetStatus("FIGHTING  " .. Boss.Name)
            NotifyAction("AUTO HUNT", Boss.Name .. " found, using the game's auto", 5)

            local KeepAuto = NewAutoKeeper(Boss)

            while IsActive() and BossFinder.IsAlive(Boss) do
                KeepAuto()
                task.wait(Config.WATCH_INTERVAL)
            end

            --// Left the loop while still running: the boss died or was
            --// removed, which is how this game shows a kill. Stop does not count.
            if IsActive() then
                local Kills = Settings:AddKill(Boss.Name)
                print(string.format("[AutoHunt] %s killed (%d total)", Boss.Name, Kills))
                SetStatus("LOOTING  " .. Boss.Name)
                task.wait(Config.LOOT_WAIT_SECONDS)
            end

            S.Target = nil
            GameAuto:Disable()
        end

        --// The selected boss's timer now, for ServerMemory, or nil.
        local function ReadSpawnIn()
            local BossName = Settings:GetSelected()
            return BossName and BossTimer.GetSeconds(BossName) or nil
        end

        --// Remembers why this server is left (a ServerMemory reason).
        local function Remember(Reason)
            local Entry = ServerMemory:Leave(game.JobId, Reason, ReadSpawnIn(), Settings:GetSelected())
            local Now = os.time()
            --// %d needs whole numbers; timer readings may not be.
            local Spawn = Entry.SpawnAt and string.format(", spawn in %ds", math.floor(Entry.SpawnAt - Now)) or ""

            print(string.format("[AutoHunt] Leaving: %s, banned %ds%s (%s)", Reason, math.floor(Entry.Until - Now), Spawn, ServerMemory:Summary()))
        end

        --// Waits for one hop attempt to leave or fail. Yields.
        local function Hop(Reason, Detail)
            print("[AutoHunt] Hopping: " .. Reason .. (Detail and ", " .. Detail or ""))
            S.PendingHop = nil
            Remember(Reason)

            ServerHop:Hop()
            SetStatus("HOPPING  //  " .. ServerHop:GetStatus())

            local Deadline = os.clock() + Config.TELEPORT_TIMEOUT

            while ServerHop:IsBusy() and os.clock() < Deadline and Lifetime.Alive do
                SetStatus("HOPPING  //  " .. ServerHop:GetStatus())
                task.wait(IDLE_WAIT)
            end

            if ServerHop:IsBusy() then
                ServerHop:CancelTeleport()
            end

            --// Still here: the hop failed. Try again after a pause, with the
            --// spawn target's longer wait over, and without scanning again
            --// for a boss that was just killed or is not here.
            S.Expected = false
            S.PendingHop = { Reason = Reason, Detail = Detail }
            SetStatus("HOP FAILED  //  " .. ServerHop:GetStatus())
            task.wait(ServerHop:GetRetryDelay())
        end

        --// Once per server, before walking: a known camper of Zone is here
        --// and no boss is alive to fight anyway. Hops; true when it did.
        local function LeaveKnownCamper(Zone)
            if S.JoinChecked or not Config.CAMPER_CHECK then
                return false
            end

            S.JoinChecked = true
            local Camper = CamperCheck:KnownHere(Zone)

            if not Camper or BossFinder.Find(Data.Selected) then
                return false
            end

            local Seconds, Name = SoonestSpawn()

            if Seconds then
                print(string.format("[AutoHunt] Known camper %s here, but %s spawns in %ds: staying", Camper, Name, math.floor(Seconds)))
                return false
            end

            NotifyAction("AUTO HUNT", Camper .. " camps " .. Zone .. " here, hopping", 5)
            Hop("CAMPED", "known camper " .. Camper)
            return true
        end

        --// Walks to Zone. True once arrived; otherwise counts the failure
        --// and hops after WALK_FAILS_BEFORE_HOP in a row.
        local function ReachZone(Zone)
            --// Auto stays off on the way: the game's auto would fight
            --// whatever is near instead of walking on.
            GameAuto:Disable()
            SetStatus("WALKING TO  " .. Zone)

            local Arrived, WalkError, Kind = ZoneWalk.WalkTo(Zone)

            if Arrived or not IsActive() then
                S.WalkFails = Arrived and 0 or S.WalkFails
                return Arrived
            end

            --// Something else drove the character: the game's auto was on
            --// (left on before the hop) although we thought it off.
            if Kind == "hijacked" and S.AutoOffs < Config.AUTO_OFF_TRIES then
                S.AutoOffs += 1
                print(string.format("[AutoHunt] The game's auto took over the walk, pressing it off (%d / %d)", S.AutoOffs, Config.AUTO_OFF_TRIES))
                NotifyAction("AUTO HUNT", "Game auto was on, turning it off", 4)
                GameAuto:ForceOff()
                return false
            end

            S.WalkFails += 1
            warn(string.format("[AutoHunt] Walk to zone failed (%d / %d):", S.WalkFails, Config.WALK_FAILS_BEFORE_HOP), WalkError)
            NotifyAction("AUTO HUNT", "Walk failed: " .. tostring(WalkError), 6)
            SetStatus("WALK FAILED  //  " .. tostring(WalkError))

            if S.WalkFails >= Config.WALK_FAILS_BEFORE_HOP then
                S.WalkFails = 0
                Hop("WALK_FAILED", "cannot reach " .. Zone)
            else
                task.wait(Config.SCAN_INTERVAL)
            end

            return false
        end

        --// At the zone: fight the boss when it is here or spawns soon,
        --// otherwise hop. Campers make the next server come sooner.
        local function HuntAtZone(Zone)
            print("[AutoHunt] Arrived at " .. Zone .. ", scanning")

            local Snapshot = Config.CAMPER_CHECK and CamperCheck:Snapshot(Zone) or nil
            local Boss = Scan()

            if not IsActive() then
                return
            end

            --// Found right away: fight it. No camper check: whoever stood
            --// still near it was fighting it too, not camping.
            if Boss then
                Fight(Boss)

                if IsActive() and Data.HopAfterKill then
                    Hop("KILLED")
                end

                return
            end

            --// Campers only matter when the boss is not about to spawn:
            --// others waiting for the same spawn are no reason to lose it.
            --// A spawn target was joined to wait for its boss anyway.
            local Campers = (S.Expected or SoonestSpawn()) and {} or CamperCheck:Finish(Snapshot)

            if IsActive() and #Campers > 0 then
                NotifyAction("AUTO HUNT", "Campers at " .. Zone .. ": " .. CamperCheck.Core.Names(Campers), 5)
                Hop("CAMPED", "campers " .. CamperCheck.Core.Names(Campers))
                return
            end

            local Reason, Detail
            Boss, Reason, Detail = WaitForSpawn()

            if not IsActive() then
                return
            end

            if Boss then
                Fight(Boss)

                if IsActive() and Data.HopAfterKill then
                    Hop("KILLED")
                end
            else
                Hop(Reason, Detail)
            end
        end

        --// Retries a hop that failed, unless a selected boss is alive now or
        --// spawns soon. True when it did.
        local function RetryPendingHop()
            local Pending = S.PendingHop

            if not Pending then
                return false
            end

            if BossFinder.Find(Data.Selected) or SoonestSpawn() then
                S.PendingHop = nil
                return false
            end

            Hop(Pending.Reason, Pending.Detail)
            return true
        end

        local function Step()
            if not Data.Running then
                S.PendingHop = nil
                SetStatus("STOPPED")
                return
            end

            if not HasSelection() then
                SetStatus("NO BOSS SELECTED")
                return
            end

            local BossName = Settings:GetSelected()
            local Zone = Config.BOSS_ZONES[BossName]

            if not Zone then
                SetStatus("NO ZONE FOR  " .. tostring(BossName))
                return
            end

            if RetryPendingHop() or LeaveKnownCamper(Zone) or not ReachZone(Zone) or not IsActive() then
                return
            end

            HuntAtZone(Zone)
        end

        --// The UI's Hop Now: still comes back running on the next server.
        function AutoHunt:HopNow()
            Remember("MANUAL")
            return ServerHop:Hop()
        end

        --// Queued once ServerHop is about to teleport, so the memory sent
        --// along already has this server in it.
        ServerHop:SetBeforeTeleport(function()
            if not QueueReload() then
                NotifyAction("AUTO HUNT", "queue_on_teleport unavailable: run the script again after the hop", 8)
            end
        end)

        S.Expected = ServerMemory:TakeExpect(game.JobId)

        if S.Expected then
            print("[AutoHunt] Joined as a spawn target: waiting up to " .. Config.TARGET_WAIT_MAX_SECONDS .. "s for the boss")
        end

        function AutoHunt:SetRunning(Running)
            Data.Running = Running == true
            Settings:Save()

            if not Data.Running then
                GameAuto:Disable()
            end
        end

        task.spawn(function()
            SetStatus("WAITING FOR SERVER")
            task.wait(Config.JOIN_SETTLE_SECONDS)

            while Lifetime.Alive do
                local Ok, Error = pcall(Step)

                if not Ok then
                    warn("[AutoHunt] Step failed:", Error)
                    SetStatus("ERROR (see console)")
                    task.wait(Config.HOP_RETRY_DELAY)
                end

                task.wait(IDLE_WAIT)
            end
        end)

        return AutoHunt
    end,
}
