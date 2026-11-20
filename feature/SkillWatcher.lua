-- SkillWatcher spots the boss's skill warnings: parts that appear in
-- workspace while it is enabled, inside one of the boss's effect folders
-- (Config.DUNGEON_SKILL_FX_FOLDERS: LumiBossFx, LumiBossSkillFx) and wide
-- enough to stand in. A green one is a safe zone to fly into ("goto"); any
-- other colour is a danger zone to leave ("avoid").
--
-- Also counted: parts named in Config.DUNGEON_SKILL_PART_NAMES /
-- DUNGEON_SAFE_ZONE_NAMES and, with Config.DUNGEON_DETECT_UNNAMED on, any
-- flat, wide, non-colliding part. Outside the effect folders only warnings
-- from a boss or miniboss count: SourceIsMajor (set by AutoDungeon) decides,
-- so a normal monster's skill is ignored.
--
-- Footprints (what a warning covers, seen from above) and the safe spot to
-- dodge to are worked out on plain X / Z numbers in Core, tested in
-- tests/run.luau.
local Core = {}

local function Matches(List, Name)
    local Lower = string.lower(Name)

    for _, Wanted in ipairs(List) do
        if string.lower(Wanted) == Lower then
            return true
        end
    end

    return false
end

--// Clearly green: the green channel beats both others by Margin (0-255).
function Core.IsGreen(R, G, B, Margin)
    return G - R >= Margin and G - B >= Margin
end

local function ByColor(Info, Cfg)
    if Cfg.DUNGEON_SAFE_ZONE_BY_COLOR and Core.IsGreen(Info.R, Info.G, Info.B, Cfg.DUNGEON_GREEN_MARGIN) then
        return "goto"
    end

    return "avoid"
end

--// "goto", "avoid" or nil for a new part. Info = { Name, R, G, B (0-255),
--// SizeX, SizeY, SizeZ, CanCollide, InFxFolder }.
function Core.Classify(Info, Cfg)
    if Matches(Cfg.DUNGEON_SAFE_ZONE_NAMES, Info.Name) then
        return "goto"
    end

    if Matches(Cfg.DUNGEON_SKILL_PART_NAMES, Info.Name) then
        return "avoid"
    end

    local Sizes = { Info.SizeX, Info.SizeY, Info.SizeZ }
    table.sort(Sizes)

    --// Narrow on two sides (a beam, a spark): not an area to step out of.
    if Sizes[2] < Cfg.DUNGEON_TELEGRAPH_MIN_SIZE then
        return nil
    end

    --// The boss's own effects: any wide one, flat or not (a dome, a ring).
    if Info.InFxFolder then
        return ByColor(Info, Cfg)
    end

    --// Elsewhere: only flat, non-colliding parts, and only when allowed.
    if not Cfg.DUNGEON_DETECT_UNNAMED or Info.CanCollide or Sizes[1] > Cfg.DUNGEON_TELEGRAPH_MAX_THICKNESS then
        return nil
    end

    return ByColor(Info, Cfg)
end

--// What a part covers from above. Axes = its three sides as
--// { X, Y, Z (unit vector), Length }; Round for balls, cylinders and
--// discs. A circle { Kind, X, Z, Radius } or a box { Kind, X, Z, AX, AZ,
--// BX, BZ (unit sides), HalfA, HalfB }.
function Core.Footprint(X, Z, Axes, Round)
    local Sorted = table.clone(Axes)

    --// The two sides closest to level make the footprint.
    table.sort(Sorted, function(Left, Right)
        return math.abs(Left.Y) < math.abs(Right.Y)
    end)

    local Flat = {}

    for Index = 1, 2 do
        local Axis = Sorted[Index]
        local Level = math.sqrt(Axis.X * Axis.X + Axis.Z * Axis.Z)

        if Level < 1e-6 then
            Flat[Index] = { X = 1, Z = 0, Half = 0 }
        else
            Flat[Index] = { X = Axis.X / Level, Z = Axis.Z / Level, Half = Axis.Length / 2 * Level }
        end
    end

    if Round then
        return { Kind = "circle", X = X, Z = Z, Radius = math.max(Flat[1].Half, Flat[2].Half) }
    end

    return {
        Kind = "box", X = X, Z = Z,
        AX = Flat[1].X, AZ = Flat[1].Z, HalfA = Flat[1].Half,
        BX = Flat[2].X, BZ = Flat[2].Z, HalfB = Flat[2].Half,
    }
end

--// The point (X, Z) is inside the footprint grown by Margin.
function Core.Contains(Hazard, X, Z, Margin)
    local DX, DZ = X - Hazard.X, Z - Hazard.Z

    if Hazard.Kind == "circle" then
        local Reach = Hazard.Radius + Margin
        return DX * DX + DZ * DZ <= Reach * Reach
    end

    local AlongA = math.abs(DX * Hazard.AX + DZ * Hazard.AZ)
    local AlongB = math.abs(DX * Hazard.BX + DZ * Hazard.BZ)
    return AlongA <= Hazard.HalfA + Margin and AlongB <= Hazard.HalfB + Margin
end

function Core.InAny(Hazards, X, Z, Margin)
    for _, Hazard in ipairs(Hazards) do
        if Core.Contains(Hazard, X, Z, Margin) then
            return true
        end
    end

    return false
end

local RING_POINTS = 16

--// Where to dodge to from (X, Z): outside every hazard by
--// Cfg.DUNGEON_DODGE_MARGIN, close to us, and as near Cfg.DUNGEON_ATTACK_DISTANCE
--// from Anchor (the boss, or nil) as possible so the fight goes on.
--// IsUsable(X, Z) is asked in order of preference (floor, no wall in the
--// way). Returns X, Z or nil.
function Core.FindSafeSpot(X, Z, Hazards, Anchor, Cfg, IsUsable)
    local Candidates = {}
    local Step = Cfg.DUNGEON_DODGE_STEP

    for Distance = Step, Cfg.DUNGEON_DODGE_MAX_DISTANCE, Step do
        for Index = 0, RING_POINTS - 1 do
            local Angle = Index / RING_POINTS * math.pi * 2
            local PX, PZ = X + math.cos(Angle) * Distance, Z + math.sin(Angle) * Distance

            if not Core.InAny(Hazards, PX, PZ, Cfg.DUNGEON_DODGE_MARGIN) then
                local Score = Distance

                if Anchor then
                    local FromAnchor = math.sqrt((PX - Anchor.X) ^ 2 + (PZ - Anchor.Z) ^ 2)
                    Score += math.abs(FromAnchor - Cfg.DUNGEON_ATTACK_DISTANCE) * 0.5
                end

                table.insert(Candidates, { X = PX, Z = PZ, Score = Score })
            end
        end
    end

    table.sort(Candidates, function(Left, Right)
        return Left.Score < Right.Score
    end)

    for _, Candidate in ipairs(Candidates) do
        if IsUsable(Candidate.X, Candidate.Z) then
            return Candidate.X, Candidate.Z
        end
    end

    return nil
end

return {
    Name = "SkillWatcher",
    Dependencies = {"Config"},
    Core = Core,

    Start = function(Context)
        local Config = Context.Config
        local Lifetime = Context.Lifetime
        local Players = Context.Services.Players

        local SkillWatcher = {
            Name = "SkillWatcher",
            Core = Core,
            S = {
                Enabled = false,
                --// { Part, Kind, Expires }
                Entries = {},
            },
            --// Part -> the warning comes from a boss or miniboss. Set by
            --// AutoDungeon; nothing counts until then.
            SourceIsMajor = function()
                return false
            end,
            --// Called on every new warning that counts.
            OnWarning = function() end,
        }

        local S = SkillWatcher.S

        local function IsOnPlayer(Part)
            for _, Other in ipairs(Players:GetPlayers()) do
                if Other.Character and Part:IsDescendantOf(Other.Character) then
                    return true
                end
            end

            return false
        end

        --// The part's colour, or its decal's when the part itself is hidden.
        local function GetColor(Part)
            if Part.Transparency >= 0.95 then
                local Decal = Part:FindFirstChildWhichIsA("Decal")

                if Decal then
                    return Decal.Color3
                end
            end

            return Part.Color
        end

        local function IsInFxFolder(Part)
            for _, Name in ipairs(Config.DUNGEON_SKILL_FX_FOLDERS) do
                if Part:FindFirstAncestor(Name) then
                    return true
                end
            end

            return false
        end

        local function Describe(Part, InFxFolder)
            local Color = GetColor(Part)

            return {
                Name = Part.Name,
                R = Color.R * 255, G = Color.G * 255, B = Color.B * 255,
                SizeX = Part.Size.X, SizeY = Part.Size.Y, SizeZ = Part.Size.Z,
                CanCollide = Part.CanCollide,
                InFxFolder = InFxFolder,
            }
        end

        local function Consider(Part)
            if not S.Enabled or not Part.Parent or IsOnPlayer(Part) then
                return
            end

            local InFxFolder = IsInFxFolder(Part)
            local Kind = Core.Classify(Describe(Part, InFxFolder), Config)

            --// The boss's effect folders hold only its skills.
            if not Kind or not (InFxFolder or SkillWatcher.SourceIsMajor(Part)) then
                return
            end

            table.insert(S.Entries, { Part = Part, Kind = Kind, Expires = os.clock() + Config.DUNGEON_TELEGRAPH_MAX_SECONDS })
            SkillWatcher.OnWarning()
        end

        Lifetime.Connect(workspace.DescendantAdded, function(Instance)
            if S.Enabled and Instance:IsA("BasePart") then
                --// Deferred: the game sets size and colour right after parenting.
                task.defer(Consider, Instance)
            end
        end)

        local function IsRound(Part)
            if Part:IsA("Part") then
                return Part.Shape == Enum.PartType.Ball or Part.Shape == Enum.PartType.Cylinder
            end

            --// A mesh about as wide as it is deep is taken to be a circle.
            local Sizes = { Part.Size.X, Part.Size.Y, Part.Size.Z }
            table.sort(Sizes)
            return Sizes[3] - Sizes[2] <= Sizes[3] * 0.15
        end

        --// The footprint of a part, read live (warnings often grow).
        function SkillWatcher.FootprintOf(Part)
            local Frame, Size = Part.CFrame, Part.Size
            local Axes = {
                { X = Frame.RightVector.X, Y = Frame.RightVector.Y, Z = Frame.RightVector.Z, Length = Size.X },
                { X = Frame.UpVector.X, Y = Frame.UpVector.Y, Z = Frame.UpVector.Z, Length = Size.Y },
                { X = Frame.LookVector.X, Y = Frame.LookVector.Y, Z = Frame.LookVector.Z, Length = Size.Z },
            }

            return Core.Footprint(Part.Position.X, Part.Position.Z, Axes, IsRound(Part))
        end

        --// Live warnings: the danger footprints, and the safe zones as
        --// { Hazard, Position }. Drops the ones that are gone or too old.
        function SkillWatcher.GetActive()
            local Now = os.clock()
            local Kept, Avoid, Goto = {}, {}, {}

            for _, Entry in ipairs(S.Entries) do
                if Entry.Part.Parent and Now < Entry.Expires then
                    table.insert(Kept, Entry)

                    local Footprint = SkillWatcher.FootprintOf(Entry.Part)

                    if Entry.Kind == "goto" then
                        table.insert(Goto, { Hazard = Footprint, Position = Entry.Part.Position })
                    else
                        table.insert(Avoid, Footprint)
                    end
                end
            end

            S.Entries = Kept
            return Avoid, Goto
        end

        function SkillWatcher.SetEnabled(Enabled)
            S.Enabled = Enabled == true

            if not S.Enabled then
                S.Entries = {}
            end
        end

        return SkillWatcher
    end,
}
