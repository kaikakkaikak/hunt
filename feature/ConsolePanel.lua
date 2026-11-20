-- ConsolePanel shows Console's lines in a draggable window, for phones that
-- cannot open F9: our lines plus every warning and error (or all output),
-- Copy to the clipboard, Clear and Close. Opened from the UI.
return {
    Name = "ConsolePanel",
    Dependencies = {"Console", "Widgets"},

    Start = function(Context)
        local Console = Context.Console
        local Widgets = Context.Widgets
        local Lifetime = Context.Lifetime
        local NotifyAction = Context.NotifyAction
        local Create = Widgets.Create
        local COLOR = Widgets.COLOR

        local GUI_NAME = "AutoHuntConsole"
        local WIDTH, HEIGHT = 340, 240
        local BAR_HEIGHT = 24
        local REFRESH = 0.5
        --// Only the newest lines are drawn: one very long label stops
        --// being drawn past its end, hiding the newest lines (Copy still
        --// has them all).
        local SHOWN_LINES = 120
        --// Within this many pixels of the bottom counts as following new lines.
        local FOLLOW_SLACK = 40

        local KIND_COLOR = {
            info = "#DCDCDC",
            warn = "#F2C744",
            error = "#F06A6A",
        }

        local Panel = {
            Name = "ConsolePanel",
            S = { OnlyOurs = true, DrawnVersion = -1, DrawnOnlyOurs = nil },
        }

        local S = Panel.S

        local Old = Widgets.GetParent():FindFirstChild(GUI_NAME)

        if Old then
            Old:Destroy()
        end

        local Gui = Create("ScreenGui", {
            Name = GUI_NAME,
            ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            DisplayOrder = 10,
            Enabled = false,
            Parent = Widgets.GetParent(),
        })

        Lifetime.OnEnd(function()
            Gui:Destroy()
        end)

        local Window = Create("Frame", {
            Size = UDim2.fromOffset(WIDTH, HEIGHT),
            Position = UDim2.new(0, 280, 0.3, 0),
            BackgroundColor3 = COLOR.Window,
            Parent = Gui,
        })

        Widgets.Corner(Window)
        Widgets.Padding(Window, 6)

        local Bar = Create("Frame", {
            Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
            BackgroundTransparency = 1,
            Parent = Window,
        })

        Create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 4),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Parent = Bar,
        })

        local Title = Create("TextLabel", {
            Size = UDim2.new(1, -4 * 4 - 70 - 3 * 50, 1, 0),
            BackgroundTransparency = 1,
            TextColor3 = COLOR.Text,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = "CONSOLE",
            LayoutOrder = 1,
            Parent = Bar,
        })

        local Filter = Widgets.Button(Bar, "", 2, UDim2.new(0, 70, 1, 0))
        local Copy = Widgets.Button(Bar, "COPY", 3, UDim2.new(0, 50, 1, 0))
        local Clear = Widgets.Button(Bar, "CLEAR", 4, UDim2.new(0, 50, 1, 0))
        local Close = Widgets.Button(Bar, "X", 5, UDim2.new(0, 50, 1, 0))
        Close.BackgroundColor3 = COLOR.Off

        for _, Button in ipairs({ Filter, Copy, Clear, Close }) do
            Button.TextSize = 11
        end

        local Scroll = Create("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, -(BAR_HEIGHT + 4)),
            Position = UDim2.fromOffset(0, BAR_HEIGHT + 4),
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 6,
            BackgroundColor3 = COLOR.Row,
            BorderSizePixel = 0,
            Parent = Window,
        })

        Widgets.Corner(Scroll)

        --// One plain label per line, made as needed and reused: a single
        --// label holding every line went blank on phones once too tall to
        --// draw, and rich text goes blank on one bad tag.
        Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = Scroll })
        Create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 2), Parent = Scroll })

        local LineLabels = {}

        local function GetLineLabel(Index)
            if not LineLabels[Index] then
                LineLabels[Index] = Create("TextLabel", {
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    Font = Enum.Font.Code,
                    TextSize = 12,
                    TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    LayoutOrder = Index,
                    Parent = Scroll,
                })
            end

            return LineLabels[Index]
        end

        Widgets.Draggable(Title, Window)

        local function PaintFilter()
            Filter.Text = S.OnlyOurs and "AUTOHUNT" or "ALL"
        end

        --// Fills the line labels with the newest SHOWN_LINES lines.
        local function Render()
            local Lines = Console:GetLines(S.OnlyOurs)
            local Shown = 0

            for Index = math.max(1, #Lines - SHOWN_LINES + 1), #Lines do
                local Line = Lines[Index]
                Shown += 1

                local Label = GetLineLabel(Shown)
                Label.Text = os.date("%H:%M:%S", Line.Time) .. "  " .. Line.Text
                Label.TextColor3 = Color3.fromHex(KIND_COLOR[Line.Kind] or KIND_COLOR.info)
                Label.Visible = true
            end

            if Shown == 0 then
                Shown = 1
                local Label = GetLineLabel(1)
                Label.Text = "(no output yet)"
                Label.TextColor3 = COLOR.Dim
                Label.Visible = true
            end

            for Index = Shown + 1, #LineLabels do
                LineLabels[Index].Visible = false
            end
        end

        --// Redraws when the lines or the filter changed; keeps following
        --// the newest line when already scrolled to the bottom.
        local function Draw()
            if S.DrawnVersion == Console:GetVersion() and S.DrawnOnlyOurs == S.OnlyOurs then
                return
            end

            local Bottom = Scroll.AbsoluteCanvasSize.Y - Scroll.AbsoluteWindowSize.Y
            local Following = Scroll.CanvasPosition.Y >= Bottom - FOLLOW_SLACK

            Render()
            S.DrawnVersion, S.DrawnOnlyOurs = Console:GetVersion(), S.OnlyOurs

            if Following then
                task.defer(function()
                    Scroll.CanvasPosition = Vector2.new(0, math.max(0, Scroll.AbsoluteCanvasSize.Y - Scroll.AbsoluteWindowSize.Y))
                end)
            end
        end

        local function GetClipboard()
            return (type(setclipboard) == "function" and setclipboard)
                or (type(toclipboard) == "function" and toclipboard)
                or nil
        end

        Lifetime.Connect(Filter.Activated, function()
            S.OnlyOurs = not S.OnlyOurs
            PaintFilter()
            Draw()
        end)

        Lifetime.Connect(Copy.Activated, function()
            local SetClipboard = GetClipboard()

            if not SetClipboard then
                NotifyAction("CONSOLE", "Copy is not supported by this executor", 4)
                return
            end

            local Ok, Error = pcall(SetClipboard, Console:PlainText(S.OnlyOurs))
            NotifyAction("CONSOLE", Ok and "Copied to clipboard" or ("Copy failed: " .. tostring(Error)), 4)
        end)

        Lifetime.Connect(Clear.Activated, function()
            Console:Clear()
            Draw()
        end)

        Lifetime.Connect(Close.Activated, function()
            Gui.Enabled = false
        end)

        function Panel:Toggle()
            Gui.Enabled = not Gui.Enabled

            if Gui.Enabled then
                Draw()
            end
        end

        PaintFilter()

        task.spawn(function()
            while Lifetime.Alive do
                if Gui.Enabled then
                    Draw()
                end

                task.wait(REFRESH)
            end
        end)

        return Panel
    end,
}
