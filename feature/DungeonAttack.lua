-- DungeonAttack does the hitting for AutoDungeon while something is in
-- range (Run's InRange says so):
--   "auto" (Config.DUNGEON_ATTACK_MODE): the game's own auto, pressed on
--          once, the first time something is in range after START DUNGEON
--          or joining a server (the game always has it off on entering).
--          Pressed again only when the button is seen to look off (the
--          game switched it off): the button is a toggle, so a press on a
--          guess could switch it off;
--   "keys": skill Config.DUNGEON_SKILL_KEY every DUNGEON_SKILL_INTERVAL and
--          the buff DUNGEON_BUFF_KEY every DUNGEON_BUFF_INTERVAL.
-- The ritual pillar is hit with the keys (and a click, DUNGEON_PILLAR_CLICK)
-- in both modes: the game's auto picks its own targets and goes for the
-- monsters around it instead.
return {
    Name = "DungeonAttack",
    Dependencies = {"Config", "GameAuto", "KeyPress"},

    Start = function(Context)
        local Config = Context.Config
        local GameAuto = Context.GameAuto
        local KeyPress = Context.KeyPress
        local Lifetime = Context.Lifetime

        --// The button's look is checked this often while the auto should be
        --// on; it must look off this many checks in a row to be pressed.
        local LOOK_CHECK_SECONDS = 2
        local OFF_CHECKS = 2

        local DungeonAttack = { Name = "DungeonAttack", S = { Warned = false, CheckedAt = -math.huge, OffChecks = 0 } }
        local S = DungeonAttack.S

        --// The game can switch its auto off by itself (e.g. away from the
        --// monsters for a while). Pressed on again only when the button
        --// is seen to look off (GameAuto learns the look), never on a guess.
        local function LooksSwitchedOff()
            if os.clock() - S.CheckedAt < LOOK_CHECK_SECONDS then
                return false
            end

            S.CheckedAt = os.clock()
            S.OffChecks = GameAuto:ReadState() == false and S.OffChecks + 1 or 0
            return S.OffChecks >= OFF_CHECKS
        end

        local function KeepAutoOn()
            if GameAuto:IsEnabled() then
                if not LooksSwitchedOff() then
                    return
                end

                S.OffChecks = 0
                print("[GameAuto] The auto button looks off: the game switched it off, pressing it on")
                GameAuto:AssumeOff()
            end

            local Ok, Why = GameAuto:Enable()

            if Ok then
                print("[AutoDungeon] Game auto switched on")
            elseif not S.Warned then
                S.Warned = true
                warn("[AutoDungeon] Could not switch the game's auto on: " .. tostring(Why))
            end
        end

        --// A new START DUNGEON: warn again if the auto cannot be found.
        function DungeonAttack.Reset()
            S.Warned = false
        end

        --// Hits while IsActive() and InRange() hold, until unloaded.
        --// TargetKind() is the kind being fought ("pillar", ...) or nil.
        function DungeonAttack.Run(IsActive, InRange, TargetKind)
            task.spawn(function()
                local SkillKey = Enum.KeyCode[Config.DUNGEON_SKILL_KEY]
                local BuffKey = Enum.KeyCode[Config.DUNGEON_BUFF_KEY]
                local LastBuff = -math.huge

                local function HitWithKeys(Click)
                    if os.clock() - LastBuff >= Config.DUNGEON_BUFF_INTERVAL then
                        LastBuff = os.clock()
                        KeyPress.Tap(BuffKey)
                    end

                    KeyPress.Tap(SkillKey)

                    if Click then
                        KeyPress.ClickCenter()
                    end
                end

                while Lifetime.Alive do
                    if IsActive() and InRange() then
                        local OnPillar = TargetKind() == "pillar"

                        if Config.DUNGEON_ATTACK_MODE == "auto" then
                            KeepAutoOn()
                        end

                        if OnPillar or Config.DUNGEON_ATTACK_MODE ~= "auto" then
                            HitWithKeys(OnPillar and Config.DUNGEON_PILLAR_CLICK)
                        end
                    end

                    task.wait(Config.DUNGEON_SKILL_INTERVAL)
                end
            end)
        end

        return DungeonAttack
    end,
}
