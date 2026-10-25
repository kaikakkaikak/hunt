-- ZoneWalk walks the character to a zone in workspace (found by name, e.g.
-- "Boss03"): along a PathfindingService path when one is found, straight
-- with Humanoid:MoveTo otherwise.
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
        --// A waypoint counts as reached within this.
        local WAYPOINT_REACHED = 4

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

        local function GetPosition(Zone)
            if Zone:IsA("BasePart") then
                return Zone.Position
            end

            if Zone:IsA("Model") then
                return Zone:GetPivot().Position
            end

            return GetPartsCenter(Zone)
        end

        --// The zone's position and the instance used, or nil when no
        --// instance of that name (any case) with a position is in workspace.
        function ZoneWalk.GetZonePosition(ZoneName)
            local Wanted = string.lower(ZoneName)

            for _, Descendant in ipairs(workspace:GetDescendants()) do
                if string.lower(Descendant.Name) == Wanted then
                    local Position = GetPosition(Descendant)

                    if Position then
                        return Position, Descendant
                    end
                end
            end

            return nil
        end

        local function Distance(Root, Position)
            return (Root.Position - Position).Magnitude
        end

        --// MoveTo Position until within Reach or Deadline. True when reached.
        local function MoveStraight(Humanoid, Root, Position, Reach, Deadline)
            local LastIssue = -math.huge

            while Lifetime.Alive and os.clock() < Deadline do
                if Distance(Root, Position) <= Reach then
                    return true
                end

                if os.clock() - LastIssue >= MOVE_REISSUE then
                    Humanoid:MoveTo(Position)
                    LastIssue = os.clock()
                end

                task.wait(POLL_INTERVAL)
            end

            return Distance(Root, Position) <= Reach
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

        --// Walks to ZoneName. True when within Config.ZONE_ARRIVE_DISTANCE,
        --// false and why otherwise. Yields up to Config.ZONE_WALK_TIMEOUT.
        function ZoneWalk.WalkTo(ZoneName)
            local Position = ZoneWalk.GetZonePosition(ZoneName)

            if not Position then
                local Streaming = workspace.StreamingEnabled and " (StreamingEnabled: may not be loaded yet)" or ""
                return false, ZoneName .. " not found in workspace" .. Streaming
            end

            local Humanoid, Root = GetCharacter()

            if not Humanoid then
                return false, "no character"
            end

            local Reach = Config.ZONE_ARRIVE_DISTANCE
            local Deadline = os.clock() + Config.ZONE_WALK_TIMEOUT

            if Distance(Root, Position) <= Reach then
                return true
            end

            for _, Waypoint in ipairs(GetWaypoints(Root, Position) or {}) do
                if Waypoint.Action == Enum.PathWaypointAction.Jump then
                    Humanoid.Jump = true
                end

                if not MoveStraight(Humanoid, Root, Waypoint.Position, WAYPOINT_REACHED, Deadline) then
                    break
                end
            end

            --// No path, or the path ran out: finish in a straight line.
            if MoveStraight(Humanoid, Root, Position, Reach, Deadline) then
                return true
            end

            return false, "could not reach " .. ZoneName
        end

        return ZoneWalk
    end,
}
