-- AutoHunt bootstrap.
-- Every feature returns {Name, Dependencies, Start(Context)}, the same shape
-- Automated-Industry-Complex uses.

--// Bump on every push: shown on load and in the window title, so an old
--// copy (cache, local files) is easy to spot.
local VERSION = "0.5.0"
local TITLE = "AUTO HUNT v" .. VERSION

--// Where features are read from: GitHub by default. Set
--// getgenv().AutoHuntLocal = true before running to read LOCAL_ROOT, inside
--// the executor's workspace folder, instead.
local LOCAL_ROOT = "autoHunt/"
local REPO = "kaikakkaikak/hunt"
local BRANCH = "master"
--// raw.githubusercontent caches a branch URL for ~5 minutes and ignores
--// query strings, so files are read from the latest commit's URL instead,
--// found through this API. The branch URL is the fallback when it fails
--// (e.g. the API's 60 requests an hour limit).
local COMMIT_API = "https://api.github.com/repos/" .. REPO .. "/commits/" .. BRANCH
local BASE = "https://raw.githubusercontent.com/" .. REPO .. "/refs/heads/" .. BRANCH .. "/"

--// A failed download is retried this many times before giving up.
local FETCH_RETRIES = 2

--// Every feature, in start order (dependencies still start first).
local MODULES = {
    "feature/Config.lua",
    "feature/Settings.lua",
    "feature/GuiClick.lua",
    "feature/ServerHop.lua",
    "feature/BossFinder.lua",
    "feature/BossTimer.lua",
    "feature/ZoneWalk.lua",
    "feature/GameAuto.lua",
    "feature/AutoHunt.lua",
    "feature/UI.lua",
}

--// Run again from queue_on_teleport right after a hop: wait for the game.
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Services = {
    Players = game:GetService("Players"),
    HttpService = game:GetService("HttpService"),
    StarterGui = game:GetService("StarterGui"),
}

local Context = {
    Services = Services,
    Player = Services.Players.LocalPlayer,
    Modules = {},
}

--// Re-execution guard: running the script again stops the previous run
--// (kept in getgenv().AutoHuntSession) before this one loads.
local Lifetime = { Alive = true, Connections = {}, Cleanups = {}, Env = nil }

function Lifetime.Connect(Signal, Callback)
    local Connection = Signal:Connect(Callback)

    if Lifetime.Alive then
        table.insert(Lifetime.Connections, Connection)
    else
        Connection:Disconnect()
    end

    return Connection
end

function Lifetime.OnEnd(Callback)
    table.insert(Lifetime.Cleanups, Callback)
end

function Lifetime.Destroy()
    if not Lifetime.Alive then
        return
    end

    Lifetime.Alive = false

    for Index = #Lifetime.Cleanups, 1, -1 do
        local Ok, Error = pcall(Lifetime.Cleanups[Index])

        if not Ok then
            warn("[AutoHunt] Cleanup failed:", Error)
        end
    end

    for _, Connection in ipairs(Lifetime.Connections) do
        pcall(function()
            Connection:Disconnect()
        end)
    end

    table.clear(Lifetime.Cleanups)
    table.clear(Lifetime.Connections)

    if Lifetime.Env and Lifetime.Env.AutoHuntSession == Lifetime then
        Lifetime.Env.AutoHuntSession = nil
    end
end

Context.Lifetime = Lifetime
Context.Connect = Lifetime.Connect

do
    local Ok, Env = pcall(function()
        return type(getgenv) == "function" and getgenv() or nil
    end)

    Lifetime.Env = Ok and type(Env) == "table" and Env or nil
end

if Lifetime.Env then
    local Previous = Lifetime.Env.AutoHuntSession

    if type(Previous) == "table" and type(Previous.Destroy) == "function" then
        print("[AutoHunt] Stopping the previous run")
        pcall(Previous.Destroy)
    end

    Lifetime.Env.AutoHuntSession = Lifetime
end

function Context.NotifyAction(Title, Message, Duration)
    pcall(function()
        Services.StarterGui:SetCore("SendNotification", {
            Title = Title,
            Text = Message,
            Duration = Duration or 4,
        })
    end)
end

------------------------------------------------------------------------
--// Loading
------------------------------------------------------------------------

local USE_LOCAL = Lifetime.Env ~= nil and Lifetime.Env.AutoHuntLocal == true

local function readLocal(Path)
    if not USE_LOCAL or type(readfile) ~= "function" or type(isfile) ~= "function" then
        return nil
    end

    local Ok, Body = pcall(function()
        return isfile(LOCAL_ROOT .. Path) and readfile(LOCAL_ROOT .. Path) or nil
    end)

    return Ok and Body or nil
end

--// The raw URL of the branch's latest commit, or nil.
local function resolveCommitBase()
    local Ok, Body = pcall(function()
        return game:HttpGet(COMMIT_API, true)
    end)

    if not Ok or type(Body) ~= "string" then
        return nil
    end

    local Decoded, Commit = pcall(function()
        return Services.HttpService:JSONDecode(Body)
    end)

    local Sha = Decoded and type(Commit) == "table" and Commit.sha

    if type(Sha) ~= "string" or not string.match(Sha, "^%x+$") then
        return nil
    end

    return "https://raw.githubusercontent.com/" .. REPO .. "/" .. Sha .. "/", Sha
end

if not USE_LOCAL then
    local CommitBase, Sha = resolveCommitBase()

    if CommitBase then
        BASE = CommitBase
        print("[AutoHunt] Using commit " .. string.sub(Sha, 1, 7))
    else
        warn("[AutoHunt] Could not read the latest commit; the branch may be up to 5 minutes old")
    end
end

local function fetchRemote(Path)
    if BASE == "" then
        return nil
    end

    local Url = BASE .. Path

    for _ = 0, FETCH_RETRIES do
        local Ok, Body = pcall(function()
            return game:HttpGet(Url, true)
        end)

        if Ok and type(Body) == "string" and Body ~= "" and not string.find(Body, "^404: Not Found") then
            return Body
        end
    end

    return nil
end

--// Shown on screen too: a load error otherwise only reaches the console.
local function fail(Message)
    Context.NotifyAction(TITLE .. " LOAD FAILED", string.match(Message, "^[^\n]*"), 15)
    error("[AutoHunt] " .. Message, 0)
end

local function loadSpec(Path)
    local Body = readLocal(Path) or fetchRemote(Path)

    if not Body then
        fail("Could not load " .. Path)
    end

    local Chunk, CompileError = loadstring(Body, "@" .. Path)

    if not Chunk then
        fail("Failed to compile " .. Path .. ": " .. tostring(CompileError))
    end

    local Spec = Chunk()

    if type(Spec) ~= "table" or type(Spec.Start) ~= "function" then
        fail("Invalid module: " .. Path)
    end

    return Spec
end

--// How AutoHunt runs this script again on the next server: the way it was
--// loaded this time.
if readLocal("init.lua") then
    Context.ReloadSource = string.format("getgenv().AutoHuntLocal = true\nloadstring(readfile(%q))()", LOCAL_ROOT .. "init.lua")
elseif BASE ~= "" then
    Context.ReloadSource = string.format("loadstring(game:HttpGet(%q))()", BASE .. "init.lua")
end

print("[AutoHunt] Loading " .. TITLE .. (readLocal("init.lua") and " from local files" or " from GitHub"))
Context.Title = TITLE

local Specs = {}
local StartOrder = {}

for _, Path in ipairs(MODULES) do
    local Spec = loadSpec(Path)
    Specs[Spec.Name] = Spec
    table.insert(StartOrder, Spec.Name)
end

local Started = {}

local function start(Name)
    if Started[Name] then
        return Context.Modules[Name]
    end

    local Spec = assert(Specs[Name], "Missing dependency: " .. tostring(Name))

    for _, Dependency in ipairs(Spec.Dependencies or {}) do
        start(Dependency)
    end

    local Ok, Module = xpcall(Spec.Start, debug.traceback, Context)

    if not Ok then
        fail(Name .. " failed to start: " .. tostring(Module))
    end

    Context.Modules[Name] = Module
    Context[Name] = Module
    Started[Name] = true
    return Module
end

for _, Name in ipairs(StartOrder) do
    start(Name)
end

if not Lifetime.Alive then
    return nil
end

--// getgenv().AutoHunt.ServerHop:Hop() etc. from the console.
if Lifetime.Env then
    Lifetime.Env.AutoHunt = Context
    Lifetime.OnEnd(function()
        if Lifetime.Env.AutoHunt == Context then
            Lifetime.Env.AutoHunt = nil
        end
    end)
end

Context.NotifyAction(TITLE, "Loaded", 3)
return Context
