-- BEGIN Prissykins follow/stay
-- Appended to CatAnimal.lua by Install.ps1. The original interaction jobs still
-- own routing, animations, sound, and rewards. These commands are session-only.
do
    local herdable = Classes.HerdableScriptObjectBase
    local scriptObject = Classes.ScriptObjectBase
    CatAnimal._instanceVars.prissykinsControl = NIL
    CatAnimal._instanceVars.prissykinsRunnable = true

    local function cancelTimer(timer)
        if timer ~= nil and timer.isValid then timer:Kill() end
    end

    local function stopFollowTimer(control)
        local timer = control.timer
        control.timer = nil
        cancelTimer(timer)
    end

    local function startIdle(cat)
        if cat.state == cat.states.idle and cat.animJob ~= nil and cat.animJob.isValid then return end
        cat.state = cat.states.idle
        cat:StartIdles()
    end

    local function updateFollow(cat, control)
        if not cat.prissykinsRunnable or control.job ~= nil or control.mode ~= "follow" then return end
        local player = Universe:GetPlayerGameObject()
        if player == nil or not player.isValid or player.containingWorld ~= cat.containingWorld then
            cat:StopSteering()
            startIdle(cat)
            control.mode = "stay"
            return
        end

        local distance = cat:GetXZDist(player)
        if cat.state == cat.states.fleeing then
            if distance <= 1.6 then
                cat:StopSteering()
                startIdle(cat)
            end
        elseif distance >= 2.8 then
            if cat.animJob ~= nil and cat.animJob.isValid then
                cat.animJob:Signal(BlockingResult.Canceled, 0)
            end
            cat.animJob = nil
            cat:SetTarget(player)
            cat:StartReverseSteering()
            cat.state = cat.states.fleeing
        end
        control.timer = cat:CreateTimer(Clock.Game, 0, 0, 0, 0.25)
    end

    local function applyMode(cat, control)
        stopFollowTimer(control)
        if not cat.prissykinsRunnable or not cat.isValid then return end
        cat:TurnOffAwareness()
        cat:StopSteering()
        local timer = cat.behaviorAlarm
        cat.behaviorAlarm = nil
        cancelTimer(timer)
        startIdle(cat)
        updateFollow(cat, control)
    end

    function CatAnimal:RunnableCallback()
        self.prissykinsRunnable = true
        herdable.RunnableCallback(self)
        local control = self.prissykinsControl
        if control ~= nil and control.mode ~= nil and control.job == nil then applyMode(self, control) end
    end

    function CatAnimal:NotRunnableCallback()
        self.prissykinsRunnable = false
        local control = self.prissykinsControl
        if control ~= nil then stopFollowTimer(control) end
        scriptObject.NotRunnableCallback(self)
    end

    function CatAnimal:Destructor()
        local control = self.prissykinsControl
        self.prissykinsControl = nil
        if control ~= nil then stopFollowTimer(control) end
        herdable.Destructor(self)
    end

    function CatAnimal:LoadCallback()
        local control = self.prissykinsControl
        self.prissykinsControl = nil
        if control ~= nil then stopFollowTimer(control) end
        herdable.LoadCallback(self)
    end

    -- While commanded, a trip across the palace trigger should not change the
    -- completed quest's herd status or cancel a follow. Keep its occupancy flag.
    local enterPalace = CatAnimal.EnterTriggerCallback
    function CatAnimal:EnterTriggerCallback(go, trigger)
        if self.prissykinsControl ~= nil and self.prissykinsControl.mode ~= nil then
            self.bInTriggerVolume = true
            return
        end
        enterPalace(self, go, trigger)
    end

    function CatAnimal:ExitTriggerCallback(go, trigger)
        if self.prissykinsControl ~= nil and self.prissykinsControl.mode ~= nil then
            self.bInTriggerVolume = false
            return
        end
        herdable.ExitTriggerCallback(self, go, trigger)
    end

    function CatAnimal:TimerExpiredCallback(timer)
        local control = self.prissykinsControl
        if control ~= nil and timer ~= nil then
            if timer == control.timer then
                control.timer = nil
                updateFollow(self, control)
                return
            end
            if timer == self.behaviorAlarm then return end
        end
        herdable.TimerExpiredCallback(self, timer)
    end

    function CatAnimal:SteeringTargetNearbyCallback()
        if self.prissykinsControl == nil then herdable.SteeringTargetNearbyCallback(self) end
    end

    function CatAnimal:SteeringTargetNotNearbyCallback()
        if self.prissykinsControl == nil then herdable.SteeringTargetNotNearbyCallback(self) end
    end

    local function canCommand(sim, cat)
        local world = cat.containingWorld
        return sim ~= nil and sim == Universe:GetPlayerGameObject() and world ~= nil and
            sim.containingWorld == world and world == Universe:GetWorld("animal_01") and
            world:FindGameObject("herdables", "cat_animal_01") == cat and
            Task:IsTaskComplete("NPC_Renee_ExplainCat")
    end

    local function finish(job, mode)
        local cat = job.prissykinsCat
        job.prissykinsCat = nil
        if cat == nil or not cat.isValid then return end
        local control = cat.prissykinsControl
        if control == nil or control.job ~= job then return end
        control.job = nil
        control.mode = mode or control.mode
        if control.mode == nil then
            cat.prissykinsControl = nil
        else
            applyMode(cat, control)
        end
    end

    local function run(job, sim, cat, stock, mode)
        local command = canCommand(sim, cat)
        local control = cat.prissykinsControl
        if control == nil and not command then return stock.Action(job, sim, cat) end
        if control == nil then
            control = {}
            cat.prissykinsControl = control
        elseif control.job ~= nil then
            return BlockingResult.Failed
        end
        control.job = job
        job.prissykinsCat = cat
        stopFollowTimer(control)
        if control.mode ~= nil then cat.state = cat.states.idle end

        local result, reason = stock.Action(job, sim, cat)
        finish(job, command and result == BlockingResult.Succeeded and mode or nil)
        return result, reason
    end

    local function addCommand(name, mode)
        local stock = Classes["HerdableScriptObjectBase_Interaction_" .. name]
        local className = "Prissykins_Interaction_" .. name
        local interaction = stock:Inherit(className)
        interaction._instanceVars = { prissykinsCat = NIL }
        function interaction:Action(sim, cat)
            return run(self, sim, cat, stock, mode)
        end
        function interaction:Destructor()
            finish(self)
            stock.Destructor(self)
        end
        local entry = System:CopyShallow(CatAnimal.interactionSet[name])
        entry.interactionClassName = className
        CatAnimal.interactionSet[name] = entry
    end

    addCommand("Feed", "follow")
    addCommand("Pet", "stay")
end
-- END Prissykins follow/stay
