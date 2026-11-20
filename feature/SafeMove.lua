-- SafeMove flies the character with TweenService, a little above the floor,
-- without passing through walls.
--
-- A tween sets the position directly, so the physics would never stop it at
-- a wall: every leg is checked first with a Blockcast the size of the
-- character (Config.DUNGEON_SWEEP_SIZE), counting only parts that collide.
-- A blocked straight line is replaced by a PathfindingService path, flown
-- waypoint by waypoint, each leg checked the same way. Points with no floor
-- under them (pits, out of the map) are never flown to.
--
-- While engaged, the character is held at the tween's position every frame
-- (velocity zeroed so it does not fall) at Config.DUNGEON_HOVER_OFFSET
-- above its standing height, facing what SetFacing gave. Speed is the
-- Humanoid's WalkSpeed times Config.DUNGEON_SPEED_MULTIPLIER.
local Core = {}

--// Seconds to fly Distance at WalkSpeed * Multiplier (never below 1 stud/s).
function Core.TweenSeconds(Distance, WalkSpeed, Multiplier)
    return Distance / math.max(WalkSpeed * Multiplier, 1)
end

--// How far along a leg of Length to stop so it is at most MaxStep long:
--// a fraction from 0 to 1.
function Core.StepFraction(Length, MaxStep)
    if Length <= MaxStep or Length <= 0 then
        return 1
    end

    return MaxStep / Length
end

--// The root's height above the floor when standing: R15 from HipHeight,
--// R6 (HipHeight 0) from its fixed leg length.
function Core.StandHeight(HipHeight, RootHeight)
    if HipHeight > 0 then
        return HipHeight + RootHeight / 2
    end

    return 3
end

return {
    Name = "SafeMove",
    Dependencies = {"Config"},
    Core = Core,

    Start = function(Context)
        local Config = Context.Config
        local Player = Context.Player
        local Lifetime = Context.Lifetime
        local Players = Context.Services.Players
        local RunService = game:GetService("RunService")
        local TweenService = game:GetService("TweenService")
        local PathfindingService = game:GetService("PathfindingService")

        --// The floor is looked for from this far above a point, this far down.
        local FLOOR_SEARCH_UP = 6
        local FLOOR_SEARCH_DOWN = 60
        --// A path's later waypoints are tried first, up to this many ahead,
        --// so a clear shortcut skips the ones in between.
        local PATH_LOOKAHEAD = 6
        local SWEEP_SIZE = Vector3.new(table.unpack(Config.DUNGEON_SWEEP_SIZE))

        local SafeMove = {
            Name = "SafeMove",
            Core = Core,
            S = {
                Engaged = false,
                --// Where the character is held, and what it faces.
                Goal = nil,
                Facing = nil,
                Tween = nil,
                Connection = nil,
                --// Models the sweeps and floor checks ignore (enemies).
                Ignore = {},
            },
        }

        local S = SafeMove.S
        local GoalValue = Instance.new("Vector3Value")

        Lifetime.Connect(GoalValue.Changed, function(Value)
            S.Goal = Value
        end)

        local function GetCharacter()
            local Character = Player.Character
            local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
            local Root = Character and Character:FindFirstChild("HumanoidRootPart")

            if Humanoid and Root and Humanoid.Health > 0 then
                return Character, Humanoid, Root
            end

            return nil
        end

        SafeMove.GetCharacter = GetCharacter

        local function BuildParams()
            local Exclude = {}

            for _, Other in ipairs(Players:GetPlayers()) do
                if Other.Character then
                    table.insert(Exclude, Other.Character)
                end
            end

            for _, Model in ipairs(S.Ignore) do
                table.insert(Exclude, Model)
            end

            local Params = RaycastParams.new()
            Params.FilterType = Enum.RaycastFilterType.Exclude
            Params.FilterDescendantsInstances = Exclude
            Params.RespectCanCollide = true
            return Params
        end

        --// Enemies and the like: never walls, never floors.
        function SafeMove.SetIgnore(Models)
            S.Ignore = Models
        end

        function SafeMove.SetFacing(Position)
            S.Facing = Position
        end

        --// How far above the floor the root is held.
        function SafeMove.HoverHeight(Humanoid, Root)
            return Core.StandHeight(Humanoid.HipHeight, Root.Size.Y) + Config.DUNGEON_HOVER_OFFSET
        end

        --// The point above Position's floor where the root is held, or nil
        --// when there is no floor under it.
        function SafeMove.HoverPoint(Position)
            local _, Humanoid, Root = GetCharacter()

            if not Humanoid then
                return nil
            end

            local Origin = Vector3.new(Position.X, Position.Y + FLOOR_SEARCH_UP, Position.Z)
            local Hit = workspace:Raycast(Origin, Vector3.new(0, -FLOOR_SEARCH_DOWN, 0), BuildParams())

            if not Hit then
                return nil
            end

            return Vector3.new(Position.X, Hit.Position.Y + SafeMove.HoverHeight(Humanoid, Root), Position.Z)
        end

        --// Nothing that collides between From and To for a box the size of
        --// the character.
        function SafeMove.IsClear(From, To)
            local Offset = To - From

            if Offset.Magnitude < 0.05 then
                return true
            end

            --// A level box: tilted on a slope its corner would dig into the floor.
            local Hit = workspace:Blockcast(CFrame.new(From), SWEEP_SIZE, Offset, BuildParams())
            return Hit == nil
        end

        --// Where the character is (held), or nil without a live one.
        function SafeMove.GetPosition()
            local _, _, Root = GetCharacter()

            if not Root then
                return nil
            end

            return S.Engaged and S.Goal or Root.Position
        end

        local function Hold()
            local _, _, Root = GetCharacter()

            if not Root or not S.Goal then
                return
            end

            local Facing = S.Facing and Vector3.new(S.Facing.X, S.Goal.Y, S.Facing.Z)

            if Facing and (Facing - S.Goal).Magnitude > 0.1 then
                Root.CFrame = CFrame.lookAt(S.Goal, Facing)
            else
                Root.CFrame = CFrame.new(S.Goal) * Root.CFrame.Rotation
            end

            Root.AssemblyLinearVelocity = Vector3.zero
            Root.AssemblyAngularVelocity = Vector3.zero
        end

        --// Starts holding the character where it is. False with no character.
        function SafeMove.Engage()
            if S.Engaged then
                return true
            end

            local _, _, Root = GetCharacter()

            if not Root then
                return false
            end

            GoalValue.Value = Root.Position
            S.Goal = Root.Position
            S.Engaged = true
            S.Connection = RunService.Heartbeat:Connect(Hold)
            return true
        end

        function SafeMove.Cancel()
            if S.Tween then
                S.Tween:Cancel()
                S.Tween = nil
            end
        end

        --// Lets the character go (it falls back to the floor).
        function SafeMove.Release()
            SafeMove.Cancel()
            S.Engaged = false
            S.Facing = nil

            if S.Connection then
                S.Connection:Disconnect()
                S.Connection = nil
            end
        end

        --// Flies to Position (already checked). True when it got there,
        --// false when cancelled. Yields.
        local function FlyTo(Position)
            local _, Humanoid = GetCharacter()

            if not Humanoid or not S.Engaged then
                return false
            end

            SafeMove.Cancel()

            local Seconds = Core.TweenSeconds((Position - S.Goal).Magnitude, Humanoid.WalkSpeed, Config.DUNGEON_SPEED_MULTIPLIER)
            local Tween = TweenService:Create(GoalValue, TweenInfo.new(Seconds, Enum.EasingStyle.Linear), { Value = Position })
            S.Tween = Tween
            Tween:Play()

            local State = Tween.Completed:Wait()

            if S.Tween == Tween then
                S.Tween = nil
            end

            return State == Enum.PlaybackState.Completed
        end

        local function GetPathPoints(From, To)
            local Path = PathfindingService:CreatePath({ AgentCanJump = true })

            local Ok = pcall(function()
                Path:ComputeAsync(From, To)
            end)

            if not Ok or Path.Status ~= Enum.PathStatus.Success then
                return nil
            end

            local Points = {}

            for Index, Waypoint in ipairs(Path:GetWaypoints()) do
                local Point = Index > 1 and SafeMove.HoverPoint(Waypoint.Position)

                if Point then
                    table.insert(Points, Point)
                end
            end

            return Points
        end

        --// The next point to fly to on the way to Target (a hover point):
        --// Target itself when the line is clear, else the furthest clear
        --// waypoint of a path. Nil and why when there is none.
        local function NextPoint(From, Target)
            if SafeMove.IsClear(From, Target) then
                return Target
            end

            --// Paths are found between floor points, not hover points.
            local _, Humanoid, Root = GetCharacter()
            local Down = Vector3.new(0, Humanoid and SafeMove.HoverHeight(Humanoid, Root) or 0, 0)
            local Points = GetPathPoints(From - Down, Target - Down)

            if not Points or #Points == 0 then
                return nil, "no path"
            end

            for Index = math.min(#Points, PATH_LOOKAHEAD), 1, -1 do
                if SafeMove.IsClear(From, Points[Index]) then
                    return Points[Index]
                end
            end

            return nil, "path blocked"
        end

        --// One leg (at most Config.DUNGEON_STEP_STUDS) toward Destination.
        --// "arrived" within ArriveDistance, "moved", "cancelled", or
        --// "blocked" and why. Yields while flying.
        function SafeMove.StepToward(Destination, ArriveDistance)
            if not S.Engaged and not SafeMove.Engage() then
                return "blocked", "no character"
            end

            local Target = SafeMove.HoverPoint(Destination)

            if not Target then
                return "blocked", "no floor"
            end

            local From = S.Goal

            if (Target - From).Magnitude <= ArriveDistance then
                return "arrived"
            end

            local Point, Why = NextPoint(From, Target)

            if not Point then
                return "blocked", Why
            end

            local Leg = Point - From
            local Stop = From + Leg * Core.StepFraction(Leg.Magnitude, Config.DUNGEON_STEP_STUDS)

            return FlyTo(Stop) and "moved" or "cancelled"
        end

        --// A fresh character must not be pulled back to where the old one was.
        Lifetime.Connect(Player.CharacterAdded, SafeMove.Release)

        Lifetime.OnEnd(function()
            SafeMove.Release()
            GoalValue:Destroy()
        end)

        return SafeMove
    end,
}
