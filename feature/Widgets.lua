-- Widgets holds what the windows share: colours, making instances, a
-- rounded button, the ScreenGui parent and dragging a window by a handle
-- (mouse or touch).
return {
    Name = "Widgets",
    Dependencies = {},

    Start = function(Context)
        local Player = Context.Player
        local Lifetime = Context.Lifetime
        local UserInputService = game:GetService("UserInputService")

        local Widgets = {
            Name = "Widgets",
            ROW_HEIGHT = 26,
            COLOR = {
                Window = Color3.fromRGB(24, 24, 28),
                Row = Color3.fromRGB(38, 38, 44),
                On = Color3.fromRGB(46, 160, 90),
                Off = Color3.fromRGB(170, 60, 60),
                Text = Color3.fromRGB(235, 235, 235),
                Dim = Color3.fromRGB(150, 150, 160),
            },
        }

        function Widgets.GetParent()
            if type(gethui) == "function" then
                local Ok, Hui = pcall(gethui)

                if Ok and Hui then
                    return Hui
                end
            end

            return Player:WaitForChild("PlayerGui")
        end

        function Widgets.Create(ClassName, Properties)
            local Object = Instance.new(ClassName)

            for Key, Value in pairs(Properties) do
                if Key ~= "Parent" then
                    Object[Key] = Value
                end
            end

            Object.Parent = Properties.Parent
            return Object
        end

        function Widgets.Corner(Parent)
            Widgets.Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = Parent })
        end

        function Widgets.Padding(Parent, Pixels)
            local Gap = UDim.new(0, Pixels)
            Widgets.Create("UIPadding", {
                PaddingTop = Gap, PaddingBottom = Gap, PaddingLeft = Gap, PaddingRight = Gap,
                Parent = Parent,
            })
        end

        function Widgets.Button(Parent, Text, Order, Size)
            local Button = Widgets.Create("TextButton", {
                Size = Size or UDim2.new(1, 0, 0, Widgets.ROW_HEIGHT),
                BackgroundColor3 = Widgets.COLOR.Row,
                TextColor3 = Widgets.COLOR.Text,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                Text = Text,
                AutoButtonColor = true,
                LayoutOrder = Order or 0,
                Parent = Parent,
            })

            Widgets.Corner(Button)
            return Button
        end

        local function IsPress(Input)
            return Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch
        end

        --// Dragging Handle moves Target.
        function Widgets.Draggable(Handle, Target)
            local DragStart, StartPosition

            Handle.Active = true

            Lifetime.Connect(Handle.InputBegan, function(Input)
                if IsPress(Input) then
                    DragStart = Input.Position
                    StartPosition = Target.Position
                end
            end)

            Lifetime.Connect(UserInputService.InputChanged, function(Input)
                local Moving = Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch

                if DragStart and Moving then
                    local Delta = Input.Position - DragStart
                    Target.Position = StartPosition + UDim2.fromOffset(Delta.X, Delta.Y)
                end
            end)

            Lifetime.Connect(UserInputService.InputEnded, function(Input)
                if IsPress(Input) then
                    DragStart = nil
                end
            end)
        end

        return Widgets
    end,
}
