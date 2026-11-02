-- UI is a small draggable window: pick the boss to hunt, Start / Stop,
-- Hop After Kill, Hop Now, Console, and the current status. Each boss shows
-- how many times it was killed.
--
-- The "-" button shrinks it to a bar with only the selected boss, its
-- kills and Play / Stop ("+" opens it again); the choice is saved, so it
-- stays small across hops.
return {
    Name = "UI",
    Dependencies = {"Config", "Settings", "AutoHunt", "Widgets", "ConsolePanel"},

    Start = function(Context)
        local Config = Context.Config
        local Settings = Context.Settings
        local AutoHunt = Context.AutoHunt
        local Widgets = Context.Widgets
        local ConsolePanel = Context.ConsolePanel
        local Lifetime = Context.Lifetime
        local Create = Widgets.Create
        local COLOR = Widgets.COLOR

        local GUI_NAME = "AutoHuntUI"
        local WIDTH = 240
        local COMPACT_WIDTH = 220
        local SMALL_BUTTON = 26
        local LIST_HEIGHT = 150
        local STATUS_REFRESH = 0.25

        local Data = Settings.Data

        local Old = Widgets.GetParent():FindFirstChild(GUI_NAME)

        if Old then
            Old:Destroy()
        end

        local Gui = Create("ScreenGui", {
            Name = GUI_NAME,
            ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            Parent = Widgets.GetParent(),
        })

        Lifetime.OnEnd(function()
            Gui:Destroy()
        end)

        --// A row of Height laid out left to right.
        local function Row(Parent, Height, Order)
            local Frame = Create("Frame", {
                Size = UDim2.new(1, 0, 0, Height),
                BackgroundTransparency = 1,
                LayoutOrder = Order or 0,
                Parent = Parent,
            })

            Create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                Padding = UDim.new(0, 4),
                SortOrder = Enum.SortOrder.LayoutOrder,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Parent = Frame,
            })

            return Frame
        end

        local function Label(Parent, Properties)
            Properties.BackgroundTransparency = 1
            Properties.TextXAlignment = Properties.TextXAlignment or Enum.TextXAlignment.Left
            Properties.Parent = Parent
            return Create("TextLabel", Properties)
        end

        ------------------------------------------------------------------------
        --// Full window
        ------------------------------------------------------------------------

        local Window = Create("Frame", {
            Size = UDim2.new(0, WIDTH, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Position = UDim2.new(0, 20, 0.3, 0),
            BackgroundColor3 = COLOR.Window,
            Parent = Gui,
        })

        Widgets.Corner(Window)
        Widgets.Padding(Window, 8)
        Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Window })

        local TitleBar = Row(Window, 22, 1)

        local Title = Label(TitleBar, {
            Size = UDim2.new(1, -(SMALL_BUTTON + 4), 1, 0),
            TextColor3 = COLOR.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 15,
            Text = Context.Title or "AUTO HUNT",
            LayoutOrder = 1,
        })

        local Shrink = Widgets.Button(TitleBar, "-", 2, UDim2.fromOffset(SMALL_BUTTON, 22))

        local Status = Label(Window, {
            Size = UDim2.new(1, 0, 0, 32),
            TextColor3 = COLOR.Dim,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 2,
        })

        --// Kills of the selected boss and of all bosses, kept across
        --// hops and game sessions by Settings.
        local KillsLabel = Label(Window, {
            Size = UDim2.new(1, 0, 0, 18),
            TextColor3 = COLOR.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            LayoutOrder = 3,
        })

        local List = Create("ScrollingFrame", {
            Size = UDim2.new(1, 0, 0, LIST_HEIGHT),
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 4,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 4,
            Parent = Window,
        })

        Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = List })

        local HopAfterKill = Widgets.Button(Window, "", 5)
        local RunButton = Widgets.Button(Window, "", 6)
        local HopNow = Widgets.Button(Window, "HOP NOW", 7)
        local ConsoleButton = Widgets.Button(Window, "CONSOLE", 8)

        ------------------------------------------------------------------------
        --// Compact bar: boss, kills, Play / Stop
        ------------------------------------------------------------------------

        local Compact = Create("Frame", {
            Size = UDim2.fromOffset(COMPACT_WIDTH, SMALL_BUTTON + 12),
            BackgroundColor3 = COLOR.Window,
            Visible = false,
            Parent = Gui,
        })

        Widgets.Corner(Compact)
        Widgets.Padding(Compact, 6)

        local CompactRow = Row(Compact, SMALL_BUTTON)
        CompactRow.Size = UDim2.fromScale(1, 1)

        local CompactLabel = Label(CompactRow, {
            Size = UDim2.new(1, -(52 + SMALL_BUTTON + 8), 1, 0),
            TextColor3 = COLOR.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextTruncate = Enum.TextTruncate.AtEnd,
            LayoutOrder = 1,
        })

        local CompactRun = Widgets.Button(CompactRow, "", 2, UDim2.fromOffset(52, SMALL_BUTTON))
        local Grow = Widgets.Button(CompactRow, "+", 3, UDim2.fromOffset(SMALL_BUTTON, SMALL_BUTTON))

        ------------------------------------------------------------------------
        --// Painting
        ------------------------------------------------------------------------

        local function PaintKills()
            local Total = 0

            for _, Count in pairs(Data.Kills) do
                Total += Count
            end

            local Selected = Settings:GetSelected()

            if Selected then
                KillsLabel.Text = string.format("KILLS: %s %d  //  TOTAL %d", Selected, Settings:GetKills(Selected), Total)
                CompactLabel.Text = string.format("%s : %d", Selected, Settings:GetKills(Selected))
            else
                KillsLabel.Text = string.format("KILLS TOTAL: %d", Total)
                CompactLabel.Text = "NO BOSS SELECTED"
            end
        end

        local function PaintBoss(Button, Name)
            local Selected = Data.Selected[Name] == true
            Button.Text = string.format("%s%s  (%d)", Selected and "[x]  " or "[  ]  ", Name, Settings:GetKills(Name))
            Button.BackgroundColor3 = Selected and COLOR.On or COLOR.Row
        end

        --// Boss name -> its button, to repaint all when the pick changes.
        local BossButtons = {}

        local function PaintAllBosses()
            for Name, Button in pairs(BossButtons) do
                PaintBoss(Button, Name)
            end
        end

        local function PaintControls()
            HopAfterKill.Text = "HOP AFTER KILL: " .. (Data.HopAfterKill and "ON" or "OFF")
            RunButton.Text = Data.Running and "STOP" or "START"
            CompactRun.Text = Data.Running and "STOP" or "PLAY"

            for _, Button in ipairs({ RunButton, CompactRun }) do
                Button.BackgroundColor3 = Data.Running and COLOR.Off or COLOR.On
            end
        end

        --// Shows the full window or the compact bar, at the same spot.
        local function ApplySize()
            local From, To = Window, Compact

            if not Data.Compact then
                From, To = Compact, Window
            end

            if From.Visible then
                To.Position = From.Position
            end

            From.Visible = false
            To.Visible = true
        end

        ------------------------------------------------------------------------
        --// Input
        ------------------------------------------------------------------------

        --// Only one boss at a time: picking one drops the other, picking
        --// the selected one again clears it.
        for Index, Name in ipairs(Config.BOSS_NAMES) do
            local Button = Widgets.Button(List, "", Index)
            Button.TextXAlignment = Enum.TextXAlignment.Left
            Create("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = Button })
            BossButtons[Name] = Button

            Lifetime.Connect(Button.Activated, function()
                Settings:Select(Settings:GetSelected() ~= Name and Name or nil)
                Settings:Save()
                PaintAllBosses()
                PaintKills()
            end)
        end

        Lifetime.Connect(HopAfterKill.Activated, function()
            Data.HopAfterKill = not Data.HopAfterKill
            Settings:Save()
            PaintControls()
        end)

        for _, Button in ipairs({ RunButton, CompactRun }) do
            Lifetime.Connect(Button.Activated, function()
                AutoHunt:SetRunning(not Data.Running)
                PaintControls()
            end)
        end

        Lifetime.Connect(HopNow.Activated, function()
            AutoHunt:HopNow()
        end)

        Lifetime.Connect(ConsoleButton.Activated, function()
            ConsolePanel:Toggle()
        end)

        for _, Button in ipairs({ Shrink, Grow }) do
            Lifetime.Connect(Button.Activated, function()
                Data.Compact = Button == Shrink
                Settings:Save()
                ApplySize()
            end)
        end

        Widgets.Draggable(Title, Window)
        Widgets.Draggable(CompactLabel, Compact)

        Compact.Position = Window.Position
        PaintAllBosses()
        PaintKills()
        PaintControls()
        ApplySize()

        task.spawn(function()
            while Lifetime.Alive do
                Status.Text = "STATUS: " .. AutoHunt:GetStatus()
                --// Picks up new kill counts and a Stop from elsewhere.
                PaintAllBosses()
                PaintKills()
                PaintControls()
                task.wait(STATUS_REFRESH)
            end
        end)

        return { Name = "UI", Gui = Gui }
    end,
}
