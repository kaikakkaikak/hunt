-- AutoHunt is the main loop. While running, with at least one boss selected:
--   1. after joining, wait for the server to load (Config.JOIN_SETTLE_SECONDS);
--   2. walk to the boss zone (Config.BOSS_ZONE);
--   3. look for a selected boss, Config.SCAN_TRIES times;
--   4. found: switch the game's auto-fight on and wait until the boss is dead
--      or gone, give Config.LOOT_WAIT_SECONDS to pick up the drops, then hop
--      for the next one (Hop After Kill) or keep scanning;
--   5. not found: when a selected boss's timer says it spawns within
--      Config.BOSS_WAIT_MAX_SECONDS, wait for it here;
--   6. otherwise (no timer, unreadable, or too long): queue this script for
--      the next server and hop.
return {
    Name = "AutoHunt",
    Dependencies = {"Config", "Settings", "ServerHop", "BossFinder", "BossTimer", "ZoneWalk", "GameAuto"},

    Start = function(Context)
        local Config = Context.Config
        local Settings = Context.Settings
        local ServerHop = Context.ServerHop
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

        --// Runs this script again on the next server with the same settings.
        local function QueueReload()
            if S.Queued then
                return true
            end

            local Queue = GetQueueFunction()

            if not Queue or not Context.ReloadSource then
                return false
            end

            local Source = string.format("getgenv().AutoHuntResume = %q\n%s", Settings:Encode(), Context.ReloadSource)
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
        --// BOSS_WAIT_MAX_SECONDS. The boss when it showed up, or nil and why
        --// (the reason to hop).
        local function WaitForSpawn()
            local Seconds, Name = BossTimer.GetSoonest(Data.Selected)

            if not Seconds then
                return nil, "NO TIMER"
            end

            if Seconds > Config.BOSS_WAIT_MAX_SECONDS then
                return nil, string.format("%s IN %ds (> %ds)", Name, math.floor(Seconds), Config.BOSS_WAIT_MAX_SECONDS)
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

            return nil, Name .. " DID NOT SPAWN"
        end

        local function Fight(Boss)
            S.Target = Boss
            SetStatus("FIGHTING  " .. Boss.Name)
            NotifyAction("AUTO HUNT", Boss.Name .. " found, using the game's auto", 5)

            local Enabled, Error = GameAuto:Enable()

            if not Enabled then
                NotifyAction("AUTO HUNT", "Auto mode: " .. tostring(Error), 6)
            end

            while IsActive() and BossFinder.IsAlive(Boss) do
                task.wait(Config.WATCH_INTERVAL)
            end

            if IsActive() then
                SetStatus("LOOTING  " .. Boss.Name)
                task.wait(Config.LOOT_WAIT_SECONDS)
            end

            S.Target = nil
            GameAuto:Disable()
        end

        --// Waits for one hop attempt to leave or fail. Yields.
        local function Hop()
            if not QueueReload() then
                NotifyAction("AUTO HUNT", "queue_on_teleport unavailable: run the script again after the hop", 8)
            end

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

            --// Still here: the hop failed. Try again after a pause.
            SetStatus("HOP FAILED  //  " .. ServerHop:GetStatus())
            task.wait(Config.HOP_RETRY_DELAY)
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

            SetStatus("WALKING TO  " .. Config.BOSS_ZONE)

            local Arrived, WalkError = ZoneWalk.WalkTo(Config.BOSS_ZONE)

            if not Arrived then
                warn("[AutoHunt] Walk to zone failed:", WalkError)
                NotifyAction("AUTO HUNT", "Walk failed: " .. tostring(WalkError), 6)
                SetStatus("WALK FAILED  //  " .. tostring(WalkError))
                task.wait(Config.SCAN_INTERVAL)
            else
                print("[AutoHunt] Arrived at " .. Config.BOSS_ZONE .. ", scanning")
            end

            if not IsActive() then
                return
            end

            local Boss = Scan()
            local Reason

            if not Boss and IsActive() then
                Boss, Reason = WaitForSpawn()
            end

            if not IsActive() then
                return
            end

            if Boss then
                Fight(Boss)

                if IsActive() and Data.HopAfterKill then
                    Hop()
                end
            else
                print("[AutoHunt] Hopping:", Reason)
                Hop()
            end
        end

        --// The UI's Hop Now: still comes back running on the next server.
        function AutoHunt:HopNow()
            QueueReload()
            return ServerHop:Hop()
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
