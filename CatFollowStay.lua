-- BEGIN Prissykins follow/stay
-- Appended to CatAnimal.lua by Install.ps1. The original interaction jobs still
-- own routing, animations, sound, and rewards. These commands are session-only.
do
    local herdable = Classes.HerdableScriptObjectBase
    local scriptObject = Classes.ScriptObjectBase
    local homeWorldName = "animal_01"
    local homeCatName = "cat_animal_01"
    local visitorName = "prissykins_travel_test"
    local companion
    local pendingArrival
    CatAnimal._instanceVars.prissykinsControl = NIL
    CatAnimal._instanceVars.prissykinsRunnable = true
    CatAnimal._instanceVars.prissykinsVisitor = false
    CatAnimal._instanceVars.prissykinsRegistered = false

    local function isVisitor(cat)
        return cat.collectionKey ~= nil and
            cat.collectionKey == Luattrib:ConvertStringToUserdataKey(visitorName)
    end

    local function travelBridge(...)
        return Luattrib:CollectionExists("herdables", "prissykins_native_bridge", ...)
    end

    local function traceTravel(stage)
        pcall(travelBridge, stage)
    end

    local function removeVisitorInteraction(cat, world)
        if cat.prissykinsRegistered and world and world.isValid then
            cat.prissykinsRegistered = travelBridge(cat, world, false) ~= 1
        end
    end

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
        if isVisitor(self) then
            self.prissykinsVisitor = true
            self.bHerded = true
            self.specifiedTaskToComplete = nil
        end
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
        if companion == self then companion = nil end
        if self.prissykinsRegistered then removeVisitorInteraction(self, self.containingWorld) end
        local control = self.prissykinsControl
        self.prissykinsControl = nil
        if control ~= nil then stopFollowTimer(control) end
        herdable.Destructor(self)
    end

    function CatAnimal:LoadCallback()
        if companion == self then companion = nil end
        local control = self.prissykinsControl
        self.prissykinsControl = nil
        if control ~= nil then stopFollowTimer(control) end
        herdable.LoadCallback(self)
    end

    -- While commanded, a trip across the palace trigger should not change the
    -- completed quest's herd status or cancel a follow. Keep its occupancy flag.
    local enterPalace = CatAnimal.EnterTriggerCallback
    function CatAnimal:EnterTriggerCallback(go, trigger)
        if self.prissykinsVisitor or (self.prissykinsControl ~= nil and self.prissykinsControl.mode ~= nil) then
            self.bInTriggerVolume = true
            return
        end
        enterPalace(self, go, trigger)
    end

    function CatAnimal:ExitTriggerCallback(go, trigger)
        if self.prissykinsVisitor or (self.prissykinsControl ~= nil and self.prissykinsControl.mode ~= nil) then
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
            sim.containingWorld == world and
            (cat.prissykinsVisitor and cat == companion or
                world == Universe:GetWorld(homeWorldName) and
                world:FindGameObject("herdables", homeCatName) == cat) and
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
        if mode ~= nil then companion = cat end
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
        -- Pet is a Stay command as soon as the player's interaction starts.
        -- Keep it even if the stock animation or its reward job is interrupted.
        if command and mode == "stay" then
            control.mode = mode
            companion = cat
        end
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

    local function retireVisitor(cat, world)
        if not cat or not cat.isValid or not isVisitor(cat) then return end
        removeVisitorInteraction(cat, world)
        cat:Destroy()
    end

    local function positionNear(player, world)
        local x, y, z, rotation = player:GetPositionRotation()
        local sideX, sideZ = Common:GetRelativePosition(1.25, -0.75, x, z, rotation)
        local groundY = world:GetGroundHeight(sideX, y, sideZ)
        if groundY ~= nil and math.abs(groundY - y) <= 0.75 then
            return sideX, groundY, sideZ, rotation
        end
        return x, y, z, rotation
    end

    local function followOnArrival(cat)
        companion = cat
        cat.prissykinsControl = { mode = "follow" }
        applyMode(cat, cat.prissykinsControl)
    end

    local function stopArrival(request, job)
        if pendingArrival == request then pendingArrival = nil end
        job.callbackFunction = nil
    end

    local function watchArrival(world)
        local request = pendingArrival
        if not request or request.scheduled or not world or world.collectionKey ~= request.destination then return end
        request.scheduled = true
        traceTravel("destination callback received")
        local frames = 0
        local waitingFor = "the destination player"
        local watcher = Classes.Job_PerFrameFunctionCallback:Spawn(function(job)
            frames = frames + 1
            if pendingArrival ~= request or frames > 1800 then
                traceTravel(pendingArrival ~= request and "arrival superseded" or "arrival timed out waiting for " .. waitingFor)
                retireVisitor(request.actor, world)
                stopArrival(request, job)
                return
            end
            -- The ferry can destroy the source island's player object. Only
            -- the current player in the selected destination can take over.
            local player = Universe:GetPlayerGameObject()
            if not player or not player.isValid or player.containingWorld ~= world or Universe:GetWorld() ~= world then
                waitingFor = "the destination player"
                return
            end
            if player:IsUnderScriptControl() then
                waitingFor = "player control"
                return
            end
            if not Task:IsTaskComplete("NPC_Renee_ExplainCat") then
                waitingFor = "the completed tower quest state"
                return
            end
            if world == Universe:GetWorld(homeWorldName) then
                waitingFor = "the original cat"
                local homeCat = world:FindGameObject("herdables", homeCatName)
                if homeCat == nil or not homeCat.isValid or not homeCat.prissykinsRunnable then return end
                homeCat:SetPositionRotation(positionNear(player, world))
                followOnArrival(homeCat)
                traceTravel("original cat resumed Follow at home")
                stopArrival(request, job)
            elseif request.actor and request.actor.isValid and request.actor.containingWorld == world and
                request.actor.prissykinsVisitor then
                local cat = request.actor
                if isVisitor(cat) and travelBridge(cat, world) == 1 then
                    cat.prissykinsRegistered = true
                    followOnArrival(cat)
                    traceTravel("visitor resumed Follow")
                else
                    retireVisitor(cat, world)
                end
                stopArrival(request, job)
            elseif not request.spawned then
                local ok, prepared = pcall(travelBridge)
                if not ok or prepared ~= 1 then
                    traceTravel("visitor preparation declined")
                    stopArrival(request, job)
                    return
                end
                if world:FindGameObject("herdables", visitorName) ~= nil then
                    traceTravel("existing visitor prevented a duplicate spawn")
                    stopArrival(request, job)
                    return
                end
                request.spawned = true
                waitingFor = "the visitor actor"
                local x, y, z, rotation = positionNear(player, world)
                local spawn = Classes.Job_SpawnObject:SpawnInWorld(world, "herdables", visitorName,
                    world, x, y, z, rotation, { ScriptName = "CatAnimal" })
                spawn:SetInitFunction(function(cat)
                    if pendingArrival == request then
                        request.actor = cat
                        traceTravel("visitor actor created")
                    else retireVisitor(cat, world) end
                end)
                traceTravel("visitor spawn requested")
                spawn:Execute(world)
            end
        end, "PrissykinsTravel", world)
        watcher:Execute(world)
    end

    local beginWorld = Classes.WorldBase.BeginIslandSimulationCallback
    function Classes.WorldBase:BeginIslandSimulationCallback(...)
        beginWorld(self, ...)
        watchArrival(self)
    end

    local beginCharacter = Classes.CharacterBase.BeginIslandSimulationCallback
    function Classes.CharacterBase:BeginIslandSimulationCallback(...)
        beginCharacter(self, ...)
        if pendingArrival and self == Universe:GetPlayerGameObject() then watchArrival(self.containingWorld) end
    end

    -- Mirror the stock ferry action. Only a confirmed map destination arms
    -- travel, before the original world change and teleport requests.
    function Classes.Boat_Interaction_LeaveIsland:Action(sim, npc)
        local _, destination = UI:SpawnAndBlock("UIWorldMap")
        if not destination then return end
        local player = Universe:GetPlayerGameObject()
        local source = player and player.containingWorld
        if source and source.collectionKey ~= destination[2] then
            pendingArrival = nil
            local cat = companion
            if cat and cat.isValid and cat.containingWorld == source then
                local control = cat.prissykinsControl
                if control and control.mode == "follow" and control.job == nil then
                    pendingArrival = { destination = destination[2] }
                    traceTravel("ferry handoff armed")
                    control.mode = "stay"
                    applyMode(cat, control)
                end
                if cat.prissykinsVisitor then
                    companion = nil
                    retireVisitor(cat, source)
                end
            end
            if not pendingArrival then traceTravel("ferry departed without Follow") end
        end
        Universe:RequestGameplayWorldChange(destination)
        Classes.Job_Teleport:Spawn(player, destination):Execute(self)
    end
    traceTravel("companion script loaded")
end
-- END Prissykins follow/stay
