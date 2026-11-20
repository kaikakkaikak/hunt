-- KeyPress sends keyboard input the way an executor allows: a synthetic
-- key event through VirtualInputManager, or keypress / keyrelease (Windows
-- virtual-key codes) when that is all the executor has.
return {
    Name = "KeyPress",
    Dependencies = {},

    Start = function()
        local TAP_SECONDS = 0.03

        local CloneReference = type(cloneref) == "function" and cloneref or function(Instance)
            return Instance
        end

        local HasVirtualInput, VirtualInputManager = pcall(function()
            return CloneReference(game:GetService("VirtualInputManager"))
        end)

        if not HasVirtualInput then
            VirtualInputManager = nil
        end

        --// Windows virtual-key codes for keypress / keyrelease.
        local VK = {
            [Enum.KeyCode.One] = 0x31,
            [Enum.KeyCode.Two] = 0x32,
            [Enum.KeyCode.Three] = 0x33,
            [Enum.KeyCode.Four] = 0x34,
            [Enum.KeyCode.Five] = 0x35,
            [Enum.KeyCode.E] = 0x45,
            [Enum.KeyCode.F] = 0x46,
            [Enum.KeyCode.Q] = 0x51,
            [Enum.KeyCode.R] = 0x52,
        }

        local KeyPress = { Name = "KeyPress" }

        --// Key down (IsDown) or up. True when some method could send it.
        function KeyPress.Send(KeyCode, IsDown)
            if VirtualInputManager then
                local Ok = pcall(function()
                    VirtualInputManager:SendKeyEvent(IsDown, KeyCode, false, game)
                end)

                if Ok then
                    return true
                end
            end

            local Code = VK[KeyCode]
            local Send = IsDown and keypress or keyrelease

            if Code and type(Send) == "function" then
                return (pcall(Send, Code))
            end

            return false
        end

        function KeyPress.Tap(KeyCode)
            if not KeyPress.Send(KeyCode, true) then
                return false
            end

            task.wait(TAP_SECONDS)
            KeyPress.Send(KeyCode, false)
            return true
        end

        --// Holds the key for Seconds (yields).
        function KeyPress.Hold(KeyCode, Seconds)
            if not KeyPress.Send(KeyCode, true) then
                return false
            end

            task.wait(Seconds)
            KeyPress.Send(KeyCode, false)
            return true
        end

        return KeyPress
    end,
}
