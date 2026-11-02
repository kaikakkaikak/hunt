-- GameAuto switches the game's own auto-fight on and off by pressing its
-- button (Config.AUTO_BUTTON_NAMES / AUTO_BUTTON_TEXTS). The button is a
-- toggle we cannot read, so Enabled is only what we last pressed it to.
--
-- Since that guess can be wrong (auto left on from before a hop: pressing
-- "on" turns it off), every press during a fight is checked: no sign of the
-- auto working within Config.AUTO_CONFIRM_SECONDS means press again, up to
-- Config.AUTO_CONFIRM_TRIES times. Two re-presses go on -> off -> on, so the
-- fight ends up with auto on whichever way the guess was wrong.
local Core = {}

--// What to do about the last press: Check = { Since = os.clock() of the
--// press, Presses = re-presses made so far }, Active = a sign of the auto
--// working was seen since. "ok", "wait", "press" or "giveup".
function Core.NextCheck(Check, Active, Now, Cfg)
    if Active then
        return "ok"
    end

    if Now - Check.Since < Cfg.AUTO_CONFIRM_SECONDS then
        return "wait"
    end

    if Check.Presses < Cfg.AUTO_CONFIRM_TRIES then
        return "press"
    end

    return "giveup"
end

return {
    Name = "GameAuto",
    Dependencies = {"Config", "GuiClick"},
    Core = Core,

    Start = function(Context)
        local Config = Context.Config
        local GuiClick = Context.GuiClick
        local Player = Context.Player

        local GameAuto = {
            Name = "GameAuto",
            Core = Core,
            S = { Enabled = false },
        }

        local S = GameAuto.S

        local function Matches(List, Value)
            local Upper = string.upper(Value)

            for _, Wanted in ipairs(List) do
                if string.upper(Wanted) == Upper then
                    return true
                end
            end

            return false
        end

        function GameAuto:FindButton()
            local PlayerGui = Player:FindFirstChildOfClass("PlayerGui")

            if not PlayerGui then
                return nil
            end

            for _, Gui in ipairs(PlayerGui:GetDescendants()) do
                if Gui:IsA("GuiButton") and GuiClick.IsOnScreen(Gui) then
                    local Text = Gui:IsA("TextButton") and Gui.Text or ""

                    if Matches(Config.AUTO_BUTTON_NAMES, Gui.Name) or Matches(Config.AUTO_BUTTON_TEXTS, Text) then
                        return Gui
                    end
                end
            end

            return nil
        end

        --// Clicks the button and records WantEnabled. True, or false and why.
        local function Click(WantEnabled)
            local Button = GameAuto:FindButton()

            if not Button then
                return false, "auto button not found"
            end

            if not GuiClick.Click(Button) then
                return false, "could not click the auto button"
            end

            S.Enabled = WantEnabled
            return true
        end

        --// True when pressed now or already on; false and why otherwise.
        local function Press(WantEnabled)
            if S.Enabled == WantEnabled then
                return true
            end

            return Click(WantEnabled)
        end

        function GameAuto:IsEnabled()
            return S.Enabled
        end

        --// Presses the button even though we think it is on already: the
        --// game may have switched its auto off by itself (death, respawn,
        --// a previous press that did not land), leaving S.Enabled wrong.
        function GameAuto:Repress()
            return Click(true)
        end

        --// Presses the button even though we think it is off already: the
        --// game's auto was seen driving the character (it can be left on
        --// from before the hop, or switched on by the game on join).
        function GameAuto:ForceOff()
            return Click(false)
        end

        function GameAuto:Enable()
            return Press(true)
        end

        function GameAuto:Disable()
            return Press(false)
        end

        return GameAuto
    end,
}
