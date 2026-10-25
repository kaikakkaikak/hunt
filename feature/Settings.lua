-- Settings keeps what the player chose (selected bosses, running, hop after
-- kill) across hops: saved to a file with writefile, and handed to the next
-- server through getgenv().AutoHuntResume by AutoHunt's queued reload, for
-- executors without file access.
return {
    Name = "Settings",
    Dependencies = {},

    Start = function(Context)
        local HttpService = Context.Services.HttpService

        local FILE = "autoHunt/settings.json"

        local Settings = {
            Name = "Settings",
            Data = {
                --// Boss name -> true.
                Selected = {},
                Running = false,
                HopAfterKill = true,
            },
        }

        local Data = Settings.Data

        local function Apply(Saved)
            if type(Saved) ~= "table" then
                return
            end

            if type(Saved.Selected) == "table" then
                for Name, IsSelected in pairs(Saved.Selected) do
                    if type(Name) == "string" and IsSelected == true then
                        Data.Selected[Name] = true
                    end
                end
            end

            if type(Saved.Running) == "boolean" then
                Data.Running = Saved.Running
            end

            if type(Saved.HopAfterKill) == "boolean" then
                Data.HopAfterKill = Saved.HopAfterKill
            end
        end

        local function Decode(Text)
            local Ok, Value = pcall(function()
                return HttpService:JSONDecode(Text)
            end)

            return Ok and Value or nil
        end

        function Settings:Encode()
            return HttpService:JSONEncode(Data)
        end

        function Settings:Save()
            if type(writefile) ~= "function" then
                return
            end

            local Ok, Error = pcall(function()
                if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("autoHunt") then
                    makefolder("autoHunt")
                end

                writefile(FILE, Settings:Encode())
            end)

            if not Ok then
                warn("[AutoHunt] Could not save settings:", Error)
            end
        end

        local function ReadFile()
            if type(readfile) ~= "function" or type(isfile) ~= "function" then
                return nil
            end

            local Ok, Text = pcall(function()
                return isfile(FILE) and readfile(FILE) or nil
            end)

            return Ok and Text or nil
        end

        --// The file wins when there is one: it also has a Stop pressed after
        --// the reload was queued. AutoHuntResume is for executors without it.
        function Settings:Load()
            local Env = Context.Lifetime.Env
            local Resume = Env and Env.AutoHuntResume

            if Env then
                Env.AutoHuntResume = nil
            end

            local Text = ReadFile()

            if Text then
                Apply(Decode(Text))
            elseif type(Resume) == "string" then
                Apply(Decode(Resume))
            end
        end

        function Settings:SelectedNames()
            local Names = {}

            for Name in pairs(Data.Selected) do
                table.insert(Names, Name)
            end

            table.sort(Names)
            return Names
        end

        Settings:Load()
        return Settings
    end,
}
