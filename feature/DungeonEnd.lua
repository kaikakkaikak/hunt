-- DungeonEnd finds the Replay button on the summary the game shows a few
-- seconds after the dungeon ends, and presses it (GuiClick).
--
-- A button counts when it is on screen and its name, its text or a text
-- label inside it has one of Config.DUNGEON_REPLAY_TEXTS in it.
local Core = {}

function Core.IsReplayText(Text, Cfg)
    local Lower = string.lower(Text)

    for _, Wanted in ipairs(Cfg.DUNGEON_REPLAY_TEXTS) do
        if string.find(Lower, string.lower(Wanted), 1, true) then
            return true
        end
    end

    return false
end

return {
    Name = "DungeonEnd",
    Dependencies = {"Config", "GuiClick"},
    Core = Core,

    Start = function(Context)
        local Config = Context.Config
        local GuiClick = Context.GuiClick
        local Player = Context.Player

        local DungeonEnd = { Name = "DungeonEnd", Core = Core }

        local function Texts(Button)
            local Found = { Button.Name }

            if Button:IsA("TextButton") then
                table.insert(Found, Button.Text)
            end

            for _, Child in ipairs(Button:GetDescendants()) do
                if Child:IsA("TextLabel") then
                    table.insert(Found, Child.Text)
                end
            end

            return Found
        end

        --// The Replay button on screen, or nil.
        function DungeonEnd.FindReplay()
            local PlayerGui = Player:FindFirstChildOfClass("PlayerGui")

            if not PlayerGui then
                return nil
            end

            for _, Gui in ipairs(PlayerGui:GetDescendants()) do
                if Gui:IsA("GuiButton") and GuiClick.IsOnScreen(Gui) then
                    for _, Text in ipairs(Texts(Gui)) do
                        if Core.IsReplayText(Text, Config) then
                            return Gui
                        end
                    end
                end
            end

            return nil
        end

        --// The method used, or nil when none could click.
        function DungeonEnd.Press(Button)
            return GuiClick.Click(Button)
        end

        return DungeonEnd
    end,
}
