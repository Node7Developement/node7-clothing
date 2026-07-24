local Config = Node7ClothingConfig or {}
local RESOURCE = GetCurrentResourceName()

local catalog = nil
local categoryByName = {}
local storeById = {}
local session = nil
local editorCam = nil
local textUiVisible = false
local blips = {}

for _, category in ipairs(Config.Categories or {}) do
    categoryByName[category.name] = category
end

for _, store in ipairs(Config.Stores or {}) do
    storeById[store.id] = store
end

local function debugLog(message)
    if Config.Debug then
        print(('[node7-clothing] %s'):format(tostring(message)))
    end
end

local function notify(description, notifyType)
    lib.notify({
        title = Config.NotifyTitle or 'NODE7 Clothing',
        description = description,
        type = notifyType or 'inform'
    })
end

local function clone(value)
    if type(value) ~= 'table' then return value end
    local output = {}
    for key, item in pairs(value) do
        output[key] = clone(item)
    end
    return output
end

local function roundMoney(value)
    return math.floor(((tonumber(value) or 0) * 100) + 0.5) / 100
end

local function money(value)
    return ('$%.2f'):format(roundMoney(value))
end

local function normalizeItem(item)
    if type(item) ~= 'table' then return { model = 0, texture = 1, remove = true } end
    return {
        model = math.floor(tonumber(item.model) or 0),
        texture = math.floor(tonumber(item.texture) or 1),
        remove = item.remove == true or (tonumber(item.model) or 0) <= 0
    }
end

local function sameItem(left, right)
    left = normalizeItem(left)
    right = normalizeItem(right)
    return left.model == right.model and left.texture == right.texture and left.remove == right.remove
end

local function loadCatalog()
    if catalog then return true end

    local source = LoadResourceFile('node7-appearance', 'data/clothing.lua')
    if not source or source == '' then
        notify('Unable to read node7-appearance clothing data.', 'error')
        return false
    end

    local chunk, compileError = load(source, '@node7-appearance/data/clothing.lua', 't', {})
    if not chunk then
        debugLog(compileError)
        notify('node7-appearance clothing data failed to compile.', 'error')
        return false
    end

    local ok, data = pcall(chunk)
    if not ok or type(data) ~= 'table' then
        debugLog(data)
        notify('node7-appearance clothing catalog is invalid.', 'error')
        return false
    end

    catalog = data
    return true
end

local function getGenderCatalog()
    if not loadCatalog() then return nil end
    return catalog[IsPedMale(PlayerPedId()) and 'male' or 'female'] or {}
end

local function getCategoryList(category)
    local genderCatalog = getGenderCatalog()
    return genderCatalog and genderCatalog[category] or nil
end

local function getItemHash(list, model, texture)
    model = math.floor(tonumber(model) or 0)
    texture = math.floor(tonumber(texture) or 1)
    if model <= 0 or not list or not list[model] or not list[model][texture] then return nil end
    return tonumber(list[model][texture].hash)
end

local function appearanceReady()
    return GetResourceState('node7-appearance') == 'started'
end

local function applyClothes(clothes)
    if not appearanceReady() then
        notify('node7-appearance is not started.', 'error')
        return false
    end

    local ok, err = pcall(function()
        exports['node7-appearance']:ApplyClothes(clothes)
    end)

    if not ok then
        debugLog(err)
        notify('Failed to apply clothing preview.', 'error')
        return false
    end

    return true
end

local function getCurrentClothes()
    if not appearanceReady() then return {} end
    local ok, clothes = pcall(function()
        return exports['node7-appearance']:GetCurrentClothes()
    end)
    if not ok or type(clothes) ~= 'table' then return {} end
    return clone(clothes)
end

local function forceVisible()
    local ped = PlayerPedId()
    SetEntityVisible(ped, true)
    SetEntityAlpha(ped, 255, false)
    SetEntityCollision(ped, true, true)
end

local function updateCamera(viewName)
    if not session or not editorCam then return end

    viewName = viewName or session.cameraView or Config.Camera.focus or 'full'
    local view = Config.Camera.views[viewName] or Config.Camera.views.full
    session.cameraView = viewName

    local ped = PlayerPedId()
    local camPos = GetOffsetFromEntityInWorldCoords(ped, 0.0, tonumber(view.distance) or 2.2, tonumber(view.cameraZ) or 0.85)
    SetCamCoord(editorCam, camPos.x, camPos.y, camPos.z)
    PointCamAtEntity(editorCam, ped, 0.0, 0.0, tonumber(view.focusZ) or 0.75, true)
    SetCamFov(editorCam, 42.0)
end

local function startCamera()
    if editorCam then return end
    editorCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(editorCam, true)
    RenderScriptCams(true, true, 300, true, true)
    updateCamera()
end

local function stopCamera()
    if not editorCam then return end
    RenderScriptCams(false, true, 300, true, true)
    DestroyCam(editorCam, false)
    editorCam = nil
end

local function movePlayer(position)
    if not position then return end
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, position.x, position.y, position.z, false, false, false)
    SetEntityHeading(ped, position.w or position.h or 0.0)
end

local function beginEditor(store)
    local ped = PlayerPedId()
    session.startPosition = GetEntityCoords(ped)
    session.startHeading = GetEntityHeading(ped)

    if Config.FadeDuringEditorMove then
        DoScreenFadeOut(250)
        local timeout = GetGameTimer() + 1500
        while not IsScreenFadedOut() and GetGameTimer() < timeout do Wait(0) end
    end

    if Config.TeleportToEditor ~= false and store.editor then
        movePlayer(store.editor)
    end

    FreezeEntityPosition(ped, true)
    DisplayRadar(false)
    forceVisible()
    startCamera()

    if Config.FadeDuringEditorMove then
        DoScreenFadeIn(250)
    end
end

local function buildRollback()
    if not session then return {} end
    local rollback = clone(session.original)
    for category in pairs(session.touched or {}) do
        if rollback[category] == nil then
            rollback[category] = { model = 0, texture = 1, remove = true }
        end
    end
    return rollback
end

local function changedCategories()
    local changed = {}
    if not session then return changed end

    for _, category in ipairs(Config.Categories or {}) do
        if not sameItem(session.original[category.name], session.working[category.name]) then
            changed[#changed + 1] = category
        end
    end
    return changed
end

local function cartTotal()
    local total = 0.0
    for _, category in ipairs(changedCategories()) do
        local item = normalizeItem(session.working[category.name])
        if Config.ChargeForRemoval or not item.remove then
            total = total + (tonumber(category.price) or 0.0)
        end
    end
    return roundMoney(total)
end

local function hasChanges()
    return #changedCategories() > 0
end

local function closeSession(keepChanges)
    if not session then return end
    local active = session

    if not keepChanges then
        applyClothes(buildRollback())
        Wait(50)
        applyClothes(active.original)
    end

    stopCamera()
    DisplayRadar(true)
    FreezeEntityPosition(PlayerPedId(), false)

    if Config.FadeDuringEditorMove then
        DoScreenFadeOut(200)
        Wait(220)
    end

    if active.store and active.store.exit then
        movePlayer(active.store.exit)
    elseif active.startPosition then
        SetEntityCoordsNoOffset(PlayerPedId(), active.startPosition.x, active.startPosition.y, active.startPosition.z, false, false, false)
        SetEntityHeading(PlayerPedId(), active.startHeading or 0.0)
    end

    forceVisible()
    session = nil

    if Config.FadeDuringEditorMove then
        DoScreenFadeIn(200)
    end
end

local openStoreMenu
local openCategoriesMenu
local openCategoryMenu
local openCameraMenu

local function previewCategory(categoryName, model, texture, remove)
    if not session then return end
    local list = getCategoryList(categoryName) or {}
    model = math.max(0, math.min(math.floor(tonumber(model) or 0), #list))

    local maxTexture = 1
    if model > 0 and list[model] then maxTexture = math.max(1, #list[model]) end
    texture = math.max(1, math.min(math.floor(tonumber(texture) or 1), maxTexture))

    local item = {
        model = model,
        texture = texture,
        remove = remove == true or model == 0
    }

    if not item.remove then
        item.hash = getItemHash(list, model, texture)
    end

    session.working[categoryName] = item
    session.touched[categoryName] = true
    applyClothes(session.working)
    forceVisible()
end

openCategoryMenu = function(categoryName)
    if not session then return end
    local category = categoryByName[categoryName]
    local list = getCategoryList(categoryName) or {}
    if not category or #list == 0 then
        notify('This category has no compatible items for the current ped.', 'error')
        openCategoriesMenu()
        return
    end

    local current = normalizeItem(session.working[categoryName])
    local model = math.max(0, math.min(current.model, #list))
    local textureMax = (model > 0 and list[model] and #list[model]) or 1
    local texture = math.max(1, math.min(current.texture, textureMax))

    local function changeModel(delta)
        local nextModel = model + delta
        if nextModel < 0 then nextModel = #list end
        if nextModel > #list then nextModel = 0 end
        previewCategory(categoryName, nextModel, 1, nextModel == 0)
        openCategoryMenu(categoryName)
    end

    local function changeTexture(delta)
        if model <= 0 then
            notify('Select a model first.', 'error')
            openCategoryMenu(categoryName)
            return
        end
        local nextTexture = texture + delta
        if nextTexture < 1 then nextTexture = textureMax end
        if nextTexture > textureMax then nextTexture = 1 end
        previewCategory(categoryName, model, nextTexture, false)
        openCategoryMenu(categoryName)
    end

    lib.registerContext({
        id = 'node7_clothing_category_' .. categoryName,
        title = category.label,
        menu = 'node7_clothing_categories',
        options = {
            {
                title = current.remove and 'Removed' or ('Model %d / Texture %d'):format(model, texture),
                description = ('%d models | %s when purchased'):format(#list, money(category.price)),
                disabled = true
            },
            { title = 'Previous Model', icon = 'chevron-left', onSelect = function() changeModel(-1) end },
            { title = 'Next Model', icon = 'chevron-right', onSelect = function() changeModel(1) end },
            { title = 'Previous Texture', icon = 'minus', onSelect = function() changeTexture(-1) end },
            { title = 'Next Texture', icon = 'plus', onSelect = function() changeTexture(1) end },
            {
                title = 'Set Exact Model / Texture',
                icon = 'keyboard',
                onSelect = function()
                    local input = lib.inputDialog(category.label, {
                        { type = 'number', label = 'Model', default = model, min = 0, max = #list, required = true },
                        { type = 'number', label = 'Texture', default = texture, min = 1, max = 999, required = true }
                    })
                    if input then
                        previewCategory(categoryName, input[1], input[2], tonumber(input[1]) == 0)
                    end
                    openCategoryMenu(categoryName)
                end
            },
            {
                title = 'Remove Item',
                description = Config.ChargeForRemoval and ('Removal costs %s'):format(money(category.price)) or 'Removal is free.',
                icon = 'trash',
                onSelect = function()
                    previewCategory(categoryName, 0, 1, true)
                    openCategoryMenu(categoryName)
                end
            },
            { title = 'Back', icon = 'arrow-left', onSelect = openCategoriesMenu }
        }
    })
    lib.showContext('node7_clothing_category_' .. categoryName)
end

openCategoriesMenu = function()
    if not session then return end
    local options = {}

    for _, category in ipairs(Config.Categories or {}) do
        local list = getCategoryList(category.name)
        if list and #list > 0 then
            local item = normalizeItem(session.working[category.name])
            local status = item.remove and 'Removed' or ('Model %d / Texture %d'):format(item.model, item.texture)
            if not sameItem(session.original[category.name], session.working[category.name]) then
                status = status .. ' | Changed'
            end
            options[#options + 1] = {
                title = category.label,
                description = ('%s | %s'):format(status, money(category.price)),
                icon = category.icon or 'shirt',
                arrow = true,
                onSelect = function() openCategoryMenu(category.name) end
            }
        end
    end

    options[#options + 1] = { title = 'Back', icon = 'arrow-left', onSelect = openStoreMenu }

    lib.registerContext({
        id = 'node7_clothing_categories',
        title = 'Browse Clothing',
        menu = 'node7_clothing_store',
        options = options
    })
    lib.showContext('node7_clothing_categories')
end

openCameraMenu = function()
    if not session then return end
    local options = {}

    for name, view in pairs(Config.Camera.views or {}) do
        options[#options + 1] = {
            title = view.label or name,
            description = session.cameraView == name and 'Current view' or nil,
            icon = 'camera',
            onSelect = function()
                updateCamera(name)
                openCameraMenu()
            end
        }
    end

    options[#options + 1] = {
        title = 'Rotate Left', icon = 'rotate-left',
        onSelect = function()
            SetEntityHeading(PlayerPedId(), GetEntityHeading(PlayerPedId()) + (Config.Camera.rotateStep or 15.0))
            updateCamera()
            openCameraMenu()
        end
    }
    options[#options + 1] = {
        title = 'Rotate Right', icon = 'rotate-right',
        onSelect = function()
            SetEntityHeading(PlayerPedId(), GetEntityHeading(PlayerPedId()) - (Config.Camera.rotateStep or 15.0))
            updateCamera()
            openCameraMenu()
        end
    }
    options[#options + 1] = { title = 'Back', icon = 'arrow-left', onSelect = openStoreMenu }

    lib.registerContext({
        id = 'node7_clothing_camera',
        title = 'Camera Controls',
        menu = 'node7_clothing_store',
        options = options
    })
    lib.showContext('node7_clothing_camera')
end

local function openWardrobe()
    if not session then return end
    local discarded = hasChanges()
    closeSession(false)

    if discarded then
        notify('Unsaved clothing previews were discarded before opening the wardrobe.', 'inform')
    end

    SetTimeout(300, function()
        if GetResourceState('node7-wardrobe') ~= 'started' then
            notify('node7-wardrobe is not started.', 'error')
            return
        end
        local ok = pcall(function()
            exports['node7-wardrobe']:OpenWardrobe()
        end)
        if not ok then TriggerEvent('node7-wardrobe:client:openMenu') end
    end)
end

local function checkout()
    if not session then return end

    local result = lib.callback.await('node7-clothing:server:purchase', false, session.store.id, session.working)
    if not result or not result.success then
        notify((result and result.message) or 'Purchase failed.', 'error')
        openStoreMenu()
        return
    end

    local saved = type(result.clothes) == 'table' and result.clothes or session.working
    applyClothes(saved)
    notify(('Purchased and saved for %s.'):format(money(result.total or 0)), 'success')
    closeSession(true)
end

openStoreMenu = function()
    if not session then return end
    local changed = changedCategories()
    local total = cartTotal()

    lib.registerContext({
        id = 'node7_clothing_store',
        title = session.store.label,
        onExit = function()
            if session then closeSession(false) end
        end,
        options = {
            {
                title = 'Browse Clothing',
                description = ('%d categories available.'):format(#(Config.Categories or {})),
                icon = 'shirt',
                arrow = true,
                onSelect = openCategoriesMenu
            },
            {
                title = 'Camera Controls',
                description = 'Full body, torso, head, and rotation controls.',
                icon = 'camera',
                arrow = true,
                onSelect = openCameraMenu
            },
            {
                title = 'Cart',
                description = ('%d changed categories | Total %s'):format(#changed, money(total)),
                icon = 'cart-shopping',
                disabled = true
            },
            {
                title = 'Purchase and Save',
                description = hasChanges() and ('Charge %s and persist to your citizenid.'):format(money(total)) or 'No changes selected.',
                icon = 'cash-register',
                disabled = not hasChanges(),
                onSelect = checkout
            },
            {
                title = 'Wardrobe / Outfits',
                description = 'Open node7-wardrobe. Unsaved previews will be discarded.',
                icon = 'box-open',
                onSelect = openWardrobe
            },
            {
                title = 'Discard and Exit',
                description = 'Restore the outfit worn before entering.',
                icon = 'xmark',
                onSelect = function() closeSession(false) end
            }
        }
    })
    lib.showContext('node7_clothing_store')
end

local function openStore(storeId)
    if session then
        notify('You are already using a clothing store.', 'error')
        return false
    end
    if not appearanceReady() or not loadCatalog() then return false end

    local store = storeById[storeId]
    if not store then
        notify('Invalid clothing store.', 'error')
        return false
    end

    local original = getCurrentClothes()
    session = {
        store = store,
        original = original,
        working = clone(original),
        touched = {},
        cameraView = Config.Camera.focus or 'full'
    }

    beginEditor(store)
    openStoreMenu()
    return true
end

local function getNearestStore(maxDistance)
    local coords = GetEntityCoords(PlayerPedId())
    local nearest, nearestDistance

    for _, store in ipairs(Config.Stores or {}) do
        local distance = #(coords - store.coords)
        if (not nearestDistance or distance < nearestDistance) and (not maxDistance or distance <= maxDistance) then
            nearest = store
            nearestDistance = distance
        end
    end

    return nearest, nearestDistance
end

local function createBlip(store)
    if Config.UseBlips == false then return end
    local ok, blip = pcall(function()
        local handle = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, store.coords.x, store.coords.y, store.coords.z)
        SetBlipSprite(handle, Config.BlipSprite or 1195729388, true)
        SetBlipScale(handle, Config.BlipScale or 0.20)
        Citizen.InvokeNative(0x9CB1A1623062F402, handle, CreateVarString(10, 'LITERAL_STRING', store.label))
        return handle
    end)

    if ok and blip then blips[#blips + 1] = blip end
end

RegisterNetEvent('node7-clothing:client:open', function(storeId)
    if storeId then
        openStore(tostring(storeId))
        return
    end
    local store = getNearestStore(15.0)
    if store then openStore(store.id) else notify('No clothing store is nearby.', 'error') end
end)

RegisterNetEvent('node7-clothing:client:close', function()
    if session then closeSession(false) end
end)

if Config.EnableCommand ~= false then
    RegisterCommand(Config.Command or 'clothingstore', function()
        local store = getNearestStore(15.0)
        if store then openStore(store.id) else notify('No clothing store is nearby.', 'error') end
    end, false)
end

CreateThread(function()
    Wait(1000)
    loadCatalog()
    for _, store in ipairs(Config.Stores or {}) do createBlip(store) end
end)

CreateThread(function()
    while true do
        local waitTime = 1000

        if not session then
            local store, distance = getNearestStore(Config.DrawDistance or 35.0)
            if store and distance and distance <= (Config.InteractionDistance or 2.15) then
                waitTime = 0
                if not textUiVisible then
                    lib.showTextUI(('[E] %s'):format(store.label))
                    textUiVisible = true
                end

                if IsControlJustReleased(0, Config.OpenControl or 0xCEFD9220) then
                    if textUiVisible then
                        lib.hideTextUI()
                        textUiVisible = false
                    end
                    openStore(store.id)
                    Wait(500)
                end
            elseif textUiVisible then
                lib.hideTextUI()
                textUiVisible = false
            end
        elseif textUiVisible then
            lib.hideTextUI()
            textUiVisible = false
        end

        Wait(waitTime)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end
    if textUiVisible then lib.hideTextUI() end
    if session then closeSession(false) else stopCamera() end
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
end)

exports('OpenStore', openStore)
exports('CloseStore', function(keepChanges) if session then closeSession(keepChanges == true) end end)
exports('GetNearestStore', getNearestStore)
exports('IsShopping', function() return session ~= nil end)
