-- Console keeps the recent output (print / warn / errors) for the UI's
-- console panel: on a phone F9 cannot be opened. Lines come from
-- LogService: its history at load, then every new message.
--// Pure helpers, tested in tests/run.luau.
local Core = {}

--// Lines of ours carry this tag.
Core.TAG = "[AutoHunt]"

--// Lines (oldest first) with Line added at the end, keeping the newest
--// Max, as a new list.
function Core.Push(Lines, Line, Max)
    local First = math.max(1, #Lines + 2 - Max)
    local Kept = table.move(Lines, First, #Lines, 1, {})
    table.insert(Kept, Line)
    return Kept
end

--// Ours (tagged), and every warning and error: an error from our code may
--// not carry the tag. All when OnlyOurs is false.
function Core.IsShown(Line, OnlyOurs)
    if not OnlyOurs or Line.Kind ~= "info" then
        return true
    end

    return string.find(Line.Text, Core.TAG, 1, true) ~= nil
end

--// Text safe inside a RichText label.
function Core.Escape(Text)
    return (string.gsub(Text, "[<>&\"']", {
        ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;", ['"'] = "&quot;", ["'"] = "&apos;",
    }))
end

return {
    Name = "Console",
    Dependencies = {},
    Core = Core,

    Start = function(Context)
        local LogService = game:GetService("LogService")
        local Lifetime = Context.Lifetime

        local MAX_LINES = 300

        local KIND = {
            [Enum.MessageType.MessageOutput] = "info",
            [Enum.MessageType.MessageInfo] = "info",
            [Enum.MessageType.MessageWarning] = "warn",
            [Enum.MessageType.MessageError] = "error",
        }

        local Console = {
            Name = "Console",
            Core = Core,
            S = {
                --// { Text, Kind, Time } oldest first.
                Lines = {},
                --// Goes up on every change, so the UI redraws only then.
                Version = 0,
            },
        }

        local S = Console.S

        local function Add(Text, MessageType, Time)
            local Line = { Text = tostring(Text), Kind = KIND[MessageType] or "info", Time = Time or os.time() }
            S.Lines = Core.Push(S.Lines, Line, MAX_LINES)
            S.Version += 1
        end

        --// The shown lines, oldest first.
        function Console:GetLines(OnlyOurs)
            local Shown = {}

            for _, Line in ipairs(S.Lines) do
                if Core.IsShown(Line, OnlyOurs) then
                    table.insert(Shown, Line)
                end
            end

            return Shown
        end

        function Console:GetVersion()
            return S.Version
        end

        function Console:Clear()
            S.Lines = {}
            S.Version += 1
        end

        --// The shown lines as plain text, for the clipboard.
        function Console:PlainText(OnlyOurs)
            local Out = {}

            for _, Line in ipairs(Console:GetLines(OnlyOurs)) do
                table.insert(Out, os.date("%H:%M:%S", Line.Time) .. "  " .. Line.Text)
            end

            return table.concat(Out, "\n")
        end

        local Ok, History = pcall(function()
            return LogService:GetLogHistory()
        end)

        if Ok and type(History) == "table" then
            for _, Entry in ipairs(History) do
                Add(Entry.message, Entry.messageType, Entry.timestamp)
            end
        end

        Lifetime.Connect(LogService.MessageOut, function(Message, MessageType)
            Add(Message, MessageType)
        end)

        return Console
    end,
}
