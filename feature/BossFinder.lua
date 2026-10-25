-- BossFinder looks in workspace for a living model named like one of the
-- selected bosses.
return {
    Name = "BossFinder",
    Dependencies = {"Config"},

    Start = function(Context)
        local Config = Context.Config

        local BossFinder = { Name = "BossFinder" }

        --// Without a Humanoid a model counts as alive while it is in
        --// workspace, unless Config.BOSS_REQUIRE_HUMANOID.
        function BossFinder.IsAlive(Model)
            if not Model or not Model:IsDescendantOf(workspace) then
                return false
            end

            local Humanoid = Model:FindFirstChildOfClass("Humanoid")

            if not Humanoid then
                return not Config.BOSS_REQUIRE_HUMANOID
            end

            return Humanoid.Health > 0
        end

        --// The first living model whose Name is a key of Wanted (name -> true),
        --// or nil.
        function BossFinder.Find(Wanted)
            local Root = Config.GetBossRoot()

            if not Root then
                return nil
            end

            for _, Descendant in ipairs(Root:GetDescendants()) do
                if Descendant:IsA("Model") and Wanted[Descendant.Name] and BossFinder.IsAlive(Descendant) then
                    return Descendant
                end
            end

            return nil
        end

        return BossFinder
    end,
}
