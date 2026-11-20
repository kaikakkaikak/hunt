-- DungeonRooms lists the dungeon's rooms, so AutoDungeon can fly into each
-- one: monsters only spawn once someone gets there.
--
-- A room is anything in workspace[Config.DUNGEON_ROOT_NAME] (a Model,
-- Folder or part) whose name contains one of Config.DUNGEON_ROOM_NAMES or,
-- when that list is empty, one of Config.DUNGEON_ROOM_KEYWORDS ("Room3",
-- "MobSpawn", "WaveTrigger"). Only the outermost match counts, so a room's
-- own spawn points are not visited one by one. Monsters are never rooms.
--
-- A room is done once we come within Config.DUNGEON_ROOM_ARRIVE of it (X and
-- Z only), flying there or passing by while fighting, and never visited
-- again. Rooms are remembered by name and place, so one that streams out
-- and back in (a new instance) still counts as done. One that cannot be
-- reached is left for Config.DUNGEON_UNREACHABLE_SECONDS and tried again
-- (the boss room opens later), up to Config.DUNGEON_ROOM_GIVE_UP_SKIPS
-- times; then it is dropped.
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

--// The same room whatever instance holds it: its name and place (4 studs).
function Core.RoomKey(Name, X, Z)
    return string.format("%s@%d,%d", Name, math.floor(X / 4 + 0.5), math.floor(Z / 4 + 0.5))
end

--// The room to fly to from Position ({ X, Y, Z }): the one already being
--// flown to (CurrentKey) until it is done or skipped, else the nearest
--// one not done and not skipped. Rooms = { Key, X, Y, Z, Done, Skipped }.
--// Keeping the room stops us turning back at a corner when another room
--// looks nearer in a straight line through the walls.
function Core.NextRoom(Rooms, Position, CurrentKey)
    local Best, BestDistance = nil, math.huge

    for _, Room in ipairs(Rooms) do
        if CurrentKey ~= nil and Room.Key == CurrentKey and not Room.Done and not Room.Skipped then
            return Room
        end
    end

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
                --// RoomKey -> true / os.clock() / blocked count.
                Done = {},
                SkipUntil = {},
                Blocked = {},
                --// The room being flown to.
                CurrentKey = nil,
                --// RoomKey -> times it was skipped.
                Skips = {},
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
                        table.insert(Rooms, {
                            Instance = Object, Name = Object.Name, Position = Center,
                            Key = Core.RoomKey(Object.Name, Center.X, Center.Z),
                        })
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

            if #S.Rooms ~= Count or not S.Logged then
                S.Logged = true
                local Names = {}

                for _, Room in ipairs(S.Rooms) do
                    table.insert(Names, Room.Name)
                end

                print(string.format("[AutoDungeon] %d rooms to explore: %s", #S.Rooms, #Names > 0 and table.concat(Names, ", ")
                    or "none (nothing in " .. Config.DUNGEON_ROOT_NAME .. " is named like a room: see DUNGEON_ROOM_NAMES)"))
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
                        Key = Room.Key,
                        X = Room.Position.X, Y = Room.Position.Y, Z = Room.Position.Z,
                        Done = S.Done[Room.Key] == true,
                        Skipped = (S.SkipUntil[Room.Key] or 0) > Now,
                        Room = Room,
                    })
                end
            end

            local Next = Core.NextRoom(Candidates, { X = Position.X, Y = Position.Y, Z = Position.Z }, S.CurrentKey)

            if Next and Next.Key ~= S.CurrentKey then
                print("[AutoDungeon] Exploring room " .. Next.Room.Name)
            end

            S.CurrentKey = Next and Next.Key or nil
            return Next and Next.Room or nil
        end

        function DungeonRooms.MarkDone(Room)
            if not S.Done[Room.Key] then
                print("[AutoDungeon] Room done: " .. Room.Name)
            end

            S.Done[Room.Key] = true
            S.Blocked[Room.Key] = nil
        end

        --// Every room we are at now counts as done.
        function DungeonRooms.MarkNearby(Position)
            for _, Room in ipairs(S.Rooms) do
                local DX, DZ = Room.Position.X - Position.X, Room.Position.Z - Position.Z

                if DX * DX + DZ * DZ <= Config.DUNGEON_ROOM_ARRIVE ^ 2 then
                    DungeonRooms.MarkDone(Room)
                end
            end
        end

        --// Counts a blocked leg; after DUNGEON_BLOCKED_TRIES in a row the
        --// room is left for a while.
        function DungeonRooms.NoteBlocked(Room, Why)
            local Count = (S.Blocked[Room.Key] or 0) + 1
            S.Blocked[Room.Key] = Count

            if Count < Config.DUNGEON_BLOCKED_TRIES then
                return
            end

            S.Blocked[Room.Key] = nil
            S.Skips[Room.Key] = (S.Skips[Room.Key] or 0) + 1

            --// Not reached after this many tries: dropped for good, so
            --// the bot does not keep coming back to it.
            if S.Skips[Room.Key] >= Config.DUNGEON_ROOM_GIVE_UP_SKIPS then
                S.Done[Room.Key] = true
                print(string.format("[AutoDungeon] Giving up on room %s (%s)", Room.Name, tostring(Why)))
                return
            end

            S.SkipUntil[Room.Key] = os.clock() + Config.DUNGEON_UNREACHABLE_SECONDS
            print(string.format("[AutoDungeon] Cannot reach room %s (%s): skipped for %ds", Room.Name, tostring(Why), Config.DUNGEON_UNREACHABLE_SECONDS))
        end

        --// Where to fly for Room: its centre, or after blocked tries a spot
        --// round it, still close enough to count as there.
        function DungeonRooms.AimPoint(Room)
            local Tries = S.Blocked[Room.Key] or 0

            if Tries == 0 then
                return Room.Position
            end

            local X, Z = DungeonTargets.Core.TurnEighths(1, 0, Tries)
            return Room.Position + Vector3.new(X, 0, Z) * Config.DUNGEON_ROOM_ARRIVE * 0.7
        end

        function DungeonRooms.NoteMoved(Room)
            S.Blocked[Room.Key] = nil
        end

        --// A new run explores every room again.
        function DungeonRooms.Reset()
            S.Done, S.SkipUntil, S.Blocked, S.Skips = {}, {}, {}, {}
            S.CurrentKey = nil
            S.ReadAt = -math.huge
        end

        return DungeonRooms
    end,
}
