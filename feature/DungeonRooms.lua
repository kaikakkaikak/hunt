-- DungeonRooms lists the dungeon's rooms, so AutoDungeon can fly into each
-- one: monsters only spawn once someone gets there.
--
-- A room is anything in workspace[Config.DUNGEON_ROOT_NAME] (a Model,
-- Folder or part) whose name contains one of Config.DUNGEON_ROOM_NAMES or,
-- when that list is empty, one of Config.DUNGEON_ROOM_KEYWORDS ("Room3",
-- "MobSpawn", "WaveTrigger"). Only the outermost match counts, so a room's
-- own spawn points are not visited one by one. Monsters are never rooms.
--
-- A room is done once reached. One that cannot be reached is left for
-- Config.DUNGEON_UNREACHABLE_SECONDS and tried again (the boss room opens
-- later).
local Core = {}

local function Normalize(Name)
    return (string.gsub(string.lower(Name), "[%s_%-]", ""))
end

local function ContainsAny(List, Normal)
    for _, Wanted in ipairs(List) do
        if string.find(Normal, Normalize(Wanted), 1, true) then
            return true
        end
    end

    return false
end

function Core.IsRoomName(Name, Cfg)
    local Normal = Normalize(Name)

    if #Cfg.DUNGEON_ROOM_NAMES > 0 then
        return ContainsAny(Cfg.DUNGEON_ROOM_NAMES, Normal)
    end

    return ContainsAny(Cfg.DUNGEON_ROOM_KEYWORDS, Normal)
end

--// The nearest room not done and not skipped, from Position ({ X, Y, Z }).
--// Rooms = { X, Y, Z, Done, Skipped }.
function Core.NextRoom(Rooms, Position)
    local Best, BestDistance = nil, math.huge

    for _, Room in ipairs(Rooms) do
        if not Room.Done and not Room.Skipped then
            local Distance = math.sqrt((Room.X - Position.X) ^ 2 + (Room.Y - Position.Y) ^ 2 + (Room.Z - Position.Z) ^ 2)

            if Distance < BestDistance then
                Best, BestDistance = Room, Distance
            end
        end
    end

    return Best
end

return {
    Name = "DungeonRooms",
    Dependencies = {"Config", "DungeonTargets"},
    Core = Core,

    Start = function(Context)
        local Config = Context.Config
        local DungeonTargets = Context.DungeonTargets

        --// The room list is read again this often (rooms can stream in).
        local REFRESH_SECONDS = 10
        --// A folder's centre is taken from at most this many of its parts.
        local MAX_CENTER_PARTS = 300

        local DungeonRooms = {
            Name = "DungeonRooms",
            Core = Core,
            S = {
                Rooms = {},
                ReadAt = -math.huge,
                Root = nil,
                Done = setmetatable({}, { __mode = "k" }),
                SkipUntil = setmetatable({}, { __mode = "k" }),
                Blocked = setmetatable({}, { __mode = "k" }),
            },
        }

        local S = DungeonRooms.S

        local function FolderCenter(Folder)
            local Sum, Count = Vector3.zero, 0

            for _, Descendant in ipairs(Folder:GetDescendants()) do
                if Descendant:IsA("BasePart") then
                    Sum += Descendant.Position
                    Count += 1

                    if Count >= MAX_CENTER_PARTS then
                        break
                    end
                end
            end

            return Count > 0 and Sum / Count or nil
        end

        local function GetCenter(Object)
            if Object:IsA("BasePart") then
                return Object.Position
            end

            if Object:IsA("Model") then
                return (Object:GetBoundingBox()).Position
            end

            if Object:IsA("Folder") then
                return FolderCenter(Object)
            end

            return nil
        end

        local function IsInside(Object, Matched, Root)
            local Node = Object.Parent

            while Node and Node ~= Root do
                if Matched[Node] then
                    return true
                end

                Node = Node.Parent
            end

            return false
        end

        local function Read(Root)
            local Rooms, Matched = {}, {}

            for _, Object in ipairs(Root:GetDescendants()) do
                local IsKind = Object:IsA("Model") or Object:IsA("Folder") or Object:IsA("BasePart")

                if IsKind and Core.IsRoomName(Object.Name, Config)
                    and not Object:FindFirstChildOfClass("Humanoid")
                    and not IsInside(Object, Matched, Root) then
                    Matched[Object] = true
                    local Center = GetCenter(Object)

                    if Center then
                        table.insert(Rooms, { Instance = Object, Name = Object.Name, Position = Center })
                    end

                    if #Rooms >= Config.DUNGEON_ROOM_MAX then
                        break
                    end
                end
            end

            return Rooms
        end

        local function Refresh()
            local Root = DungeonTargets.GetRoot()

            if Root == S.Root and os.clock() - S.ReadAt < REFRESH_SECONDS then
                return
            end

            local Count = #S.Rooms
            S.Root, S.ReadAt = Root, os.clock()
            S.Rooms = Root and Read(Root) or {}

            if #S.Rooms ~= Count then
                local Names = {}

                for _, Room in ipairs(S.Rooms) do
                    table.insert(Names, Room.Name)
                end

                print(string.format("[AutoDungeon] %d rooms to explore: %s", #S.Rooms, table.concat(Names, ", ")))
            end
        end

        --// The nearest room still to visit, or nil.
        function DungeonRooms.Next(Position)
            Refresh()

            local Now = os.clock()
            local Candidates = {}

            for _, Room in ipairs(S.Rooms) do
                if Room.Instance.Parent then
                    table.insert(Candidates, {
                        X = Room.Position.X, Y = Room.Position.Y, Z = Room.Position.Z,
                        Done = S.Done[Room.Instance] == true,
                        Skipped = (S.SkipUntil[Room.Instance] or 0) > Now,
                        Room = Room,
                    })
                end
            end

            local Next = Core.NextRoom(Candidates, { X = Position.X, Y = Position.Y, Z = Position.Z })
            return Next and Next.Room or nil
        end

        function DungeonRooms.MarkDone(Room)
            S.Done[Room.Instance] = true
            S.Blocked[Room.Instance] = nil
        end

        --// Counts a blocked leg; after DUNGEON_BLOCKED_TRIES in a row the
        --// room is left for a while.
        function DungeonRooms.NoteBlocked(Room, Why)
            local Count = (S.Blocked[Room.Instance] or 0) + 1
            S.Blocked[Room.Instance] = Count

            if Count >= Config.DUNGEON_BLOCKED_TRIES then
                S.Blocked[Room.Instance] = nil
                S.SkipUntil[Room.Instance] = os.clock() + Config.DUNGEON_UNREACHABLE_SECONDS
                print(string.format("[AutoDungeon] Cannot reach room %s (%s): skipped for %ds", Room.Name, tostring(Why), Config.DUNGEON_UNREACHABLE_SECONDS))
            end
        end

        function DungeonRooms.NoteMoved(Room)
            S.Blocked[Room.Instance] = nil
        end

        --// A new run explores every room again.
        function DungeonRooms.Reset()
            S.Done = setmetatable({}, { __mode = "k" })
            S.SkipUntil = setmetatable({}, { __mode = "k" })
            S.Blocked = setmetatable({}, { __mode = "k" })
            S.ReadAt = -math.huge
        end

        return DungeonRooms
    end,
}
