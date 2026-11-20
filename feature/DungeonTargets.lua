-- DungeonTargets finds what the dungeon (workspace[Config.DUNGEON_ROOT_NAME])
-- has left to fight, and its boss door.
--
-- Kinds: "pillar" (Config.DUNGEON_PILLAR_NAMES, anywhere in workspace: it is
-- there while it stands, gone once broken), "major" (a miniboss or the
-- boss: Config.DUNGEON_MAJOR_NAMES, or a name with one of
-- Config.DUNGEON_MAJOR_KEYWORDS in it) and "mob" (a living Humanoid named in
-- Config.DUNGEON_MOB_NAMES; any non-player one when that list is empty).
-- Names match ignoring case, spaces, "_" and "-".
--
-- Which one to fight next (Core.Pick), matching the dungeon's order:
--   1. a mob within Config.DUNGEON_ENGAGE_RADIUS: the ones on the way;
--   2. the nearest mob anywhere: the five rooms;
--   3. the nearest ritual pillar;
--   4. the nearest miniboss or boss.
-- Nothing left to fight: the boss door's prompt is held open.
local Core = {}

--// "Bone hound", "Bone_Hound" and "BoneHound" are the same name.
function Core.Normalize(Name)
    return (string.gsub(string.lower(Name), "[%s_%-]", ""))
end

local function MatchesName(List, Normal)
    for _, Wanted in ipairs(List) do
        if Core.Normalize(Wanted) == Normal then
            return true
        end
    end

    return false
end

local function ContainsKeyword(List, Lower)
    for _, Keyword in ipairs(List) do
        if string.find(Lower, string.lower(Keyword), 1, true) then
            return true
        end
    end

    return false
end

--// "pillar", "major", "mob", or nil for a model that is not fought.
function Core.Kind(Name, Cfg)
    local Normal = Core.Normalize(Name)

    if MatchesName(Cfg.DUNGEON_PILLAR_NAMES, Normal) then
        return "pillar"
    end

    if MatchesName(Cfg.DUNGEON_MAJOR_NAMES, Normal) or ContainsKeyword(Cfg.DUNGEON_MAJOR_KEYWORDS, string.lower(Name)) then
        return "major"
    end

    if #Cfg.DUNGEON_MOB_NAMES == 0 or MatchesName(Cfg.DUNGEON_MOB_NAMES, Normal) then
        return "mob"
    end

    return nil
end

--// Any of the texts has a door keyword in it (no keywords: any text does).
function Core.IsDoorText(Texts, Cfg)
    if #Cfg.DUNGEON_DOOR_KEYWORDS == 0 then
        return true
    end

    for _, Text in ipairs(Texts) do
        if ContainsKeyword(Cfg.DUNGEON_DOOR_KEYWORDS, string.lower(Text)) then
            return true
        end
    end

    return false
end

local PRIORITY = { pillar = 3, major = 4 }

--// The target to fight from Position ({ X, Y, Z }), or nil. Targets =
--// { Kind, X, Y, Z, Skipped }: a skipped one (could not be reached) is
--// left for later.
function Core.Pick(Targets, Position, Cfg)
    local Best, BestRank, BestDistance = nil, math.huge, math.huge

    for _, Target in ipairs(Targets) do
        if not Target.Skipped then
            local Distance = math.sqrt((Target.X - Position.X) ^ 2 + (Target.Y - Position.Y) ^ 2 + (Target.Z - Position.Z) ^ 2)
            local Rank = PRIORITY[Target.Kind]

            if not Rank then
                Rank = Distance <= Cfg.DUNGEON_ENGAGE_RADIUS and 1 or 2
            end

            if Rank < BestRank or (Rank == BestRank and Distance < BestDistance) then
                Best, BestRank, BestDistance = Target, Rank, Distance
            end
        end
    end

    return Best
end

return {
    Name = "DungeonTargets",
    Dependencies = {"Config", "KeyPress"},
    Core = Core,

    Start = function(Context)
        local Config = Context.Config
        local KeyPress = Context.KeyPress
        local Players = Context.Services.Players

        --// After the hold, the door gets this long to open.
        local DOOR_SETTLE = 0.3

        local DungeonTargets = { Name = "DungeonTargets", Core = Core }

        function DungeonTargets.GetRoot()
            return workspace:FindFirstChild(Config.DUNGEON_ROOT_NAME)
        end

        local function GetPosition(Object)
            if Object:IsA("BasePart") then
                return Object.Position
            end

            if Object:IsA("Attachment") then
                return Object.WorldPosition
            end

            if Object:IsA("Model") then
                local Root = Object:FindFirstChild("HumanoidRootPart") or Object.PrimaryPart

                return Root and Root.Position or Object:GetPivot().Position
            end

            return nil
        end

        DungeonTargets.GetPosition = GetPosition

        --// Alive: a living Humanoid, else a positive Health / HP attribute,
        --// else simply still there.
        local function IsAlive(Object)
            local Humanoid = Object:FindFirstChildOfClass("Humanoid")

            if Humanoid then
                return Humanoid.Health > 0
            end

            local Health = Object:GetAttribute("Health") or Object:GetAttribute("HP")

            if type(Health) == "number" then
                return Health > 0
            end

            return true
        end

        local function IsPlayerCharacter(Model)
            return Players:GetPlayerFromCharacter(Model) ~= nil
        end

        --// Half its width seen from above, so big targets (the pillar) are
        --// hit from outside them.
        local function GetRadius(Object)
            local Size = Object:IsA("Model") and Object:GetExtentsSize() or Object.Size
            return math.max(Size.X, Size.Z) / 2
        end

        DungeonTargets.IsAlive = IsAlive

        --// Everything left to fight: { Model, Kind, Name, Position, Radius }.
        local function ScanNow()
            local Root = DungeonTargets.GetRoot()
            local Found = {}

            if not Root then
                return Found
            end

            local function Add(Object, Kind)
                local Position = GetPosition(Object)

                if Position then
                    table.insert(Found, { Model = Object, Kind = Kind, Name = Object.Name, Position = Position, Radius = GetRadius(Object) })
                end
            end

            for _, Object in ipairs(Root:GetDescendants()) do
                if Object:IsA("Model") then
                    local Kind = Core.Kind(Object.Name, Config)

                    if Kind and Kind ~= "pillar" and Object:FindFirstChildOfClass("Humanoid") and not IsPlayerCharacter(Object) and IsAlive(Object) then
                        Add(Object, Kind)
                    end
                end
            end

            --// The pillar may sit outside the dungeon's folder; it standing
            --// at all means it is not broken yet.
            for _, Name in ipairs(Config.DUNGEON_PILLAR_NAMES) do
                local Pillar = workspace:FindFirstChild(Name, true)

                if Pillar and (Pillar:IsA("Model") or Pillar:IsA("BasePart")) and IsAlive(Pillar) then
                    Add(Pillar, "pillar")
                end
            end

            return Found
        end

        --// ScanNow, reused for SCAN_CACHE seconds: a big map's descendants
        --// are too many to walk every frame.
        local SCAN_CACHE = 0.15
        local Cached, CachedAt = nil, -math.huge

        function DungeonTargets.Scan()
            if not Cached or os.clock() - CachedAt >= SCAN_CACHE then
                Cached, CachedAt = ScanNow(), os.clock()
            end

            return Cached
        end

        --// The boss door's enabled prompt, or nil.
        function DungeonTargets.FindDoor()
            local Root = DungeonTargets.GetRoot()

            if not Root then
                return nil
            end

            for _, Prompt in ipairs(Root:GetDescendants()) do
                if Prompt:IsA("ProximityPrompt") and Prompt.Enabled then
                    local Parent = Prompt.Parent
                    local Texts = { Prompt.Name, Prompt.ActionText, Prompt.ObjectText, Parent and Parent.Name or "" }

                    if Parent and Parent.Parent then
                        table.insert(Texts, Parent.Parent.Name)
                    end

                    if Core.IsDoorText(Texts, Config) and GetPosition(Parent) then
                        return Prompt
                    end
                end
            end

            return nil
        end

        local function HoldPrompt(Prompt)
            Prompt:InputHoldBegin()
            task.wait(Prompt.HoldDuration + DOOR_SETTLE)
            Prompt:InputHoldEnd()
        end

        --// One way to open the door per try, cycling: the executor's
        --// fireproximityprompt, the prompt's own hold, then holding E.
        local OPENERS = {
            function(Prompt)
                if type(fireproximityprompt) ~= "function" then
                    return false
                end

                fireproximityprompt(Prompt)
                task.wait(DOOR_SETTLE)
                return true
            end,
            function(Prompt)
                HoldPrompt(Prompt)
                return true
            end,
            function(Prompt)
                local Key = Enum.KeyCode[Config.DUNGEON_DOOR_KEY]
                return KeyPress.Hold(Key, Prompt.HoldDuration + DOOR_SETTLE)
            end,
        }

        --// Try number Try (1, 2, ...) at opening the door; we must be in
        --// range already. True when a method could be used.
        function DungeonTargets.OpenDoor(Prompt, Try)
            local Opener = OPENERS[(Try - 1) % #OPENERS + 1]
            local Ok, Used = pcall(Opener, Prompt)
            return Ok and Used == true
        end

        return DungeonTargets
    end,
}
