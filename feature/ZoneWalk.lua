-- ZoneWalk walks the character to a zone in workspace (found by name, e.g.
-- "Boss03"): along a PathfindingService path when one is found, straight
-- with Humanoid:MoveTo otherwise.
--
-- Arrived means standing inside the zone's footprint (a part's or model's
-- box, seen from above), or within Config.ZONE_ARRIVE_DISTANCE of its centre
-- counting only X and Z: a zone's centre is often up in the air or under
-- the floor, out of reach in 3D. A walk that stops making progress ends
-- early instead of running into the timeout.
return {
    Name = "ZoneWalk",
    Dependencies = {"Config"},

    Start = function(Context)
        local Config = Context.Config
        local Player = Context.Player
        local Lifetime = Context.Lifetime
        local PathfindingService = game:GetService("PathfindingService")

        --// Humanoid:MoveTo gives up after 8 seconds, so it is sent again this often.
        local MOVE_REISSUE = 1
        local POLL_INTERVAL = 0.1
        --// A waypoint counts as reached within this (X and Z only).
        local WAYPOINT_REACHED = 4
        --// Moving less than STUCK_DISTANCE in STUCK_SECONDS counts as stuck.
        local STUCK_SECONDS = 3
        local STUCK_DISTANCE = 1

        local ZoneWalk = { Name = "ZoneWalk" }

        local function GetCharacter()
            local Character = Player.Character
            local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
            local Root = Character and Character:FindFirstChild("HumanoidRootPart")

            if Humanoid and Root and Humanoid.Health > 0 then
                return Humanoid, Root
            end

            return nil
        end

        local function Flat(Vector)
            return Vector3.new(Vector.X, 0, Vector.Z)
        end

        local function FlatDistance(A, B)
            return (Flat(A) - Flat(B)).Magnitude
        end

        --// The centre of the parts inside a Folder (or any container), or nil.
        local function GetPartsCenter(Container)
            local Sum, Count = Vector3.zero, 0

            for _, Descendant in ipairs(Container:GetDescendants()) do
                if Descendant:IsA("BasePart") then
                    Sum += Descendant.Position
                    Count += 1
                end
            end

            return Count > 0 and Sum / Count or nil
        end

        --// { Center, CFrame?, Size? } for a zone instance, or nil.
        local function DescribeZone(Zone)
            if Zone:IsA("BasePart") then
                return { Center = Zone.Position, CFrame = Zone.CFrame, Size = Zone.Size }
            end

            if Zone:IsA("Model") then
                local BoxCFrame, BoxSize = Zone:GetBoundingBox()
                return { Center = BoxCFrame.Position, CFrame = BoxCFrame, Size = BoxSize }
            end

            local Center = GetPartsCenter(Zone)
            return Center and { Center = Center } or nil
        end

        --// The zone (any case of ZoneName) and its description, or nil.
        function ZoneWalk.FindZone(ZoneName)
            local Wanted = string.lower(ZoneName)

            for _, Descendant in ipairs(workspace:GetDescendants()) do
                if string.lower(Descendant.Name) == Wanted then
                    local Info = DescribeZone(Descendant)

                    if Info then
                        return Descendant, Info
                    end
                end
            end

            return nil
        end

        local function IsInFootprint(Info, Position)
            if not Info.CFrame then
                return false
            end

            local Local = Info.CFrame:PointToObjectSpace(Position)
            return math.abs(Local.X) <= Info.Size.X / 2 and math.abs(Local.Z) <= Info.Size.Z / 2
        end

        local function IsArrived(Info, Root)
            return IsInFootprint(Info, Root.Position)
                or FlatDistance(Root.Position, Info.Center) <= Config.ZONE_ARRIVE_DISTANCE
        end

        --// MoveTo Target until IsDone(), stuck, or Deadline.
        --// Returns "done", "stuck" or "timeout".
        local function MoveStraight(Humanoid, Root, Target, IsDone, Deadline)
            local LastIssue = -math.huge
            local CheckAt, CheckPosition = os.clock() + STUCK_SECONDS, Root.Position

            while Lifetime.Alive and os.clock() < Deadline do
                if IsDone() then
                    return "done"
                end

                if os.clock() >= CheckAt then
                    if (Root.Position - CheckPosition).Magnitude < STUCK_DISTANCE then
                        return "stuck"
                    end

                    CheckAt, CheckPosition = os.clock() + STUCK_SECONDS, Root.Position
                end

                if os.clock() - LastIssue >= MOVE_REISSUE then
                    Humanoid:MoveTo(Target)
                    LastIssue = os.clock()
                end

                task.wait(POLL_INTERVAL)
            end

            return IsDone() and "done" or "timeout"
        end

        local function GetWaypoints(Root, Position)
            local Path = PathfindingService:CreatePath({ AgentCanJump = true })

            local Ok = pcall(function()
                Path:ComputeAsync(Root.Position, Position)
            end)

            if not Ok or Path.Status ~= Enum.PathStatus.Success then
                return nil
            end

            return Path:GetWaypoints()
        end

        --// Follows a path toward the zone; stops early once arrived.
        local function FollowPath(Humanoid, Root, Info, Deadline)
            for _, Waypoint in ipairs(GetWaypoints(Root, Info.Center) or {}) do
                if IsArrived(Info, Root) then
                    return
                end

                if Waypoint.Action == Enum.PathWaypointAction.Jump then
                    Humanoid.Jump = true
                end

                local Result = MoveStraight(Humanoid, Root, Waypoint.Position, function()
                    return IsArrived(Info, Root) or FlatDistance(Root.Position, Waypoint.Position) <= WAYPOINT_REACHED
                end, Deadline)

                if Result ~= "done" then
                    return
                end
            end
        end

        --// Walks to ZoneName. True once arrived, false and why otherwise.
        --// Yields up to Config.ZONE_WALK_TIMEOUT.
        function ZoneWalk.WalkTo(ZoneName)
            local _, Info = ZoneWalk.FindZone(ZoneName)

            if not Info then
                local Streaming = workspace.StreamingEnabled and " (StreamingEnabled: may not be loaded yet)" or ""
                return false, ZoneName .. " not found in workspace" .. Streaming
            end

            local Humanoid, Root = GetCharacter()

            if not Humanoid then
                return false, "no character"
            end

            if IsArrived(Info, Root) then
                return true
            end

            local Deadline = os.clock() + Config.ZONE_WALK_TIMEOUT
            FollowPath(Humanoid, Root, Info, Deadline)

            --// No path, or the path ran out: finish in a straight line.
            local Result = MoveStraight(Humanoid, Root, Info.Center, function()
                return IsArrived(Info, Root)
            end, Deadline)

            --// Stand still so the scan and the game's auto start from here.
            Humanoid:MoveTo(Root.Position)

            if Result == "done" then
                return true
            end

            return false, string.format("%s %s, %d studs away", Result, ZoneName, math.floor(FlatDistance(Root.Position, Info.Center)))
        end

        return ZoneWalk
    end,
}
