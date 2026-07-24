local Config = Node7ClothingConfig or {}

local function debugLog(message)
    if Config.Debug then
        print(('[node7-clothing:interiors] %s'):format(tostring(message)))
    end
end

local function loadEntitySets(entry)
    if type(entry) ~= 'table' or not entry.coords or type(entry.sets) ~= 'table' then return end

    local interior = GetInteriorAtCoords(entry.coords.x, entry.coords.y, entry.coords.z)
    if not interior or interior == 0 or not IsValidInterior(interior) then
        debugLog(('invalid interior at %.2f %.2f %.2f'):format(entry.coords.x, entry.coords.y, entry.coords.z))
        return
    end

    local timeout = GetGameTimer() + 5000
    while not IsInteriorReady(interior) and GetGameTimer() < timeout do
        Wait(50)
    end

    for _, setName in ipairs(entry.sets) do
        if type(setName) == 'string' and setName ~= '' and not IsInteriorEntitySetActive(interior, setName) then
            ActivateInteriorEntitySet(interior, setName)
            debugLog(('activated entity set %s'):format(setName))
        end
    end
end

function Node7LoadClothingInteriors()
    local interiorConfig = Config.Interiors or {}
    if interiorConfig.enabled == false then return end

    for _, store in ipairs(Config.Stores or {}) do
        for _, imap in ipairs(store.imaps or {}) do
            RequestImap(tonumber(imap))
            debugLog(('requested imap %s for %s'):format(tostring(imap), tostring(store.id)))
        end

        for _, entry in ipairs(store.entitySets or {}) do
            loadEntitySets(entry)
        end
    end
end

RegisterNetEvent('node7-clothing:client:reloadInteriors', Node7LoadClothingInteriors)

CreateThread(function()
    if not Config.Interiors or Config.Interiors.loadAtStart ~= false then
        Wait(500)
        Node7LoadClothingInteriors()
        Wait((Config.Interiors and Config.Interiors.reloadDelay) or 5000)
        Node7LoadClothingInteriors()
    end
end)
