-- AutoHunt is the main loop. While running, with at least one boss selected:
--   1. after joining, wait for the server to load (Config.JOIN_SETTLE_SECONDS);
--      a player known to camp the boss's zone here, with no boss alive:
--      hop at once (CamperCheck);
--   2. walk to the selected boss's zone (Config.BOSS_ZONES) with the game's
--      auto off; nothing below runs until arrived (walk again, or hop after
--      Config.WALK_FAILS_BEFORE_HOP failed walks);
--   3. look for a selected boss, Config.SCAN_TRIES times, noting who stands
--      near the zone meanwhile;
--   4. found: switch the game's auto-fight on and wait until the boss is dead
--      or gone, give Config.LOOT_WAIT_SECONDS to pick up the drops, then hop
--      for the next one (Hop After Kill) or keep scanning; each kill is
--      counted per boss in Settings (saved);
--   5. not found and someone camps the zone: hop;
--   6. not found: when a selected boss's timer says it spawns within
--      Config.BOSS_WAIT_MAX_SECONDS (TARGET_WAIT_MAX_SECONDS on a server
--      joined as a spawn target), wait for it here;
--   7. otherwise (no timer, unreadable, or too long): hop.
-- Every hop first tells ServerMemory why this server was left and when its
-- boss spawns, so it is not hopped back to too soon, and this script is
-- queued to run again on the next server.
return {
    Name = "AutoHunt",
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

        --// Waits here when the soonest selected boss spawns within
        --// BOSS_WAIT_MAX_SECONDS (TARGET_WAIT_MAX_SECONDS on a spawn target).
        --// The boss when it showed up, or nil, the ServerMemory reason to
        --// hop and a description.
        local function WaitForSpawn()
            local Seconds, Name = BossTimer.GetSoonest(Data.Selected)
            local MaxWait = S.Expected and Config.TARGET_WAIT_MAX_SECONDS or Config.BOSS_WAIT_MAX_SECONDS

            if not Seconds then
                return nil, "NO_TIMER", "no readable timer"
            end

            if Seconds > MaxWait then
                return nil, "FAR", string.format("%s in %ds (> %ds)", Name, math.floor(Seconds), MaxWait)
            end

            local Deadline = os.clock() + Seconds + Config.BOSS_SPAWN_GRACE

            while IsActive() and os.clock() < Deadline do
                local Boss = BossFinder.Find(Data.Selected)

                if Boss then
                    return Boss
                end

                local Left = BossTimer.GetSeconds(Name)
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

        --// Keeps the game's auto on during a fight: retries a press that
        --// failed (button not on screen yet right after the walk), and
        --// presses again when the boss stops taking damage for
        --// AUTO_STALL_SECONDS (the game turned its auto off). Only after
        --// damage was seen this fight: a health we cannot read never drops,
        --// and pressing on that would toggle auto off and on forever.
        local function NewAutoKeeper(Boss)
            local LastHealths = ReadHealths(Boss)
            local LastDamageAt = os.clock()
            local SawDamage = false
            local Warned = false

            return function()
                if not GameAuto:IsEnabled() then
                    local Enabled, Error = GameAuto:Enable()

                    if not Enabled and not Warned then
                        Warned = true
                        NotifyAction("AUTO HUNT", "Auto mode: " .. tostring(Error) .. ", retrying", 6)
                    end

                    LastDamageAt = os.clock()
                    return
                end

                local Healths = ReadHealths(Boss)

                if TookDamage(LastHealths, Healths) then
                    SawDamage = true
                    LastDamageAt = os.clock()
                end

                LastHealths = Healths

                if SawDamage and os.clock() - LastDamageAt >= Config.AUTO_STALL_SECONDS then
                    print("[AutoHunt] " .. Boss.Name .. " stopped taking damage, pressing auto again")
                    GameAuto:Repress()
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
            --// spawn target's longer wait over.
            S.Expected = false
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

            local Arrived, WalkError = ZoneWalk.WalkTo(Zone)

            if Arrived or not IsActive() then
                S.WalkFails = Arrived and 0 or S.WalkFails
                return Arrived
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

            --// A spawn target was joined to wait for its boss: others waiting
            --// for the same spawn are not a reason to leave.
            local Campers = S.Expected and {} or CamperCheck:Finish(Snapshot)

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

        local function Step()
            if not Data.Running then
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

            if LeaveKnownCamper(Zone) or not ReachZone(Zone) or not IsActive() then
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
