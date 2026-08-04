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

    return {
        model = model,
        texture = texture,
        hash = tonumber(item.hash),
        remove = item.remove == true or model <= 0
    }
end

local function sameItem(left, right)
    left = normalizeItem(left)
    right = normalizeItem(right)

    return left.model == right.model
        and left.texture == right.texture
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

local function applySingleCategory(category, item)
    local ped = PlayerPedId()
    item = normalizeItem(item)

    local ok, err = pcall(function()
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(category), 0)
        if not item.remove and item.hash then
            Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, item.hash, true, true, true)
        end
        refreshPed(ped)
    end)

    if not ok then debugLog(err) end
    forceVisible()
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
    return ok
end

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

    for _, value in ipairs(data.values) do
        local category = tostring(value.name or '')
        if flattened[category] then
            local nextItem = itemForFlatIndex(category, value.currentValue)
            local previous = normalizeItem(workingClothes[category])
            if previous.model ~= nextItem.model or previous.texture ~= nextItem.texture or previous.remove ~= nextItem.remove then
                workingClothes[category] = nextItem
                applySingleCategory(category, nextItem)
            end
        end
    end

    FreezeEntityPosition(PlayerPedId(), true)
    cb({ ok = true })
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
