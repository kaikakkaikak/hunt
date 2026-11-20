-- DungeonTargets finds what the dungeon (workspace[Config.DUNGEON_ROOT_NAME])
-- has left to fight, and its boss door.
--
-- Kinds: "pillar" (Config.DUNGEON_PILLAR_NAMES: there while it stands,
-- gone once broken), "major" (a miniboss or the boss:
-- Config.DUNGEON_MAJOR_NAMES, or a name with one of
-- Config.DUNGEON_MAJOR_KEYWORDS in it) and "mob" (Config.DUNGEON_MOB_NAMES;
-- any non-player Humanoid when that list is empty). All are looked for in
-- the whole workspace, not only the dungeon's folder. A name matches when it
-- contains a listed one, ignoring case, spaces, "_" and "-" ("SheetGhost3"
-- is a "Sheet Ghost"). A monster is alive while its Humanoid is, or its
-- Health / HP attribute is above 0.
--
-- Which one to fight next (Core.Pick): the ritual pillar, then the
-- miniboss or boss, then monsters; the nearest of the same kind first.
-- Monsters passed on the way are still hit (AutoDungeon attacks anything
-- in range). Nothing left to fight: the boss door's prompt is held open.
local Core = {}

--// "Bone hound", "Bone_Hound" and "BoneHound" are the same name.
function Core.Normalize(Name)
    return (string.gsub(string.lower(Name), "[%s_%-]", ""))
end

local function MatchesName(List, Normal)
    for _, Wanted in ipairs(List) do
        if string.find(Normal, Core.Normalize(Wanted), 1, true) then
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

local PRIORITY = { pillar = 1, major = 2, mob = 3 }

--// Direction (X, Z) turned by Try eighths of a turn: try 0 is the
--// direction itself, then 45, 90, ... degrees round the target.
function Core.TurnEighths(X, Z, Try)
    local Angle = (Try % 8) * math.pi / 4
    local Cos, Sin = math.cos(Angle), math.sin(Angle)
    return X * Cos - Z * Sin, X * Sin + Z * Cos
end

--// The target to fight from Position ({ X, Y, Z }), or nil. Targets =
--// { Id, Kind, X, Y, Z, Skipped }: a skipped one (could not be reached) is
--// left for later.
--//
--// The one being fought (CurrentId) is kept while nothing of a better kind
--// shows up: "nearest" is a straight line through walls, so on the way
--// round a corner another target would keep looking nearer, and we would
--// turn back and forth between them.
function Core.Pick(Targets, Position, CurrentId)
    local Best, BestRank, BestDistance = nil, math.huge, math.huge
    local Current, CurrentRank = nil, math.huge

    for _, Target in ipairs(Targets) do
        if not Target.Skipped then
            local Distance = math.sqrt((Target.X - Position.X) ^ 2 + (Target.Y - Position.Y) ^ 2 + (Target.Z - Position.Z) ^ 2)
            local Rank = PRIORITY[Target.Kind] or math.huge

            if Rank < BestRank or (Rank == BestRank and Distance < BestDistance) then
                Best, BestRank, BestDistance = Target, Rank, Distance
            end

            if CurrentId ~= nil and Target.Id == CurrentId then
                Current, CurrentRank = Target, Rank
            end
        end
    end

    if Current and CurrentRank <= BestRank then
        return Current
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

        --// Where a target faces (level), or nil.
        local function GetLook(Object)
            local Frame

            if Object:IsA("Model") then
                local Root = Object:FindFirstChild("HumanoidRootPart") or Object.PrimaryPart
                Frame = Root and Root.CFrame or Object:GetPivot()
            elseif Object:IsA("BasePart") then
                Frame = Object.CFrame
            end

            local Look = Frame and Vector3.new(Frame.LookVector.X, 0, Frame.LookVector.Z)
            return Look and Look.Magnitude > 0.1 and Look.Unit or nil
        end

        DungeonTargets.GetLook = GetLook

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
        --// Capped: a model's box can include big invisible parts, which
        --// would put the spot to hit it from far off, even off the map.
        local function GetRadius(Object)
            local Size = Object:IsA("Model") and Object:GetExtentsSize() or Object.Size
            return math.min(math.max(Size.X, Size.Z) / 2, Config.DUNGEON_MAX_TARGET_RADIUS)
        end

        DungeonTargets.IsAlive = IsAlive

        --// Everything left to fight: { Model, Kind, Name, Position, Radius }.
        --// A Humanoid, or a health attribute: a mesh model inside a
        --// monster has neither, so it is not taken for a second one.
        local function HasHealth(Model)
            if Model:FindFirstChildOfClass("Humanoid") then
                return true
            end

            return type(Model:GetAttribute("Health") or Model:GetAttribute("HP")) == "number"
        end

        local function ScanNow()
            local Found = {}

            if not DungeonTargets.GetRoot() then
                return Found
            end

            local function Add(Object, Kind)
                local Position = GetPosition(Object)

                if Position then
                    table.insert(Found, {
                        Model = Object, Kind = Kind, Name = Object.Name,
                        Position = Position, Radius = GetRadius(Object), Look = GetLook(Object),
                    })
                end
            end

            for _, Object in ipairs(workspace:GetDescendants()) do
                if Object:IsA("Model") then
                    local Kind = Core.Kind(Object.Name, Config)

                    if Kind and Kind ~= "pillar" and HasHealth(Object) and not IsPlayerCharacter(Object) and IsAlive(Object) then
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
        local SCAN_CACHE = 0.3
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
