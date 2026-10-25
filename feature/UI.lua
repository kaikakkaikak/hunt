-- UI is a small draggable window: tick the bosses to hunt, Start / Stop,
-- Hop After Kill, Hop Now, and the current status.
return {
    Name = "UI",
    Dependencies = {"Config", "Settings", "AutoHunt"},

    Start = function(Context)
        local Config = Context.Config
        local Settings = Context.Settings
        local AutoHunt = Context.AutoHunt
        local Lifetime = Context.Lifetime
        local Player = Context.Player
        local UserInputService = game:GetService("UserInputService")

        local GUI_NAME = "AutoHuntUI"
        local WIDTH = 240
        local ROW_HEIGHT = 26
        local LIST_HEIGHT = 150
        local STATUS_REFRESH = 0.25

        local COLOR = {
            Window = Color3.fromRGB(24, 24, 28),
            Row = Color3.fromRGB(38, 38, 44),
            On = Color3.fromRGB(46, 160, 90),
            Off = Color3.fromRGB(170, 60, 60),
            Text = Color3.fromRGB(235, 235, 235),
            Dim = Color3.fromRGB(150, 150, 160),
        }

        local Data = Settings.Data

        local function GetParent()
            if type(gethui) == "function" then
                local Ok, Hui = pcall(gethui)

                if Ok and Hui then
                    return Hui
                end
            end

            return Player:WaitForChild("PlayerGui")
        end

        local function Create(ClassName, Properties)
            local Object = Instance.new(ClassName)

            for Key, Value in pairs(Properties) do
                if Key ~= "Parent" then
                    Object[Key] = Value
                end
            end

            Object.Parent = Properties.Parent
            return Object
        end

        local function Corner(Parent)
            Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = Parent })
        end

        local function MakeButton(Parent, Text, Order)
            local Button = Create("TextButton", {
                Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
                BackgroundColor3 = COLOR.Row,
                TextColor3 = COLOR.Text,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                Text = Text,
                AutoButtonColor = true,
                LayoutOrder = Order,
                Parent = Parent,
            })

            Corner(Button)
            return Button
        end

        local Old = GetParent():FindFirstChild(GUI_NAME)

        if Old then
            Old:Destroy()
        end

        local Gui = Create("ScreenGui", {
            Name = GUI_NAME,
            ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            Parent = GetParent(),
        })

        Lifetime.OnEnd(function()
            Gui:Destroy()
        end)

        local Window = Create("Frame", {
            Size = UDim2.new(0, WIDTH, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Position = UDim2.new(0, 20, 0.3, 0),
            BackgroundColor3 = COLOR.Window,
            Parent = Gui,
        })

        Corner(Window)
        Create("UIPadding", {
            PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
            Parent = Window,
        })
        Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Window })

        local Title = Create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            TextColor3 = COLOR.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = "AUTO HUNT",
            LayoutOrder = 1,
            Parent = Window,
        })

        local Status = Create("TextLabel", {
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundTransparency = 1,
            TextColor3 = COLOR.Dim,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 2,
            Parent = Window,
        })

        local List = Create("ScrollingFrame", {
            Size = UDim2.new(1, 0, 0, LIST_HEIGHT),
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 4,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 3,
            Parent = Window,
        })

        Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = List })

        ------------------------------------------------------------------------
        --// Boss list
        ------------------------------------------------------------------------

        local function PaintBoss(Button, Name)
            local Selected = Data.Selected[Name] == true
            Button.Text = (Selected and "[x]  " or "[  ]  ") .. Name
            Button.BackgroundColor3 = Selected and COLOR.On or COLOR.Row
        end

        for Index, Name in ipairs(Config.BOSS_NAMES) do
            local Button = MakeButton(List, "", Index)
            Button.TextXAlignment = Enum.TextXAlignment.Left
            Create("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = Button })
            PaintBoss(Button, Name)

            Lifetime.Connect(Button.Activated, function()
                Data.Selected[Name] = not Data.Selected[Name] or nil
                Settings:Save()
                PaintBoss(Button, Name)
            end)
        end

        ------------------------------------------------------------------------
        --// Controls
        ------------------------------------------------------------------------

        local HopAfterKill = MakeButton(Window, "", 4)
        local RunButton = MakeButton(Window, "", 5)
        local HopNow = MakeButton(Window, "HOP NOW", 6)

        local function PaintControls()
            HopAfterKill.Text = "HOP AFTER KILL: " .. (Data.HopAfterKill and "ON" or "OFF")
            RunButton.Text = Data.Running and "STOP" or "START"
            RunButton.BackgroundColor3 = Data.Running and COLOR.Off or COLOR.On
        end

        Lifetime.Connect(HopAfterKill.Activated, function()
            Data.HopAfterKill = not Data.HopAfterKill
            Settings:Save()
            PaintControls()
        end)

        Lifetime.Connect(RunButton.Activated, function()
            AutoHunt:SetRunning(not Data.Running)
            PaintControls()
        end)

        Lifetime.Connect(HopNow.Activated, function()
            AutoHunt:HopNow()
        end)

        PaintControls()

        ------------------------------------------------------------------------
        --// Dragging by the title
        ------------------------------------------------------------------------

        local DragStart, StartPosition

        Lifetime.Connect(Title.InputBegan, function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                DragStart = Input.Position
                StartPosition = Window.Position
            end
        end)

        Title.Active = true

        Lifetime.Connect(UserInputService.InputChanged, function(Input)
            if DragStart and (Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch) then
                local Delta = Input.Position - DragStart
                Window.Position = StartPosition + UDim2.fromOffset(Delta.X, Delta.Y)
            end
        end)

        Lifetime.Connect(UserInputService.InputEnded, function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                DragStart = nil
            end
        end)

        task.spawn(function()
            while Lifetime.Alive do
                Status.Text = "STATUS: " .. AutoHunt:GetStatus()
                task.wait(STATUS_REFRESH)
            end
        end)

        return { Name = "UI", Gui = Gui }
    end,
}
