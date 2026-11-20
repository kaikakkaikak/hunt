-- DungeonAttack does the hitting for AutoDungeon while something is in
-- range (Run's InRange says so):
--   "auto" (Config.DUNGEON_ATTACK_MODE): the game's own auto, pressed on
--          once, the first time something is in range after START DUNGEON
--          or joining a server (the game always has it off on entering).
--          Never pressed again while the run goes on: the button is a
--          toggle, so a second press would switch it off;
--   "keys": skill Config.DUNGEON_SKILL_KEY every DUNGEON_SKILL_INTERVAL and
--          the buff DUNGEON_BUFF_KEY every DUNGEON_BUFF_INTERVAL.
return {
    Name = "DungeonAttack",
    Dependencies = {"Config", "GameAuto", "KeyPress"},

    Start = function(Context)
        local Config = Context.Config
        local GameAuto = Context.GameAuto
        local KeyPress = Context.KeyPress
        local Lifetime = Context.Lifetime

        local DungeonAttack = { Name = "DungeonAttack", S = { Warned = false } }
        local S = DungeonAttack.S

        local function KeepAutoOn()
            if GameAuto:IsEnabled() then
                return
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
        function DungeonAttack.Run(IsActive, InRange)
            task.spawn(function()
                local SkillKey = Enum.KeyCode[Config.DUNGEON_SKILL_KEY]
                local BuffKey = Enum.KeyCode[Config.DUNGEON_BUFF_KEY]
                local LastBuff = -math.huge

                while Lifetime.Alive do
                    if IsActive() and InRange() then
                        if Config.DUNGEON_ATTACK_MODE == "auto" then
                            KeepAutoOn()
                        else
                            if os.clock() - LastBuff >= Config.DUNGEON_BUFF_INTERVAL then
                                LastBuff = os.clock()
                                KeyPress.Tap(BuffKey)
                            end

                            KeyPress.Tap(SkillKey)
                        end
                    end

                    task.wait(Config.DUNGEON_SKILL_INTERVAL)
                end
            end)
        end

        return DungeonAttack
    end,
}
