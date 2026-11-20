-- Prints what AutoDungeon needs to know about the dungeon, for Config:
--   1. every monster (a Model with a Humanoid) in workspace.Halloween, the
--      ritual pillar, and every ProximityPrompt (the boss door);
--   2. then, for WATCH_SECONDS, every new part in workspace: run it right
--      before the boss uses its skills (and its green circle) and send the
--      output.
local ROOT_NAME = "Halloween"
local WATCH_SECONDS = 60
local Players = game:GetService("Players")

local Root = workspace:FindFirstChild(ROOT_NAME)

local function Fmt(Number)
    return string.format("%.1f", Number)
end

local function Vec(Vector)
    return Fmt(Vector.X) .. "," .. Fmt(Vector.Y) .. "," .. Fmt(Vector.Z)
end

local function Rgb(Color)
    return string.format("%d,%d,%d", Color.R * 255, Color.G * 255, Color.B * 255)
end

print("==== DumpDungeon ====")

if not Root then
    warn("workspace." .. ROOT_NAME .. " not found. Top level of workspace:")

    for _, Child in ipairs(workspace:GetChildren()) do
        print("  " .. Child.Name .. "  [" .. Child.ClassName .. "]")
    end
else
    print("---- monsters ----")
    local Counts = {}

    for _, Object in ipairs(Root:GetDescendants()) do
        local Humanoid = Object:IsA("Model") and Object:FindFirstChildOfClass("Humanoid")

        if Humanoid and not Players:GetPlayerFromCharacter(Object) then
            Counts[Object.Name] = (Counts[Object.Name] or 0) + 1

            if Counts[Object.Name] <= 2 then
                print(string.format("%s  HP=%s/%s  %s", Object.Name, Fmt(Humanoid.Health), Fmt(Humanoid.MaxHealth), Object:GetFullName()))
            end
        end
    end

    for Name, Count in pairs(Counts) do
        print(string.format("  %s x%d", Name, Count))
    end

    print("---- pillar ----")

    for _, Object in ipairs(Root:GetDescendants()) do
        if string.find(string.lower(Object.Name), "pillar", 1, true) then
            local Attributes = {}

            for Name, Value in pairs(Object:GetAttributes()) do
                table.insert(Attributes, "@" .. Name .. "=" .. tostring(Value))
            end

            print(string.format("%s [%s] %s %s", Object.Name, Object.ClassName, Object:GetFullName(), table.concat(Attributes, " ")))
        end
    end

    print("---- prompts ----")

    for _, Prompt in ipairs(Root:GetDescendants()) do
        if Prompt:IsA("ProximityPrompt") then
            print(string.format("%q action=%q object=%q hold=%s range=%s enabled=%s  %s",
                Prompt.Name, Prompt.ActionText, Prompt.ObjectText, Fmt(Prompt.HoldDuration),
                Fmt(Prompt.MaxActivationDistance), tostring(Prompt.Enabled), Prompt:GetFullName()))
        end
    end
end

print(string.format("---- new parts for %ds: fight the boss now ----", WATCH_SECONDS))

local Seen = {}

local function IsOnPlayer(Part)
    for _, Player in ipairs(Players:GetPlayers()) do
        if Player.Character and Part:IsDescendantOf(Player.Character) then
            return true
        end
    end

    return false
end

local function Report(Part)
    if not Part.Parent or IsOnPlayer(Part) then
        return
    end

    --// One line per kind of part, not per copy.
    local Key = Part.Name .. "|" .. Part.Parent.Name .. "|" .. Vec(Part.Size)

    if Seen[Key] then
        return
    end

    Seen[Key] = true

    local Shape = Part:IsA("Part") and Part.Shape.Name or Part.ClassName
    local Decal = Part:FindFirstChildWhichIsA("Decal")
    local DecalText = Decal and (" decal=" .. Decal.Texture .. " decalColor=" .. Rgb(Decal.Color3)) or ""

    print(string.format("%s [%s] size=%s color=%s transp=%s collide=%s%s  %s",
        Part.Name, Shape, Vec(Part.Size), Rgb(Part.Color), Fmt(Part.Transparency),
        tostring(Part.CanCollide), DecalText, Part:GetFullName()))
end

local Connection = workspace.DescendantAdded:Connect(function(Instance)
    if Instance:IsA("BasePart") then
        task.defer(Report, Instance)
    end
end)

task.delay(WATCH_SECONDS, function()
    Connection:Disconnect()
    print("==== end ====")
end)
