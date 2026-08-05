local Config = Node7ClothingConfig or {}
local RESOURCE = GetCurrentResourceName()
local Core = exports['node7-core']:GetCoreObject()

local Camera = nil
local BeforePosition = nil
local menuOpen = false
local menuType = nil
local originalClothes = {}
local workingClothes = {}
local catalog = nil
local flattened = {}
local prompts = {}
local pendingOutfitRequest = nil
local requestSequence = 0
local pendingOutfitName = nil
local checkoutPending = false
local purchaseInFlight = false
local purchaseSequence = 0
local pendingPurchaseId = nil
local outfitActionSequence = 0
local pendingOutfitActionId = nil
local barberRestoreRevision = 0
local hiddenCommandItems = {}
local wearableCommandState = {}
local catalogNameCache = {}
local playerLoadMaskRevision = 0
local playerLoadMaskPending = false

local function clone(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end

local function debugLog(message)
    if Config.Debug then
        print(('[node7-clothing] %s'):format(tostring(message)))
    end
end

local function notify(message, notificationType)
    if not Core or not Core.Functions or not Core.Functions.Notify then return end

    Core.Functions.Notify({
        title = 'Tailor',
        description = tostring(message or 'Clothing update.'),
        type = notificationType or 'info',
        duration = 5000
    })
end

local function forceVisible()
    local ped = PlayerPedId()
    SetEntityVisible(ped, true)
    SetEntityAlpha(ped, 255, false)
    SetEntityCollision(ped, true, true)
end

local function loadCatalog(silent)
    if catalog then return true end

    local source = LoadResourceFile('node7-appearance', 'data/clothing.lua')
    if not source or source == '' then
        print('[node7-clothing] ERROR: node7-appearance/data/clothing.lua could not be read.')
        if not silent then notify('Clothing catalog is unavailable.', 'error') end
        return false
    end

    local chunk, compileError = load(source, '@node7-appearance/data/clothing.lua', 't', {})
    if not chunk then
        print(('[node7-clothing] ERROR: clothing catalog compile failed: %s'):format(tostring(compileError)))
        if not silent then notify('Clothing catalog is unavailable.', 'error') end
        return false
    end

    local ok, data = pcall(chunk)
    if not ok or type(data) ~= 'table' then
        print(('[node7-clothing] ERROR: clothing catalog load failed: %s'):format(tostring(data)))
        if not silent then notify('Clothing catalog is unavailable.', 'error') end
        return false
    end

    catalog = data
    return true
end

local function genderName()
    return IsPedMale(PlayerPedId()) and 'male' or 'female'
end

local function getCategoryList(category)
    if not loadCatalog() then return nil end
    local genderCatalog = catalog[genderName()] or {}
    return genderCatalog[category]
end

local function rebuildFlattened()
    flattened = {}

    for _, category in ipairs(Config.Categories or {}) do
        local list = getCategoryList(category.name) or {}
        local values = {}

        for modelIndex, textures in ipairs(list) do
            for textureIndex, item in ipairs(textures or {}) do
                values[#values + 1] = {
                    model = modelIndex,
                    texture = textureIndex,
                    hash = tonumber(item.hash)
                }
            end
        end

        flattened[category.name] = values
    end
end

local function normalizeItem(item)
    if type(item) ~= 'table' then
        return { model = 0, texture = 1, remove = true }
    end

    local model = math.floor(tonumber(item.model) or 0)
    local texture = math.max(1, math.floor(tonumber(item.texture) or 1))
    local hash = tonumber(item.hash)
    local hasHash = hash and hash > 0

    return {
        model = model,
        texture = texture,
        hash = hash,
        remove = item.remove == true or (model <= 0 and not hasHash)
    }
end

local function sameItem(left, right)
    left = normalizeItem(left)
    right = normalizeItem(right)

    return left.model == right.model
        and left.texture == right.texture
        and tonumber(left.hash or 0) == tonumber(right.hash or 0)
        and left.remove == right.remove
end

local function calculateCheckoutTotal()
    local total = 0.0
    local changed = 0

    for _, category in ipairs(Config.Categories or {}) do
        local before = originalClothes[category.name]
        local after = workingClothes[category.name]

        if not sameItem(before, after) then
            changed = changed + 1
            local item = normalizeItem(after)

            if Config.ChargeForRemoval == true or not item.remove then
                total = total + math.max(0.0, tonumber(category.price) or 0.0)
            end
        end
    end

    return math.floor((total * 100) + 0.5) / 100, changed
end

local function flatIndexFor(category, item)
    item = normalizeItem(item)
    if item.remove then return 0 end

    for index, value in ipairs(flattened[category] or {}) do
        if value.model == item.model and value.texture == item.texture then
            return index
        end
    end

    return 0
end

local function itemForFlatIndex(category, index)
    index = math.floor(tonumber(index) or 0)
    if index <= 0 then
        return { model = 0, texture = 1, remove = true }
    end

    local value = (flattened[category] or {})[index]
    if not value then
        return { model = 0, texture = 1, remove = true }
    end

    return {
        model = value.model,
        texture = value.texture,
        hash = value.hash,
        remove = false
    }
end

local function refreshPed(ped)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, 0)
end

-- Clothing refreshes can rebuild MetaPed state and temporarily remove barber-owned
-- hair, beard, eyebrow, eye, and facial data. Debounce one restore after the final
-- clothing refresh instead of making node7-barbers fight every component change.
local function scheduleBarberRestore(delay, beardOnly)
    barberRestoreRevision = barberRestoreRevision + 1
    local revision = barberRestoreRevision

    CreateThread(function()
        Wait(math.max(0, math.floor(tonumber(delay) or 150)))
        if revision ~= barberRestoreRevision then return end
        if GetResourceState('node7-barbers') ~= 'started' then return end

        if beardOnly then
            -- Mask and neckwear toggles must not rebuild the entire barber state.
            -- Restore only the purchased beard after the component change settles.
            local restored = false
            local ok, result = pcall(function()
                return exports['node7-barbers']:RestoreBeardNow()
            end)
            restored = ok and result == true

            if not restored then
                pcall(function()
                    exports['node7-barbers']:RestoreBeard()
                end)
            end
            return
        end

        -- Full clothing/outfit rebuilds may affect every barber-owned head value.
        TriggerEvent('node7-appearance:client:applied')
    end)
end

local function isFaceCoveringCategory(category)
    category = tostring(category or ''):lower()
    return category == 'masks' or category == 'mask'
        or category == 'neckwear' or category == 'bandana'
end

local function applyCategoryComponent(ped, category, item)
    item = normalizeItem(item)
    local categoryHash = GetHashKey(category)

    if item.remove then
        if isFaceCoveringCategory(category) then
            -- Use the dedicated shop-item removal native for masks/neckwear.
            -- REMOVE_TAG + a full variation refresh was rebuilding the head and
            -- deleting the paid beard along with the face covering.
            Citizen.InvokeNative(0xDF631E4BCE1B1FC4, ped, categoryHash, true, true, true)
            return false
        end

        Citizen.InvokeNative(0xD710A5007C2AC539, ped, categoryHash, 0)
        return true
    end

    Citizen.InvokeNative(0xD710A5007C2AC539, ped, categoryHash, 0)
    if item.hash then
        -- The final flag must be true for RedM shop items. The previous false
        -- value prevented facial-hair components from being restored reliably.
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, item.hash, true, true, true)
    end
    return true
end

local function applyCategoryBatch(changes)
    if type(changes) ~= 'table' or #changes == 0 then return true end

    local ped = PlayerPedId()
    local needsVariation = false
    local beardOnlyRestore = true
    local ok, err = pcall(function()
        for index = 1, #changes do
            local change = changes[index]
            needsVariation = applyCategoryComponent(ped, change.category, change.item) or needsVariation
            beardOnlyRestore = beardOnlyRestore and isFaceCoveringCategory(change.category)
        end

        if needsVariation then
            refreshPed(ped)
        end
    end)

    if not ok then debugLog(err) end
    forceVisible()

    if ok then
        -- Face-covering commands restore only the beard. Other clothing changes
        -- can request the complete barber-owned head state.
        scheduleBarberRestore(beardOnlyRestore and 75 or 225, beardOnlyRestore)

        for index = 1, #changes do
            TriggerEvent('node7-clothing:client:componentApplied', changes[index].category)
        end
    end

    return ok
end

local function getCurrentClothes()
    if GetResourceState('node7-appearance') ~= 'started' then return {} end

    local ok, clothes = pcall(function()
        return exports['node7-appearance']:GetCurrentClothes()
    end)

    if not ok or type(clothes) ~= 'table' then return {} end
    return clone(clothes)
end

local function applyFullClothes(clothes)
    if GetResourceState('node7-appearance') ~= 'started' then return false end

    local ok, err = pcall(function()
        exports['node7-appearance']:ApplyClothes(clothes)
    end)

    if not ok then debugLog(err) end
    forceVisible()

    if ok then
        -- ApplyClothes performs a full MetaPed rebuild. Restore barber-owned state
        -- only after that rebuild and its collision/variation work have settled.
        scheduleBarberRestore(325)
    end

    return ok
end


local function clearCommandState()
    hiddenCommandItems = {}
    wearableCommandState = {}
end

local function itemHasValue(item)
    if type(item) ~= 'table' or item.remove == true then return false end
    return (tonumber(item.hash) or 0) > 0 or (tonumber(item.model) or 0) > 0
end

-- Saved masks remain owned by appearance, but they should never spawn enabled.
-- Keep the saved item in the temporary command cache so /mask can restore it,
-- then remove only the live mask component after character appearance finishes.
local function removeMaskAfterPlayerLoad(revision)
    if not playerLoadMaskPending or revision ~= playerLoadMaskRevision then return false end
    if GetResourceState('node7-appearance') ~= 'started' then return false end

    local clothes = getCurrentClothes()
    if type(clothes) ~= 'table' or next(clothes) == nil then return false end

    local savedMask = clothes.masks or clothes.mask
    local previousHidden = hiddenCommandItems.masks

    if itemHasValue(savedMask) then
        hiddenCommandItems.masks = clone(savedMask)
    end

    local removed = applyCategoryBatch({
        {
            category = 'masks',
            item = { model = 0, texture = 1, remove = true }
        }
    })

    if not removed then
        hiddenCommandItems.masks = previousHidden
        return false
    end

    wearableCommandState.masks = nil
    playerLoadMaskPending = false
    debugLog('saved mask removed for player load; /mask can restore it')
    return true
end

local function queueMaskRemovalForPlayerLoad()
    playerLoadMaskRevision = playerLoadMaskRevision + 1
    local revision = playerLoadMaskRevision

    clearCommandState()
    playerLoadMaskPending = true

    CreateThread(function()
        -- Appearance normally emits its completion event first. This retry loop
        -- covers slower database/server restarts without removing the mask later
        -- during normal gameplay.
        local deadline = GetGameTimer() + 15000
        Wait(500)

        while playerLoadMaskPending
            and revision == playerLoadMaskRevision
            and GetGameTimer() < deadline do
            if removeMaskAfterPlayerLoad(revision) then return end
            Wait(500)
        end

        if revision == playerLoadMaskRevision then
            playerLoadMaskPending = false
        end
    end)
end

local function getCommandConfig(value)
    value = tostring(value or ''):lower()

    -- Explicit command/name matches must win over category aliases.
    for _, item in ipairs(Config.CommandCategories or {}) do
        if tostring(item.command or ''):lower() == value
            or tostring(item.name or ''):lower() == value then
            return item
        end
    end

    for _, item in ipairs(Config.CommandCategories or {}) do
        if tostring(item.category or ''):lower() == value then
            return item
        end
    end

    return nil
end

local function getCatalogItemName(category, item)
    if type(item) ~= 'table' then return nil end
    category = tostring(category or '')
    if category == '' then return nil end

    catalogNameCache[category] = catalogNameCache[category] or {}
    local categoryCache = catalogNameCache[category]
    local hash = tonumber(item.hash)

    if hash and categoryCache[hash] ~= nil then
        return categoryCache[hash] or nil
    end

    local list = getCategoryList(category) or {}
    local selected = nil

    if hash and hash > 0 then
        for _, textures in ipairs(list) do
            for _, catalogItem in ipairs(textures or {}) do
                local catalogHash = tonumber(catalogItem.hash)
                if catalogHash then
                    categoryCache[catalogHash] = tostring(catalogItem.hashname or ''):lower()
                end
                if catalogHash == hash then selected = catalogItem end
            end
        end
    else
        local model = math.floor(tonumber(item.model) or 0)
        local texture = math.max(1, math.floor(tonumber(item.texture) or 1))
        selected = list[model] and list[model][texture] or nil
    end

    if not selected then
        if hash then categoryCache[hash] = false end
        return nil
    end

    local name = tostring(selected.hashname or ''):lower()
    if hash then categoryCache[hash] = name end
    return name ~= '' and name or nil
end

local function commandMatchesItem(command, item)
    local match = tostring(command.matchHashname or ''):lower()
    if match == '' then return true end

    local itemName = getCatalogItemName(command.category, item)
    -- Older saved clothing rows may not contain enough catalog metadata.
    -- In that case allow the category toggle to continue normally.
    if not itemName then return true end
    return itemName:find(match, 1, true) ~= nil
end

local function applyWearableState(componentHash, wearableName)
    local hash = tonumber(componentHash)
    if not hash or hash <= 0 then return false end

    local ped = PlayerPedId()
    local ok, err = pcall(function()
        Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, hash, joaat(wearableName), 0, true, 1)
        refreshPed(ped)
    end)

    if not ok then
        debugLog(('wearable update failed: %s'):format(tostring(err)))
        return false
    end

    forceVisible()
    scheduleBarberRestore(250)
    return true
end

local function toggleWearable(command)
    local clothes = getCurrentClothes()
    local current = clothes[command.category]

    if not itemHasValue(current) then
        notify(('No %s is currently equipped.'):format(command.label or command.category), 'error')
        return false
    end

    local activeCommand = wearableCommandState[command.category]
    local targetState = activeCommand == command.command and 'BASE' or command.wearable

    if not applyWearableState(current.hash, targetState) then
        notify(('Unable to change %s.'):format(command.label or command.category), 'error')
        return false
    end

    if targetState == 'BASE' then
        wearableCommandState[command.category] = nil
        notify((command.label or command.command) .. ' reset.', 'success')
    else
        wearableCommandState[command.category] = command.command
        notify((command.label or command.command) .. ' changed.', 'success')
    end

    return true
end

local function toggleCommandCategory(value)
    local command = getCommandConfig(value)
    if not command then
        notify('Unknown clothing category.', 'error')
        return false
    end

    if command.wearable then
        return toggleWearable(command)
    end

    local category = command.category
    local hidden = hiddenCommandItems[category]

    if hidden then
        if not commandMatchesItem(command, hidden) then
            notify(('The hidden %s does not match this command.'):format(command.label or category), 'error')
            return false
        end

        if applyCategoryBatch({ { category = category, item = clone(hidden) } }) then
            hiddenCommandItems[category] = nil
            notify((command.label or category) .. ' restored.', 'success')
            return true
        end

        return false
    end

    local clothes = getCurrentClothes()
    local current = clothes[category]

    if not itemHasValue(current) then
        notify(('No %s is currently equipped.'):format(command.label or category), 'error')
        return false
    end

    if not commandMatchesItem(command, current) then
        notify('No bandana is currently equipped.', 'error')
        return false
    end

    hiddenCommandItems[category] = clone(current)

    if applyCategoryBatch({
        { category = category, item = { model = 0, texture = 1, remove = true } }
    }) then
        notify((command.label or category) .. ' removed.', 'success')
        return true
    end

    hiddenCommandItems[category] = nil
    return false
end

local function undressCommands()
    local clothes = getCurrentClothes()
    if next(clothes) == nil then
        notify('No clothing is currently loaded.', 'error')
        return false
    end

    local changes = {}
    local seen = {}

    for _, command in ipairs(Config.CommandCategories or {}) do
        local category = command.category
        if not command.wearable
            and not command.matchHashname
            and not seen[category]
            and not (Config.SafeUndressKeep and Config.SafeUndressKeep[category]) then
            seen[category] = true
            local current = clothes[category]
            if itemHasValue(current) then
                hiddenCommandItems[category] = hiddenCommandItems[category] or clone(current)
                changes[#changes + 1] = {
                    category = category,
                    item = { model = 0, texture = 1, remove = true }
                }
            end
        end
    end

    if #changes == 0 then
        notify('No removable outer clothing is equipped.', 'info')
        return false
    end

    local ok = applyCategoryBatch(changes)
    if ok then notify('Outer clothing removed.', 'success') end
    return ok
end

local function dressCommands()
    local changes = {}
    for category, item in pairs(hiddenCommandItems) do
        changes[#changes + 1] = { category = category, item = clone(item) }
    end

    local restoredAnything = #changes > 0
    local ok = true

    if #changes > 0 then
        ok = applyCategoryBatch(changes)
        if ok then hiddenCommandItems = {} end
    end

    local wearableChanged = false
    if next(wearableCommandState) ~= nil then
        local clothes = getCurrentClothes()
        local ped = PlayerPedId()

        for category in pairs(wearableCommandState) do
            local item = clothes[category]
            if itemHasValue(item) and (tonumber(item.hash) or 0) > 0 then
                local wearableOk = pcall(function()
                    Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, tonumber(item.hash), joaat('BASE'), 0, true, 1)
                end)
                wearableChanged = wearableChanged or wearableOk
            end
        end

        wearableCommandState = {}
        if wearableChanged then
            refreshPed(ped)
            forceVisible()
            scheduleBarberRestore(250)
            restoredAnything = true
        end
    end

    if restoredAnything and ok then
        notify('Clothing restored.', 'success')
        return true
    end

    notify('No clothing is currently hidden.', 'info')
    return false
end

local function registerClothingCommands()
    RegisterCommand(Config.DressCommand or 'dress', dressCommands, false)
    RegisterCommand(Config.UndressCommand or 'undress', undressCommands, false)

    if Config.EnableToggleCommands == false then return end

    local registered = {}
    for _, command in ipairs(Config.CommandCategories or {}) do
        local name = tostring(command.command or ''):lower()
        if name ~= '' and not registered[name] then
            registered[name] = true
            local commandName = name
            RegisterCommand(commandName, function()
                toggleCommandCategory(commandName)
            end, false)
        end
    end
end

RegisterNetEvent('Node7Core:Client:OnPlayerLoaded', queueMaskRemovalForPlayerLoad)

RegisterNetEvent('node7-appearance:client:applied', function()
    if not playerLoadMaskPending then return end

    local revision = playerLoadMaskRevision
    CreateThread(function()
        Wait(75)
        removeMaskAfterPlayerLoad(revision)
    end)
end)

RegisterNetEvent('node7-clothing:client:toggleCategory', toggleCommandCategory)
RegisterNetEvent('node7-clothing:client:dress', dressCommands)
RegisterNetEvent('node7-clothing:client:undress', undressCommands)

-- Compatibility is owned here now that node7-wardrobe is outfit-only.
RegisterNetEvent('rsg-wardrobe:client:OnOffClothing', toggleCommandCategory)
RegisterNetEvent('rsg-wardrobe:client:removeAllClothing', undressCommands)

exports('ToggleClothing', toggleCommandCategory)
exports('RemoveAllClothing', undressCommands)
exports('DressClothing', dressCommands)
exports('FixVisibility', forceVisible)
exports('IsHidden', function(value)
    local command = getCommandConfig(value)
    return command and hiddenCommandItems[command.category] ~= nil or false
end)

CreateThread(function()
    Wait(500)
    registerClothingCommands()
end)

local function buildClothingValues()
    local values = {}

    for _, category in ipairs(Config.Categories or {}) do
        local choices = flattened[category.name] or {}
        if #choices > 0 then
            values[#values + 1] = {
                name = category.name,
                minValue = 0,
                maxValue = #choices,
                currentValue = flatIndexFor(category.name, workingClothes[category.name])
            }
        end
    end

    return values
end

local function disableCamera()
    if Camera and DoesCamExist(Camera) then
        SetCamActive(Camera, false)
        RenderScriptCams(false, true, 250, true, true)
        DestroyCam(Camera, false)
    else
        RenderScriptCams(false, false, 0, true, true)
    end

    Camera = nil
    SetNuiFocus(false, false)
    FreezeEntityPosition(PlayerPedId(), false)
end

local function enableCamera()
    local ped = PlayerPedId()

    if Camera and DoesCamExist(Camera) then
        DestroyCam(Camera, false)
    end

    local playerCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.0)
    Camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(Camera, true)
    SetCamCoord(Camera, playerCoords.x, playerCoords.y, playerCoords.z + 0.5)
    SetCamRot(Camera, 0.0, 0.0, GetEntityHeading(ped) + 180.0, 2)
    RenderScriptCams(true, false, 0, true, true)
end

local function clothingRoomTransition(coords)
    local ped = PlayerPedId()

    DoScreenFadeOut(350)
    local timeout = GetGameTimer() + 2000
    while not IsScreenFadedOut() and GetGameTimer() < timeout do Wait(0) end

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, coords.w or 0.0)

    timeout = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end

    Wait(150)
    DoScreenFadeIn(350)
end

local function restorePosition()
    if not BeforePosition then return end
    clothingRoomTransition(BeforePosition)
    BeforePosition = nil
end

local function closeMenu(commit)
    if not menuOpen then return end

    menuOpen = false
    menuType = nil
    checkoutPending = false
    purchaseInFlight = false
    pendingPurchaseId = nil
    pendingOutfitName = nil

    SendNUIMessage({ type = 'paymentClose' })
    SendNUIMessage({ type = 'forceClose' })

    if commit then
        applyFullClothes(workingClothes)
    else
        applyFullClothes(originalClothes)
    end

    disableCamera()
    restorePosition()
    forceVisible()
end

local function reopenClothingMenu()
    if not menuOpen then return end

    menuType = 'clothingMenu'
    SendNUIMessage({ type = 'paymentClose' })
    SendNUIMessage({ type = 'clothingMenu', clothes = buildClothingValues() })
end

local function beginCheckout()
    if not menuOpen or checkoutPending or purchaseInFlight then return end

    if menuType ~= 'clothingMenu' then
        closeMenu(true)
        return
    end

    local total, changed = calculateCheckoutTotal()

    if changed <= 0 then
        if pendingOutfitName and pendingOutfitName ~= '' then
            outfitActionSequence = outfitActionSequence + 1
            pendingOutfitActionId = ('%s:save:%s'):format(
                GetPlayerServerId(PlayerId()),
                outfitActionSequence
            )
            TriggerServerEvent(
                'node7-clothing:server:saveCurrentOutfit',
                pendingOutfitActionId,
                pendingOutfitName
            )
        else
            notify('No clothing changes were selected.', 'info')
        end

        closeMenu(true)
        return
    end

    checkoutPending = true
    SendNUIMessage({
        type = 'paymentMenu',
        total = total,
        changed = changed,
        methods = Config.PaymentMethods or {
            cash = 'Cash',
            bank = 'Bank'
        }
    })
end

local function requestOutfits(callback)
    requestSequence = requestSequence + 1
    local requestId = requestSequence
    pendingOutfitRequest = { id = requestId, callback = callback }
    TriggerServerEvent('node7-clothing:server:getOutfits', requestId)
end

RegisterNetEvent('node7-clothing:client:outfitsResponse', function(requestId, outfits)
    if not pendingOutfitRequest or pendingOutfitRequest.id ~= requestId then return end
    local callback = pendingOutfitRequest.callback
    pendingOutfitRequest = nil
    callback(type(outfits) == 'table' and outfits or {})
end)

local function openMenu(targetMenuType)
    if menuOpen then return end
    if not loadCatalog(false) then return end

    rebuildFlattened()
    originalClothes = getCurrentClothes()
    workingClothes = clone(originalClothes)

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    BeforePosition = vector4(coords.x, coords.y, coords.z, GetEntityHeading(ped))

    clothingRoomTransition(Config.StaticClothingRoom)
    ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, true)
    forceVisible()

    menuOpen = true
    menuType = targetMenuType
    pendingOutfitName = nil
    checkoutPending = false
    purchaseInFlight = false
    pendingPurchaseId = nil
    SendNUIMessage({ type = 'paymentClose' })
    SetNuiFocus(true, true)
    enableCamera()

    if targetMenuType == 'outfitMenu' then
        requestOutfits(function(outfits)
            if not menuOpen or menuType ~= 'outfitMenu' then return end
            SendNUIMessage({ type = 'outfitMenu', outfits = outfits })
        end)
    else
        SendNUIMessage({ type = 'clothingMenu', clothes = buildClothingValues() })
    end
end

RegisterNUICallback('rotateCamera', function(data, cb)
    if menuOpen then
        local ped = PlayerPedId()
        local direction = tostring(data.direction or '')
        if direction == 'left' then
            SetEntityHeading(ped, GetEntityHeading(ped) - 10.0)
        elseif direction == 'right' then
            SetEntityHeading(ped, GetEntityHeading(ped) + 10.0)
        end
    end
    cb({ ok = menuOpen })
end)

RegisterNUICallback('setCamera', function(data, cb)
    if menuOpen and Camera and DoesCamExist(Camera) then
        local ped = PlayerPedId()
        local mode = tonumber(data.direction)
        local playerCoords

        if mode == 1 then
            playerCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.75, 0.0)
            SetCamCoord(Camera, playerCoords.x, playerCoords.y, playerCoords.z + 0.65)
        elseif mode == 2 then
            playerCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.0)
            SetCamCoord(Camera, playerCoords.x, playerCoords.y, playerCoords.z + 0.2)
        elseif mode == 3 then
            playerCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.0)
            SetCamCoord(Camera, playerCoords.x, playerCoords.y, playerCoords.z - 0.5)
        end

        if playerCoords then
            SetCamRot(Camera, 0.0, 0.0, GetEntityHeading(ped) + 180.0, 2)
        end
    end
    cb({ ok = menuOpen })
end)

RegisterNUICallback('applyClothes', function(data, cb)
    if not menuOpen or type(data.values) ~= 'table' then
        cb({ ok = false })
        return
    end

    local changes = {}

    for index = 1, #data.values do
        local value = data.values[index]
        local category = tostring(value.name or '')

        if flattened[category] then
            local nextItem = itemForFlatIndex(category, value.currentValue)
            local previous = normalizeItem(workingClothes[category])

            if not sameItem(previous, nextItem) then
                workingClothes[category] = nextItem
                changes[#changes + 1] = {
                    category = category,
                    item = nextItem
                }
            end
        end
    end

    local ok = applyCategoryBatch(changes)
    FreezeEntityPosition(PlayerPedId(), true)
    cb({ ok = ok, changed = #changes })
end)

RegisterNUICallback('applySkin', function(_, cb)
    cb({ ok = false })
end)

RegisterNUICallback('useOutfit', function(data, cb)
    if not menuOpen or type(data.skin) ~= 'table' then
        cb({ ok = false })
        return
    end

    outfitActionSequence = outfitActionSequence + 1
    pendingOutfitActionId = ('%s:use:%s'):format(
        GetPlayerServerId(PlayerId()),
        outfitActionSequence
    )

    TriggerServerEvent(
        'node7-clothing:server:useOutfit',
        pendingOutfitActionId,
        data.skin
    )

    cb({ ok = true, pending = true })
end)

RegisterNUICallback('saveOutfit', function(data, cb)
    if not menuOpen then
        cb({ ok = false, message = 'The clothing shop is not open.' })
        return
    end

    local name = tostring(data.outfitName or '')
        :gsub('^%s+', '')
        :gsub('%s+$', '')

    if #name < 2 then
        cb({ ok = false, message = 'Enter an outfit name.' })
        return
    end

    if #name > 40 then
        name = name:sub(1, 40)
    end

    pendingOutfitName = name
    cb({ ok = true, outfitName = name })
end)

RegisterNUICallback('save', function(_, cb)
    if menuOpen then beginCheckout() end
    cb({ ok = true })
end)

-- QBR's Save path calls closeMenu. Clothing checkout now asks for Cash or Bank first.
RegisterNUICallback('closeMenu', function(_, cb)
    if menuOpen then beginCheckout() end
    cb({ ok = true })
end)

RegisterNUICallback('beginCheckout', function(_, cb)
    if menuOpen then
        beginCheckout()
    end
    cb({ ok = menuOpen, checkout = checkoutPending })
end)

RegisterNUICallback('purchase', function(data, cb)
    if not menuOpen or not checkoutPending or purchaseInFlight then
        cb({ ok = false })
        return
    end

    local method = tostring(data.method or ''):lower()
    local allowed = Config.PaymentMethods or { cash = 'Cash', bank = 'Bank' }
    if not allowed[method] then
        cb({ ok = false, message = 'Invalid payment method.' })
        return
    end

    purchaseSequence = purchaseSequence + 1
    pendingPurchaseId = ('%s:%s'):format(GetPlayerServerId(PlayerId()), purchaseSequence)
    purchaseInFlight = true

    TriggerServerEvent(
        'node7-clothing:server:purchase',
        pendingPurchaseId,
        method,
        workingClothes,
        pendingOutfitName
    )

    cb({ ok = true })
end)

RegisterNUICallback('cancelPayment', function(_, cb)
    if menuOpen and not purchaseInFlight then
        checkoutPending = false
        pendingOutfitName = nil
        reopenClothingMenu()
    end
    cb({ ok = menuOpen and not purchaseInFlight })
end)

RegisterNetEvent('node7-clothing:client:purchaseResult', function(requestId, result)
    if not pendingPurchaseId or tostring(requestId or '') ~= pendingPurchaseId then return end

    purchaseInFlight = false
    pendingPurchaseId = nil
    result = type(result) == 'table' and result or {}

    if result.success == true and type(result.clothes) == 'table' then
        clearCommandState()
        workingClothes = clone(result.clothes)
        SendNUIMessage({
            type = 'paymentResult',
            success = true,
            message = result.message or 'Purchase complete.'
        })
        closeMenu(true)
        return
    end

    SendNUIMessage({
        type = 'paymentResult',
        success = false,
        message = result.message or 'Payment failed.'
    })
end)


RegisterNetEvent('node7-clothing:client:outfitActionResult', function(requestId, result)
    if not pendingOutfitActionId or tostring(requestId or '') ~= pendingOutfitActionId then return end

    pendingOutfitActionId = nil
    result = type(result) == 'table' and result or {}

    if result.success == true and type(result.clothes) == 'table' then
        clearCommandState()
        workingClothes = clone(result.clothes)
        originalClothes = clone(result.clothes)
        applyFullClothes(workingClothes)

        if menuOpen then
            FreezeEntityPosition(PlayerPedId(), true)
        end
    end
end)

-- QBR's Close/Escape path calls closeMenu2. Discard the preview.
RegisterNUICallback('closeMenu2', function(_, cb)
    if menuOpen then closeMenu(false) end
    cb({ ok = true })
end)

RegisterNetEvent('node7-clothing:client:openMenu', function(_, targetMenuType)
    openMenu(targetMenuType == 'outfitMenu' and 'outfitMenu' or 'clothingMenu')
end)

RegisterNetEvent('node7-clothing:client:openClothing', function()
    openMenu('clothingMenu')
end)

RegisterNetEvent('node7-clothing:client:openOutfits', function()
    openMenu('outfitMenu')
end)

local function createPrompt(control, text, group)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, control)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', text))
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, true)
    PromptSetStandardMode(prompt, true)
    PromptSetGroup(prompt, group, 0)
    PromptRegisterEnd(prompt)
    return prompt
end

CreateThread(function()
    loadCatalog(true)

    for index, store in ipairs(Config.Stores or {}) do
        local group = GetRandomIntInRange(0, 0xFFFFFF)
        prompts[index] = {
            group = group,
            clothing = createPrompt(Config.ClothingControl or 0xF3830D8E, 'Open ' .. store.name, group),
            outfits = createPrompt(Config.OutfitsControl or 0xC7B5340A, 'Open Outfits', group)
        }

        if Config.ShowBlips ~= false and store.showblip ~= false then
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, store.coords.x, store.coords.y, store.coords.z)
            SetBlipSprite(blip, Config.BlipSprite or 1195729388, true)
            SetBlipScale(blip, Config.BlipScale or 0.20)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, CreateVarString(10, 'LITERAL_STRING', store.name))
            prompts[index].blip = blip
        end
    end

    SetNuiFocus(false, false)
    RenderScriptCams(false, false, 0, true, true)
end)

CreateThread(function()
    while true do
        local waitTime = 750

        if not menuOpen then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)

            for index, store in ipairs(Config.Stores or {}) do
                local distance = #(coords - store.coords)
                if distance <= (Config.DrawDistance or 25.0) then
                    waitTime = 0
                    if distance <= (Config.InteractionDistance or 2.0) then
                        local promptData = prompts[index]
                        if promptData then
                            PromptSetActiveGroupThisFrame(promptData.group, CreateVarString(10, 'LITERAL_STRING', store.name), 1, 0, 0, 0)

                            if PromptHasStandardModeCompleted(promptData.clothing) then
                                openMenu('clothingMenu')
                                Wait(500)
                                break
                            end

                            if PromptHasStandardModeCompleted(promptData.outfits) then
                                openMenu('outfitMenu')
                                Wait(500)
                                break
                            end
                        end
                    end
                end
            end
        else
            waitTime = 200
            FreezeEntityPosition(PlayerPedId(), true)
            forceVisible()
        end

        Wait(waitTime)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then return end
    SetNuiFocus(false, false)
    RenderScriptCams(false, false, 0, true, true)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end

    SetNuiFocus(false, false)
    disableCamera()

    if menuOpen then
        applyFullClothes(originalClothes)
        if BeforePosition then
            local ped = PlayerPedId()
            SetEntityCoordsNoOffset(ped, BeforePosition.x, BeforePosition.y, BeforePosition.z, false, false, false)
            SetEntityHeading(ped, BeforePosition.w or 0.0)
        end
    end

    for _, data in pairs(prompts) do
        if data.clothing then PromptDelete(data.clothing) end
        if data.outfits then PromptDelete(data.outfits) end
        if data.blip then RemoveBlip(data.blip) end
    end
end)

exports('OpenClothing', function() openMenu('clothingMenu') end)
exports('OpenOutfits', function() openMenu('outfitMenu') end)
exports('IsOpen', function() return menuOpen end)
