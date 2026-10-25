-- BossTimer reads the seconds left on a boss's spawn timer in workspace.
-- Timers are the instances named Config.BOSS_TIMER_NAME, and each boss's own
-- is picked by its place in that list (Config.BOSS_TIMERS). The time is read
-- from, in order: the timer's own Value, a number attribute, then the text
-- of any label inside it ("25", "0:25", "1:02:03", "1m 20s", "25s").
return {
    Name = "BossTimer",
    Dependencies = {"Config"},

    Start = function(Context)
        local Config = Context.Config

        local TIME_ATTRIBUTES = { "Time", "TimeLeft", "Remaining", "Seconds", "Timer" }

        local BossTimer = { Name = "BossTimer" }

        --// Seconds from a timer text, or nil.
        function BossTimer.ParseSeconds(Text)
            if type(Text) ~= "string" then
                return nil
            end

            Text = string.gsub(Text, "^%s*(.-)%s*$", "%1")

            local Plain = tonumber(Text)

            if Plain then
                return Plain
            end

            local Hours, Minutes, Seconds = string.match(Text, "(%d+):(%d+):(%d+)")

            if Hours then
                return tonumber(Hours) * 3600 + tonumber(Minutes) * 60 + tonumber(Seconds)
            end

            Minutes, Seconds = string.match(Text, "(%d+):(%d+)")

            if Minutes then
                return tonumber(Minutes) * 60 + tonumber(Seconds)
            end

            local UnitMinutes = string.match(Text, "(%d+)%s*[mM]")
            local UnitSeconds = string.match(Text, "(%d+)%s*[sS]")

            if UnitMinutes or UnitSeconds then
                return (tonumber(UnitMinutes) or 0) * 60 + (tonumber(UnitSeconds) or 0)
            end

            return nil
        end

        local function ReadValue(Object)
            if not Object:IsA("ValueBase") then
                return nil
            end

            local Value = Object.Value

            if type(Value) == "number" then
                return Value
            end

            return BossTimer.ParseSeconds(tostring(Value))
        end

        local function ReadAttribute(Object)
            for _, Name in ipairs(TIME_ATTRIBUTES) do
                local Value = Object:GetAttribute(Name)

                if type(Value) == "number" then
                    return Value
                end

                local Parsed = BossTimer.ParseSeconds(Value)

                if Parsed then
                    return Parsed
                end
            end

            return nil
        end

        local function ReadText(Object)
            for _, Descendant in ipairs(Object:GetDescendants()) do
                if Descendant:IsA("TextLabel") or Descendant:IsA("TextBox") then
                    local Seconds = BossTimer.ParseSeconds(Descendant.Text)

                    if Seconds then
                        return Seconds
                    end
                elseif Descendant:IsA("ValueBase") then
                    local Seconds = ReadValue(Descendant)

                    if Seconds then
                        return Seconds
                    end
                end
            end

            return nil
        end

        --// Every timer in workspace, in GetDescendants order.
        function BossTimer.List()
            local Wanted = string.lower(Config.BOSS_TIMER_NAME)
            local Timers = {}

            for _, Descendant in ipairs(workspace:GetDescendants()) do
                if string.lower(Descendant.Name) == Wanted then
                    table.insert(Timers, Descendant)
                end
            end

            return Timers
        end

        --// Seconds left on one timer instance, or nil when unreadable.
        function BossTimer.Read(Timer)
            return ReadValue(Timer) or ReadAttribute(Timer) or ReadText(Timer)
        end

        --// Seconds until BossName spawns, or nil (no timer for it, or unreadable).
        function BossTimer.GetSeconds(BossName)
            local Index = Config.BOSS_TIMERS[BossName]
            local Timer = Index and BossTimer.List()[Index]

            return Timer and BossTimer.Read(Timer) or nil
        end

        --// The selected boss that spawns soonest and its seconds, or nil.
        function BossTimer.GetSoonest(Selected)
            local BestName, BestSeconds

            for Name in pairs(Selected) do
                local Seconds = BossTimer.GetSeconds(Name)

                if Seconds and (not BestSeconds or Seconds < BestSeconds) then
                    BestName, BestSeconds = Name, Seconds
                end
            end

            return BestSeconds, BestName
        end

        return BossTimer
    end,
}
