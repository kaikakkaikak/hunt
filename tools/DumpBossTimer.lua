-- Prints every instance in workspace whose name contains "timer" or a
-- Config boss name, with its children: class, Text / Value and attributes.
-- Run it in the executor while the timer is counting down, then again while
-- the boss is alive, and send both outputs.
local KEYWORDS = { "timer", "obsidian", "pharaoh", "tempest", "dragon", "whitefang", "sabertooth", "volcano", "turtle" }
local MAX_DEPTH = 6

local function Describe(Object)
    local Parts = { Object.ClassName }

    if Object:IsA("TextLabel") or Object:IsA("TextButton") or Object:IsA("TextBox") then
        table.insert(Parts, string.format("Text=%q", Object.Text))
    elseif Object:IsA("ValueBase") then
        table.insert(Parts, "Value=" .. tostring(Object.Value))
    end

    for Name, Value in pairs(Object:GetAttributes()) do
        table.insert(Parts, string.format("@%s=%s", Name, tostring(Value)))
    end

    return table.concat(Parts, "  ")
end

local function Dump(Object, Depth)
    print(string.rep("  ", Depth) .. Object.Name .. "  [" .. Describe(Object) .. "]")

    if Depth >= MAX_DEPTH then
        return
    end

    for _, Child in ipairs(Object:GetChildren()) do
        Dump(Child, Depth + 1)
    end
end

local function Matches(Name)
    local Lower = string.lower(Name)

    for _, Keyword in ipairs(KEYWORDS) do
        if string.find(Lower, Keyword, 1, true) then
            return true
        end
    end

    return false
end

print("==== BossTimer dump ====")

for _, Object in ipairs(workspace:GetDescendants()) do
    if Matches(Object.Name) and not Matches(Object.Parent.Name) then
        print("PATH: " .. Object:GetFullName())
        Dump(Object, 0)
    end
end

--// Numbered the way feature/BossTimer.lua counts them (Config.BOSS_TIMERS).
print("==== bosstimer order ====")

local Index = 0

for _, Object in ipairs(workspace:GetDescendants()) do
    if string.lower(Object.Name) == "bosstimer" then
        Index += 1
        print(string.format("#%d  %s", Index, Object:GetFullName()))
        Dump(Object, 1)
    end
end

print("==== end ====")
