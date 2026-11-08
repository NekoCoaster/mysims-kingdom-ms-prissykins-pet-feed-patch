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

local world = {}
local player = {isValid = true, containingWorld = world}
Universe = {GetPlayerGameObject = function() return player end, GetWorld = function() return world end}
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
check(cat.prissykinsControl.mode == "follow" and cat.lastTimer.isValid, "Canceled Pet failed to restore follow")

action("Pet", cat, player)
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
