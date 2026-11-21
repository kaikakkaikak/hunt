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

--// Whether the auto is on from how its button looks now (Current), given
--// how it looked on (OnLook) and off (OffLook): true, false, or nil when
--// that is not known (not learned yet, or on and off look the same).
function Core.ReadState(Current, OnLook, OffLook)
    if not OnLook or not OffLook or OnLook == OffLook then
        return nil
    end

    if Current == OnLook then
        return true
    end

    if Current == OffLook then
        return false
    end

    return nil
end

--// Whether the auto is on from its button's texts (Texts): false when one
--// says OFF, true when one says ON, nil when none says either.
function Core.TextState(Texts)
    local State = nil

    for _, Text in ipairs(Texts) do
        local Upper = " " .. string.upper(Text) .. " "

        if string.find(Upper, "%WOFF%W") then
            return false
        end

        if string.find(Upper, "%WON%W") then
            State = true
        end
    end

    return State
end

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

        --// The button changes look as it goes on and off (its colours, text,
        --// image): this sums that up, so a look can be compared later.
        local MAX_LOOK_PARTS = 40
        --// After a press, the button gets this long to show its new look.
        local LOOK_SETTLE = 0.5

        local function Look(Button)
            local Parts = {}

            for Index, Gui in ipairs({ Button, table.unpack(Button:GetDescendants(), 1, MAX_LOOK_PARTS) }) do
                local Part = { Index, Gui.Name }

                if Gui:IsA("GuiObject") then
                    table.insert(Part, Gui.BackgroundColor3:ToHex())
                    table.insert(Part, math.floor(Gui.BackgroundTransparency * 100))
                    table.insert(Part, tostring(Gui.Visible))
                end

                if Gui:IsA("TextLabel") or Gui:IsA("TextButton") then
                    table.insert(Part, Gui.Text)
                    table.insert(Part, Gui.TextColor3:ToHex())
                elseif Gui:IsA("ImageLabel") or Gui:IsA("ImageButton") then
                    table.insert(Part, Gui.Image)
                    table.insert(Part, Gui.ImageColor3:ToHex())
                elseif Gui:IsA("UIStroke") then
                    table.insert(Part, tostring(Gui.Enabled))
                    table.insert(Part, Gui.Color:ToHex())
                elseif Gui:IsA("UIGradient") then
                    table.insert(Part, tostring(Gui.Enabled))
                end

                for Key, Value in ipairs(Part) do
                    Part[Key] = tostring(Value)
                end

                table.insert(Parts, table.concat(Part, ","))
            end

            return table.concat(Parts, "|")
        end

        --// Clicks the button and records WantEnabled. True, or false and why.
        --// Learns what on and off look like from the button before and
        --// after the press.
        local function Click(WantEnabled)
            local Button = GameAuto:FindButton()

            if not Button then
                return false, "auto button not found"
            end

            local Before = Look(Button)

            if not GuiClick.Click(Button) then
                return false, "could not click the auto button"
            end

            task.wait(LOOK_SETTLE)

            local Now = GameAuto:FindButton() or Button
            local After = Look(Now)

            if After ~= Before then
                local Learned = S.OnLook == nil
                S.OnLook, S.OffLook = WantEnabled and After or Before, WantEnabled and Before or After

                if Learned then
                    print("[GameAuto] Learned how the auto button looks on and off")
                end
            end

            S.Enabled = WantEnabled
            --// Every press is logged: the button is a toggle, so a stray one
            --// shows up as the auto going off.
            print("[GameAuto] Pressed the auto button (now taken as " .. (WantEnabled and "on" or "off") .. ")")
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

        --// The auto's real state from the button's look: true, false, or
        --// nil when it cannot be told (not learned yet, button not there).
        function GameAuto:ReadState()
            local Button = GameAuto:FindButton()

            if not Button then
                return nil
            end

            local State = Core.ReadState(Look(Button), S.OnLook, S.OffLook)

            if State ~= nil then
                return State
            end

            --// Not learned: the button may say ON / OFF itself.
            local Texts = {}

            for _, Gui in ipairs({ Button, table.unpack(Button:GetDescendants(), 1, MAX_LOOK_PARTS) }) do
                if (Gui:IsA("TextLabel") or Gui:IsA("TextButton")) and Gui.Visible then
                    table.insert(Texts, Gui.Text)
                end
            end

            return Core.TextState(Texts)
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

        --// The game is known to have its auto off (it always is on entering
        --// the dungeon): no press, only what we believe.
        function GameAuto:AssumeOff()
            S.Enabled = false
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
