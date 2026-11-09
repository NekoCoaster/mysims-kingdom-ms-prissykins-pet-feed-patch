-- Lua 5.1 test using the shipped CatAnimal class with mocked engine services.
-- Run with a CatAnimal.lua that includes CatFollowStay.lua as the first argument.
local function check(condition, message)
    if not condition then error(message, 2) end
end

Classes = {}
local function inherit(base, name)
    local class = setmetatable({}, {__index = base})
    Classes[name] = class
    return class
end
Classes.ScriptObjectBase = {NotRunnableCallback = function() end, Inherit = inherit}
local herdable = inherit(Classes.ScriptObjectBase, "HerdableScriptObjectBase")
herdable.states = {idle = 0, walking = 1, fleeing = 2}
herdable.RunnableCallback = function(cat) cat:StartIdles() end
herdable.Destructor = function() end
herdable.LoadCallback = function(cat) cat.loaded = true end
herdable.TimerExpiredCallback = function(cat) cat.stockTimers = cat.stockTimers + 1 end
herdable.SteeringTargetNearbyCallback = function(cat) cat.stockAwareness = cat.stockAwareness + 1 end
herdable.SteeringTargetNotNearbyCallback = herdable.SteeringTargetNearbyCallback
herdable.EnterTriggerCallback = function(cat) cat.bHerded = true end
herdable.ExitTriggerCallback = function(cat) cat.bHerded = false end
herdable.interactionSet = {}

BlockingResult = {Succeeded = 1, Failed = 2, Canceled = 3}
Clock = {Game = 1}
System = {CopyShallow = function(_, input)
    local result = {}
    for k, v in pairs(input) do result[k] = v end
    return result
end}
local function newJob()
    return {isValid = true, Signal = function(self) self.isValid = false end}
end

for _, name in ipairs({"Pet", "Feed"}) do
    local className = "HerdableScriptObjectBase_Interaction_" .. name
    local stock = inherit({Inherit = inherit}, className)
    herdable.interactionSet[name] = {interactionClassName = className}
    function stock:Action(_, cat)
        cat.stockActions = cat.stockActions + 1
        cat:StopSteering()
        if self.suspend then coroutine.yield() end
        cat:StartIdles()
        return self.result or BlockingResult.Succeeded, 99
    end
    function stock:Destructor() end
end

local world = {isValid = true, collectionKey = "animal_01"}
local currentWorld = world
local player = {isValid = true, containingWorld = world}
Universe = {
    GetPlayerGameObject = function() return player end,
    GetWorld = function(_, name) if name == "animal_01" then return world end return currentWorld end,
}
Luattrib = {ConvertStringToUserdataKey = function(_, key) return key end}
Classes.WorldBase = {BeginIslandSimulationCallback = function() end}
Classes.CharacterBase = {BeginIslandSimulationCallback = function() end}
Classes.Boat_Interaction_LeaveIsland = {}
local questComplete = false
Task = {IsTaskComplete = function(_, task)
    check(task == "NPC_Renee_ExplainCat", "Wrong quest gate")
    return questComplete
end}

assert(loadfile(arg[1]))()
local class = Classes.CatAnimal
check(herdable.interactionSet.Pet.interactionClassName == "HerdableScriptObjectBase_Interaction_Pet", "Changed stock animal interaction")
check(herdable.interactionSet.Feed.interactionClassName == "HerdableScriptObjectBase_Interaction_Feed", "Changed stock animal interaction")

local function newCat()
    local cat = setmetatable({isValid = true, containingWorld = world, state = herdable.states.idle,
        prissykinsRunnable = true, distance = 1, stockActions = 0, stockTimers = 0, stockAwareness = 0,
        bHerded = true, starts = 0, stops = 0}, {__index = class})
    function cat:StartIdles() if self.state == self.states.idle then self.animJob = newJob() end end
    function cat:StopSteering() self.stops = self.stops + 1; self.moving = false end
    function cat:StartReverseSteering() self.starts = self.starts + 1; self.moving = true end
    function cat:TurnOffAwareness() self.aware = false end
    function cat:SetTarget(target) self.steeringTarget = target end
    function cat:GetXZDist(target) check(target == player, "Wrong target"); return self.distance end
    function cat:CreateTimer(clock, d, h, m, s)
        check(clock == Clock.Game and d == 0 and h == 0 and m == 0 and s == 0.25, "Unexpected timer")
        local timer = {isValid = true, Kill = function(t) t.isValid = false end}
        self.lastTimer = timer
        return timer
    end
    return cat
end

local cat = newCat()
function world:FindGameObject(kind, name)
    check(kind == "herdables" and name == "cat_animal_01", "Wrong collection filter")
    return cat
end

local function action(name, target, actor, args)
    local job = setmetatable(args or {}, {__index = Classes[class.interactionSet[name].interactionClassName]})
    local result, reason = job:Action(actor, target)
    check(reason == 99, "Lost the stock result/reason")
    job:Destructor()
    return result
end

action("Feed", cat, player)
check(cat.prissykinsControl == nil, "Pre-quest feed changed behavior")
questComplete = true
local other = newCat()
action("Feed", other, player)
action("Feed", cat, {isValid = true, containingWorld = world})
action("Feed", cat, player, {result = BlockingResult.Failed})
check(other.prissykinsControl == nil and cat.prissykinsControl == nil, "Out-of-scope or failed command applied")

action("Feed", cat, player)
check(cat.prissykinsControl.mode == "follow" and cat.starts == 0 and cat.aware == false, "Feed did not arm follow")
local function tick(distance)
    cat.distance = distance
    local timer = cat.lastTimer
    check(timer.isValid, "No live follow timer")
    timer.isValid = false
    cat:TimerExpiredCallback(timer)
end

tick(5)
check(cat.starts == 1 and cat.moving and cat.steeringTarget == player, "Cat did not follow")
tick(60)
check(cat.starts == 1 and cat.moving, "Distance unexpectedly ended follow")
tick(1.4)
check(not cat.moving and cat.state == cat.states.idle, "Cat did not wait near the player")
tick(3)
check(cat.starts == 2 and cat.moving, "Cat did not resume follow")

local job = setmetatable({suspend = true}, {__index = Classes.Prissykins_Interaction_Pet})
local paused = coroutine.create(function() job:Action(player, cat) end)
local timer = cat.lastTimer
check(coroutine.resume(paused) and coroutine.status(paused) == "suspended" and not timer.isValid, "Pet did not pause follow while playing")
job:Destructor()
check(cat.prissykinsControl.mode == "stay" and not cat.lastTimer.isValid, "Interrupted Pet reversed Stay")

action("Feed", cat, player)
action("Pet", cat, player, {result = BlockingResult.Failed})
check(cat.prissykinsControl.mode == "stay" and not cat.moving and not cat.lastTimer.isValid, "Pet did not set stay")
cat:SteeringTargetNearbyCallback()
cat:SteeringTargetNotNearbyCallback()
cat:ExitTriggerCallback()
check(cat.stockAwareness == 0 and cat.bHerded, "Stay allowed stock movement or changed the quest flag")
action("Feed", cat, player)
local stoppedTimer = cat.lastTimer
cat:NotRunnableCallback()
check(not stoppedTimer.isValid, "Unload did not cancel the timer")
cat:RunnableCallback()
check(cat.lastTimer ~= stoppedTimer and cat.lastTimer.isValid, "Same-world reactivation failed to resume follow")
player.containingWorld = {}
tick(8)
check(cat.prissykinsControl.mode == "stay" and not cat.moving and not cat.lastTimer.isValid, "Follow attempted to cross worlds")
cat:LoadCallback()
check(cat.prissykinsControl == nil and cat.loaded, "Save reload did not restore stock control")
print("PASS: quest and identity gates, stock interactions, follow and catch-up, cancellation, stay, reload and world boundary.")

local visitorName = "prissykins_travel_test"
local away = {isValid = true, collectionKey = "capital_01"}
local third = {isValid = true, collectionKey = "cutesburgh_01"}
local destination, requested, watcher, visitor
local prepared, registered, removed, spawned = 0, 0, 0, 0
local allowSpawn = true
UI = {SpawnAndBlock = function() return 0, destination end}
Universe.RequestGameplayWorldChange = function(_, ref) requested = ref end
Classes.Job_Teleport = {Spawn = function(_, actor, ref)
    check(actor == player and ref == destination, "Changed stock teleport")
    return {Execute = function() end}
end}
function player:GetPositionRotation() return 5, 2, 8, 0 end
function player:IsUnderScriptControl() return self.inCutscene end
Common = {GetRelativePosition = function(_, dx, dz, x, z) return x + dx, z + dz end}
for _, island in ipairs({world, away, third}) do
    function island:GetGroundHeight() return 2 end
end
for _, island in ipairs({away, third}) do
    function island:FindGameObject(_, name)
        check(name == visitorName, "Looked up the original cat on a different island")
        return visitor and visitor.isValid and visitor.containingWorld == self and visitor or nil
    end
end
function cat:SetPositionRotation(x, y, z)
    self.arrivalPosition = {x, y, z}
end
package = nil -- Retail omits the Lua package library.
function Luattrib:CollectionExists(kind, key, actor, island, remove)
    check(kind == "herdables" and key == "prissykins_native_bridge", "Wrong native bridge")
    if type(actor) == "string" then return 1 end
    if actor == nil then
        prepared = prepared + 1
        return allowSpawn and 1 or nil
    end
    check(actor == visitor and island == actor.containingWorld and island ~= world, "Wrong native registration target")
    if remove == false then removed = removed + 1 else registered = registered + 1 end
    return 1
end
Classes.Job_PerFrameFunctionCallback = {Spawn = function(_, callback)
    watcher = {callbackFunction = callback, Execute = function() end}
    return watcher
end}
Classes.Job_SpawnObject = {SpawnInWorld = function(_, island, kind, key, parent, x, y, z, rotation, overrides)
    check(island == currentWorld and parent == island and kind == "herdables" and key == visitorName,
        "Incorrect transient spawn")
    check(x == 6.25 and y == 2 and z == 7.25 and rotation == 0 and overrides.ScriptName == "CatAnimal",
        "Incorrect spawn position or script")
    spawned = spawned + 1
    return {
        SetInitFunction = function(self, callback) self.init = callback end,
        Execute = function(self)
            visitor = newCat()
            visitor.containingWorld = island
            visitor.collectionKey = visitorName
            function visitor:Destroy() self:Destructor(); self.isValid = false end
            visitor:RunnableCallback()
            self.init(visitor)
        end,
    }
end}

local function depart(island)
    destination = island and {"world", island.collectionKey}
    requested = nil
    watcher = nil
    Classes.Boat_Interaction_LeaveIsland:Action(player, {})
    check(requested == destination, "Ferry request changed")
end

local function arrive(island)
    currentWorld = island
    Classes.WorldBase.BeginIslandSimulationCallback(island)
    local initial = watcher
    player.containingWorld = island
    Classes.CharacterBase.BeginIslandSimulationCallback(player)
    check(initial == watcher, "Duplicate arrival callback queued")
end

player.containingWorld = world
action("Feed", cat, player)
depart(nil)
check(cat.prissykinsControl.mode == "follow", "Canceling the map changed Follow")
depart(away)
check(cat.prissykinsControl.mode == "stay", "Original kept following after ferry departure")
local departingPlayer = player
departingPlayer.isValid = false
player = nil
currentWorld = away
Classes.WorldBase.BeginIslandSimulationCallback(away)
watcher:callbackFunction()
check(watcher.callbackFunction and spawned == 0, "Arrival canceled when the source player was destroyed")
player = {
    isValid = false,
    containingWorld = world,
    GetPositionRotation = departingPlayer.GetPositionRotation,
    IsUnderScriptControl = departingPlayer.IsUnderScriptControl,
}
watcher:callbackFunction()
check(watcher.callbackFunction and spawned == 0, "Arrival did not wait for the new player to become valid")
player.isValid = true
watcher:callbackFunction()
check(watcher.callbackFunction and spawned == 0, "Visitor spawned before the player reached the destination")
arrive(away)
player.inCutscene = true
watcher:callbackFunction()
check(spawned == 0, "Visitor spawned under script control")
player.inCutscene = false
questComplete = false
watcher:callbackFunction()
check(watcher.callbackFunction and spawned == 0, "Arrival did not wait for the destination quest state")
questComplete = true
watcher:callbackFunction()
watcher:callbackFunction()
check(spawned == 1 and prepared == 1 and registered == 1 and watcher.callbackFunction == nil and
    visitor.prissykinsControl.mode == "follow", "First arrival did not start exactly one visitor")
action("Pet", visitor, player)
check(visitor.prissykinsControl.mode == "stay", "Away Pet did not set Stay")
action("Feed", visitor, player)
depart(third)
check(removed == 1 and not visitor.isValid, "Visitor was left on the source island")
arrive(third)
watcher:callbackFunction()
watcher:callbackFunction()
check(spawned == 2 and registered == 2, "Second arrival did not create exactly one visitor")
depart(world)
arrive(world)
watcher:callbackFunction()
check(spawned == 2 and removed == 2 and cat.arrivalPosition and cat.prissykinsControl.mode == "follow",
    "Home arrival did not reuse the original cat")
action("Pet", cat, player)
depart(away)
arrive(away)
check(watcher == nil, "A cat in Stay mode travelled")
currentWorld = world
player.containingWorld = world
action("Feed", cat, player)
allowSpawn = false
depart(away)
arrive(away)
watcher:callbackFunction()
check(spawned == 2 and watcher.callbackFunction == nil, "Spawned without a verified transient record")
allowSpawn = true
currentWorld = world
player.containingWorld = world
action("Feed", cat, player)
depart(away)
arrive(away)
watcher:callbackFunction()
watcher:callbackFunction()
action("Pet", visitor, player)
depart(third)
arrive(third)
check(watcher == nil and removed == 3 and not visitor.isValid, "Away Stay carried a visitor to another island")
print("PASS: ferry cancellation, source player destruction, destination player replacement and readiness, duplicate callbacks, away Pet/Feed, multi-island handoff, original cat reuse, Stay, and transient guard.")
