-- GameAuto switches the game's own auto-fight on and off by pressing its
-- button (Config.AUTO_BUTTON_NAMES / AUTO_BUTTON_TEXTS). The button is a
-- toggle we cannot read, so Enabled is only what we last pressed it to.
return {
    Name = "GameAuto",
    Dependencies = {"Config", "GuiClick"},

    Start = function(Context)
        local Config = Context.Config
        local GuiClick = Context.GuiClick
        local Player = Context.Player

        local GameAuto = {
            Name = "GameAuto",
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

        function GameAuto:Enable()
            return Press(true)
        end

        function GameAuto:Disable()
            return Press(false)
        end

        return GameAuto
    end,
}
