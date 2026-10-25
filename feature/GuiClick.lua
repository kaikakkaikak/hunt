-- GuiClick presses a GuiButton the way an executor allows, ported from
-- Automated-Industry-Complex/Core/GuiClick.lua.
--
-- Methods, each tried only when the executor provides it:
--   firesignal / getconnections  fire the button's handlers directly,
--                                instantly and without moving the cursor
--   VirtualInputManager          a synthetic mouse click on the button
--   mouse                        moves the real cursor, clicks, moves back
return {
    Name = "GuiClick",
    Dependencies = {},

    Start = function()
        local GuiService = game:GetService("GuiService")
        local UserInputService = game:GetService("UserInputService")

        local CLICK_HOLD_SECONDS = 0.05

        local CloneReference = type(cloneref) == "function" and cloneref or function(Instance)
            return Instance
        end

        local HasVirtualInput, VirtualInputManager = pcall(function()
            return CloneReference(game:GetService("VirtualInputManager"))
        end)

        if not HasVirtualInput then
            VirtualInputManager = nil
        end

        local GuiClick = { Name = "GuiClick" }

        --// Drawn and big enough to click: every ancestor up to its
        --// ScreenGui is visible and that ScreenGui is enabled.
        function GuiClick.IsOnScreen(Gui)
            if not Gui or not Gui.Parent then
                return false
            end

            if Gui.AbsoluteSize.X < 1 or Gui.AbsoluteSize.Y < 1 then
                return false
            end

            local Node = Gui

            while Node do
                if Node:IsA("GuiObject") and not Node.Visible then
                    return false
                end

                if Node:IsA("LayerCollector") then
                    return Node.Enabled
                end

                Node = Node.Parent
            end

            return false
        end

        local function FireConnections(Signal)
            if type(getconnections) ~= "function" then
                return false
            end

            local Ok, Connections = pcall(getconnections, Signal)

            if not Ok or type(Connections) ~= "table" then
                return false
            end

            local Fired = false

            for _, Connection in ipairs(Connections) do
                if pcall(function()
                    Connection:Fire()
                end) then
                    Fired = true
                end
            end

            return Fired
        end

        local function FireSignal(Signal)
            if type(firesignal) ~= "function" then
                return false
            end

            return (pcall(firesignal, Signal))
        end

        --// Screen-space centre of a button, including the top bar inset when
        --// its ScreenGui uses it.
        local function GetButtonCenter(Button)
            local Center = Button.AbsolutePosition + Button.AbsoluteSize / 2
            local ScreenGui = Button:FindFirstAncestorWhichIsA("ScreenGui")

            if not (ScreenGui and ScreenGui.IgnoreGuiInset) then
                Center += GuiService:GetGuiInset()
            end

            return Center
        end

        local function ClickWithVirtualInput(Button)
            if not VirtualInputManager then
                return false
            end

            local Center = GetButtonCenter(Button)

            return (pcall(function()
                VirtualInputManager:SendMouseButtonEvent(Center.X, Center.Y, 0, true, game, 0)
                task.wait(CLICK_HOLD_SECONDS)
                VirtualInputManager:SendMouseButtonEvent(Center.X, Center.Y, 0, false, game, 0)
            end))
        end

        local function ClickWithRealMouse(Button)
            if type(mousemoveabs) ~= "function" or type(mouse1click) ~= "function" then
                return false
            end

            local Center = GetButtonCenter(Button)
            local Previous = UserInputService:GetMouseLocation()

            return (pcall(function()
                mousemoveabs(Center.X, Center.Y)
                task.wait(CLICK_HOLD_SECONDS)
                mouse1click()
                task.wait(CLICK_HOLD_SECONDS)
                mousemoveabs(Previous.X, Previous.Y)
            end))
        end

        local DEFAULT_SIGNALS = { "Activated", "MouseButton1Click" }

        local function FireFirst(Fire, Button, Signals)
            for _, SignalName in ipairs(Signals or DEFAULT_SIGNALS) do
                if Fire(Button[SignalName]) then
                    return true
                end
            end

            return false
        end

        GuiClick.Methods = {
            {
                Name = "getconnections",
                Click = function(Button, Signals)
                    return FireFirst(FireConnections, Button, Signals)
                end,
            },
            {
                Name = "firesignal",
                Click = function(Button, Signals)
                    return FireFirst(FireSignal, Button, Signals)
                end,
            },
            { Name = "VirtualInputManager", Click = ClickWithVirtualInput },
            { Name = "mouse", Click = ClickWithRealMouse },
        }

        --// Clicks with the first method that can send. Returns its name, or
        --// nil when none could. The caller checks whether it took effect.
        function GuiClick.Click(Button, Signals)
            for _, Method in ipairs(GuiClick.Methods) do
                if Method.Click(Button, Signals) then
                    return Method.Name
                end
            end

            return nil
        end

        return GuiClick
    end,
}
