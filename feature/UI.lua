-- UI is a small draggable window with a nav bar on top to switch between
-- two pages (the pick is saved):
--   HUNT     pick the boss to hunt (each with its kills), Hop After Kill,
--            Start / Stop and Hop Now;
--   DUNGEON  Start / Stop the auto dungeon, and whether it checks the rooms
--            (flies into each so its monsters spawn), collects the boxes,
--            dodges the boss's skills, flies into its green safe zone and
--            hits the boss from behind.
-- The status line shows the open page's feature; Console is on both.
--
-- The "-" button shrinks it to a bar with only the selected boss (or the
-- dungeon's status), its kills and Play / Stop ("+" opens it again); the
-- choice is saved, so it stays small across hops.
return {
    Name = "UI",
    Dependencies = {"Config", "Settings", "AutoHunt", "AutoDungeon", "Widgets", "ConsolePanel"},

    Start = function(Context)
        local Config = Context.Config
        local Settings = Context.Settings
        local AutoHunt = Context.AutoHunt
        local AutoDungeon = Context.AutoDungeon
        local Widgets = Context.Widgets
        local ConsolePanel = Context.ConsolePanel
        local Lifetime = Context.Lifetime
        local Create = Widgets.Create
        local COLOR = Widgets.COLOR

        local GUI_NAME = "AutoHuntUI"
        local WIDTH = 240
        local COMPACT_WIDTH = 220
        local SMALL_BUTTON = 26
        local NAV_HEIGHT = 26
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

        --// A column that grows with what is in it.
        local function Page(Parent, Order)
            local Frame = Create("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                LayoutOrder = Order,
                Parent = Parent,
            })

            Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Frame })
            return Frame
        end

        --// A left-aligned button that reads "[x]  Text" when on.
        local function CheckButton(Parent, Order)
            local Button = Widgets.Button(Parent, "", Order)
            Button.TextXAlignment = Enum.TextXAlignment.Left
            Create("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = Button })
            return Button
        end

        local function PaintCheck(Button, Text, IsOn)
            Button.Text = (IsOn and "[x]  " or "[  ]  ") .. Text
            Button.BackgroundColor3 = IsOn and COLOR.On or COLOR.Row
        end

        ------------------------------------------------------------------------
        --// Full window: title, nav, status, the open page, console
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

        local Nav = Row(Window, NAV_HEIGHT, 2)
        local HALF = UDim2.new(0.5, -2, 1, 0)
        local Tabs = {
            hunt = Widgets.Button(Nav, "HUNT", 1, HALF),
            dungeon = Widgets.Button(Nav, "DUNGEON", 2, HALF),
        }

        local Status = Label(Window, {
            Size = UDim2.new(1, 0, 0, 32),
            TextColor3 = COLOR.Dim,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 3,
        })

        --// Hunt page

        local HuntPage = Page(Window, 4)

        --// Kills of the selected boss and of all bosses, kept across
        --// hops and game sessions by Settings.
        local KillsLabel = Label(HuntPage, {
            Size = UDim2.new(1, 0, 0, 18),
            TextColor3 = COLOR.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            LayoutOrder = 1,
        })

        local List = Create("ScrollingFrame", {
            Size = UDim2.new(1, 0, 0, LIST_HEIGHT),
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 4,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = 2,
            Parent = HuntPage,
        })

        Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = List })

        local HopAfterKill = Widgets.Button(HuntPage, "", 3)
        local RunButton = Widgets.Button(HuntPage, "", 4)
        local HopNow = Widgets.Button(HuntPage, "HOP NOW", 5)

        --// Dungeon page

        local DungeonPage = Page(Window, 4)
        local DungeonRun = Widgets.Button(DungeonPage, "", 1)
        local CheckRooms = CheckButton(DungeonPage, 2)
        local CollectBoxes = CheckButton(DungeonPage, 3)
        local DodgeSkills = CheckButton(DungeonPage, 4)
        local SafeZone = CheckButton(DungeonPage, 5)
        local Backstab = CheckButton(DungeonPage, 6)

        local ConsoleButton = Widgets.Button(Window, "CONSOLE", 5)

        local Pages = { hunt = HuntPage, dungeon = DungeonPage }

        ------------------------------------------------------------------------
        --// Compact bar: boss (or dungeon), kills, Play / Stop
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

            if Data.Dungeon then
                CompactLabel.Text = "DUNGEON: " .. AutoDungeon:GetStatus()
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

        local function PaintRun(Button, IsRunning, StartText)
            Button.Text = IsRunning and "STOP" or StartText
            Button.BackgroundColor3 = IsRunning and COLOR.Off or COLOR.On
        end

        local function PaintControls()
            HopAfterKill.Text = "HOP AFTER KILL: " .. (Data.HopAfterKill and "ON" or "OFF")
            PaintRun(RunButton, Data.Running, "START")
            PaintRun(DungeonRun, Data.Dungeon, "START DUNGEON")
            PaintCheck(CheckRooms, "CHECK ROOMS", Data.DungeonRooms)
            PaintCheck(CollectBoxes, "COLLECT BOXES", Data.DungeonLoot)
            PaintCheck(DodgeSkills, "DODGE BOSS SKILLS", Data.DungeonDodge)
            PaintCheck(SafeZone, "GREEN SAFE ZONE", Data.DungeonSafeZone)
            PaintCheck(Backstab, "HIT BOSS FROM BEHIND", Data.DungeonBackstab)
            --// The compact bar's button stops whichever is running.
            PaintRun(CompactRun, Data.Running or Data.Dungeon, "PLAY")
        end

        local function PaintStatus()
            local Source = Data.Tab == "dungeon" and AutoDungeon or AutoHunt
            Status.Text = "STATUS: " .. Source:GetStatus()
        end

        local function ShowTab()
            for Name, Frame in pairs(Pages) do
                local IsOpen = Name == Data.Tab
                Frame.Visible = IsOpen
                Tabs[Name].BackgroundColor3 = IsOpen and COLOR.On or COLOR.Row
            end

            PaintStatus()
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

        for Name, Button in pairs(Tabs) do
            Lifetime.Connect(Button.Activated, function()
                Data.Tab = Name
                Settings:Save()
                ShowTab()
            end)
        end

        --// Only one boss at a time: picking one drops the other, picking
        --// the selected one again clears it.
        for Index, Name in ipairs(Config.BOSS_NAMES) do
            local Button = CheckButton(List, Index)
            BossButtons[Name] = Button

            Lifetime.Connect(Button.Activated, function()
                Settings:Select(Settings:GetSelected() ~= Name and Name or nil)
                Settings:Save()
                PaintAllBosses()
                PaintKills()
            end)
        end

        local function Toggle(Button, Key)
            Lifetime.Connect(Button.Activated, function()
                Data[Key] = not Data[Key]
                Settings:Save()
                PaintControls()
            end)
        end

        Toggle(HopAfterKill, "HopAfterKill")
        Toggle(CheckRooms, "DungeonRooms")
        Toggle(CollectBoxes, "DungeonLoot")
        Toggle(DodgeSkills, "DungeonDodge")
        Toggle(SafeZone, "DungeonSafeZone")
        Toggle(Backstab, "DungeonBackstab")

        Lifetime.Connect(DungeonRun.Activated, function()
            AutoDungeon:SetRunning(not Data.Dungeon)
            PaintControls()
        end)

        Lifetime.Connect(RunButton.Activated, function()
            if not Data.Running then
                AutoDungeon:SetRunning(false)
            end

            AutoHunt:SetRunning(not Data.Running)
            PaintControls()
        end)

        Lifetime.Connect(CompactRun.Activated, function()
            if Data.Dungeon then
                AutoDungeon:SetRunning(false)
            elseif Data.Running then
                AutoHunt:SetRunning(false)
            elseif Data.Tab == "dungeon" then
                AutoDungeon:SetRunning(true)
            else
                AutoHunt:SetRunning(true)
            end

            PaintControls()
        end)

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
        ShowTab()
        ApplySize()

        task.spawn(function()
            while Lifetime.Alive do
                PaintStatus()
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
