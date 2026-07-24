local Config = Node7ClothingConfig or {}
local Node7Core = exports['node7-core']:GetCoreObject()

local categoryByName = {}
local storeById = {}
local catalog = nil
local purchaseLocks = {}

for _, category in ipairs(Config.Categories or {}) do
    categoryByName[category.name] = category
end

for _, store in ipairs(Config.Stores or {}) do
    storeById[store.id] = store
end

local function debugLog(message)
    if Config.Debug then
        print(('[node7-clothing:server] %s'):format(tostring(message)))
    end
end

local function clone(value)
    if type(value) ~= 'table' then return value end
    local output = {}
    for key, item in pairs(value) do output[key] = clone(item) end
    return output
end

local function loadCatalog()
    if catalog then return true end
    local source = LoadResourceFile('node7-appearance', 'data/clothing.lua')
    if not source or source == '' then return false end

    local chunk, compileError = load(source, '@node7-appearance/data/clothing.lua', 't', {})
    if not chunk then
        debugLog(compileError)
        return false
    end

    local ok, data = pcall(chunk)
    if not ok or type(data) ~= 'table' then
        debugLog(data)
        return false
    end

    catalog = data
    return true
end

local function normalized(item)
    if type(item) ~= 'table' then return { model = 0, texture = 1, remove = true } end
    return {
        model = math.floor(tonumber(item.model) or 0),
        texture = math.floor(tonumber(item.texture) or 1),
        remove = item.remove == true or (tonumber(item.model) or 0) <= 0
    }
end

local function sameItem(left, right)
    left = normalized(left)
    right = normalized(right)
    return left.model == right.model and left.texture == right.texture and left.remove == right.remove
end

local function getAppearance(citizenid)
    local ok, data = pcall(function()
        return exports['node7-appearance']:GetAppearance(citizenid)
    end)
    if not ok or type(data) ~= 'table' then return { skin = {}, clothes = {} } end
    return data
end

local function validateStoreDistance(src, store)
    if not store or (Config.ServerValidationDistance or 0) <= 0 then return true end
    local ped = GetPlayerPed(src)
    if not ped or ped <= 0 then return false end
    local coords = GetEntityCoords(ped)
    return #(coords - store.coords) <= (Config.ServerValidationDistance or 12.0)
end

local function sanitizeClothes(submitted, saved, gender)
    local merged = clone(saved or {})
    local genderCatalog = catalog and catalog[gender] or nil
    if type(submitted) ~= 'table' or type(genderCatalog) ~= 'table' then return nil, 'Invalid clothing data.' end

    for categoryName, submittedItem in pairs(submitted) do
        local category = categoryByName[categoryName]
        local list = genderCatalog[categoryName]
        if category and type(list) == 'table' and type(submittedItem) == 'table' then
            local item = normalized(submittedItem)

            if item.remove then
                merged[categoryName] = { model = 0, texture = 1, remove = true }
            else
                if item.model < 1 or item.model > #list then
                    return nil, ('Invalid %s model.'):format(category.label)
                end
                local textures = list[item.model]
                if type(textures) ~= 'table' or item.texture < 1 or item.texture > #textures then
                    return nil, ('Invalid %s texture.'):format(category.label)
                end
                merged[categoryName] = {
                    model = item.model,
                    texture = item.texture,
                    remove = false
                }
            end
        end
    end

    return merged
end

local function calculateTotal(saved, merged)
    local total = 0.0
    local count = 0

    for _, category in ipairs(Config.Categories or {}) do
        local before = saved and saved[category.name] or nil
        local after = merged and merged[category.name] or nil
        if not sameItem(before, after) then
            count = count + 1
            local item = normalized(after)
            if Config.ChargeForRemoval or not item.remove then
                total = total + (tonumber(category.price) or 0.0)
            end
        end
    end

    total = math.floor((total * 100) + 0.5) / 100
    return total, count
end

lib.callback.register('node7-clothing:server:purchase', function(source, storeId, submitted)
    local src = source
    if purchaseLocks[src] then
        return { success = false, message = 'A clothing purchase is already processing.' }
    end
    purchaseLocks[src] = true

    local function finish(result)
        purchaseLocks[src] = nil
        return result
    end

    local player = Node7Core.Functions.GetPlayer(src)
    if not player or not player.PlayerData or not player.PlayerData.citizenid then
        return finish({ success = false, message = 'Player data is not loaded.' })
    end

    local store = storeById[tostring(storeId or '')]
    if not store then
        return finish({ success = false, message = 'Invalid clothing store.' })
    end

    if not validateStoreDistance(src, store) then
        return finish({ success = false, message = 'You are too far from the clothing store.' })
    end

    if not loadCatalog() then
        return finish({ success = false, message = 'Clothing catalog is unavailable.' })
    end

    local citizenid = player.PlayerData.citizenid
    local appearance = getAppearance(citizenid)
    local saved = type(appearance.clothes) == 'table' and appearance.clothes or {}
    local skin = type(appearance.skin) == 'table' and appearance.skin or {}
    local gender = tonumber(skin.sex) == 2 and 'female' or 'male'

    local merged, validationError = sanitizeClothes(submitted, saved, gender)
    if not merged then
        return finish({ success = false, message = validationError or 'Invalid clothing selection.' })
    end

    local total, changedCount = calculateTotal(saved, merged)
    if changedCount <= 0 then
        return finish({ success = false, message = 'No clothing changes were selected.' })
    end

    local currency = tostring(Config.Currency or 'cash'):lower()
    if total > 0 then
        local balance = player.Functions.GetMoney(currency)
        if type(balance) ~= 'number' or balance < total then
            return finish({ success = false, message = ('You need $%.2f.'):format(total) })
        end

        if not player.Functions.RemoveMoney(currency, total, ('node7-clothing:%s'):format(store.id)) then
            return finish({ success = false, message = 'Payment failed.' })
        end
    end

    local savedOk, savedResult = pcall(function()
        return exports['node7-appearance']:SaveClothes(citizenid, merged)
    end)

    local persisted = savedOk and savedResult ~= false
    if not persisted then
        if total > 0 then
            player.Functions.AddMoney(currency, total, 'node7-clothing-refund')
        end
        debugLog(savedResult)
        return finish({ success = false, message = 'Clothing could not be saved. Payment was refunded.' })
    end

    return finish({
        success = true,
        clothes = merged,
        total = total,
        changed = changedCount
    })
end)

AddEventHandler('playerDropped', function()
    purchaseLocks[source] = nil
end)

exports('OpenStore', function(source, storeId)
    TriggerClientEvent('node7-clothing:client:open', source, storeId)
end)

CreateThread(function()
    Wait(1000)
    if not loadCatalog() then
        print('[node7-clothing] WARNING: node7-appearance clothing catalog could not be loaded.')
    else
        print(('[node7-clothing] Started with %d configured stores.'):format(#(Config.Stores or {})))
    end
end)
