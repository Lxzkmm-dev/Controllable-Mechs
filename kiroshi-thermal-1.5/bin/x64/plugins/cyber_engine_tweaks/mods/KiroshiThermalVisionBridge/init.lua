local nightVision
local lastRequestID
local availabilityTimer = 0
local sessionActive = false
local originalToggleNV
local integratedToggleNV

local function ClearIntegrationFacts(quests)
    quests:SetFactStr("qc_night_vision_bridge_present", 0)
    quests:SetFactStr("qc_night_vision_available", 0)
    quests:SetFactStr("qc_night_vision_active", 0)
    quests:SetFactStr("qc_night_vision_requested", 0)
end

registerForEvent("onInit", function()
    nightVision = GetMod("nightVision")
    if type(nightVision) ~= "table" or type(nightVision.runtimeData) ~= "table" or type(nightVision.hasNVInstalled) ~= "function" or type(nightVision.toggleNV) ~= "function" then
        nightVision = nil
    else
        originalToggleNV = nightVision.toggleNV
        integratedToggleNV = function(self, ...)
            local container = Game.GetScriptableSystemsContainer()
            local thermalSystem = container and container:Get("ThermalVision.ThermalVisionSystem")
            if thermalSystem and thermalSystem:TryToggleKiroshiIntegration() then
                return
            end
            return originalToggleNV(self, ...)
        end
        nightVision.toggleNV = integratedToggleNV
    end
    lastRequestID = nil
    availabilityTimer = 0
    sessionActive = false
end)

registerForEvent("onUpdate", function(deltaTime)
    local active = nightVision ~= nil and nightVision.runtimeData.inGame == true
    if not active then
        if nightVision and sessionActive then
            nightVision.runtimeData.enabled = false
        end
        sessionActive = false
        lastRequestID = nil
        availabilityTimer = 0
    end

    local quests = Game.GetQuestsSystem()
    if not quests then
        return
    end

    if not active then
        ClearIntegrationFacts(quests)
        return
    end

    if not sessionActive then
        sessionActive = true
        availabilityTimer = 0
        lastRequestID = quests:GetFactStr("qc_night_vision_request_id")
        quests:SetFactStr("qc_night_vision_requested", 0)
        quests:SetFactStr("qc_night_vision_bridge_present", 1)
        quests:SetFactStr("qc_night_vision_available", 0)
        quests:SetFactStr("qc_night_vision_active", 0)
        nightVision.runtimeData.enabled = false
    end

    availabilityTimer = availabilityTimer - deltaTime
    if availabilityTimer <= 0 then
        local checkSucceeded, hasNightVision = pcall(function()
            return nightVision:hasNVInstalled()
        end)
        local available = checkSucceeded and hasNightVision == true
        quests:SetFactStr("qc_night_vision_available", available and 1 or 0)
        if not available then
            nightVision.runtimeData.enabled = false
        end
        availabilityTimer = 1
    end

    local requestID = quests:GetFactStr("qc_night_vision_request_id")
    if lastRequestID == nil then
        lastRequestID = requestID
    elseif requestID ~= lastRequestID then
        local requested = quests:GetFactStr("qc_night_vision_requested") > 0
        nightVision.runtimeData.enabled = requested
        lastRequestID = requestID
    end

    if quests:GetFactStr("qc_thermal_vision_active") > 0 and nightVision.runtimeData.enabled then
        nightVision.runtimeData.enabled = false
    end

    quests:SetFactStr("qc_night_vision_bridge_present", 1)
    quests:SetFactStr("qc_night_vision_active", nightVision.runtimeData.enabled and 1 or 0)
end)

registerForEvent("onShutdown", function()
    local quests = Game.GetQuestsSystem()
    if quests then
        ClearIntegrationFacts(quests)
    end

    if nightVision and originalToggleNV and nightVision.toggleNV == integratedToggleNV then
        nightVision.toggleNV = originalToggleNV
    end

    nightVision = nil
    originalToggleNV = nil
    integratedToggleNV = nil
    lastRequestID = nil
    availabilityTimer = 0
    sessionActive = false
end)
