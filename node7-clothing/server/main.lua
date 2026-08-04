local Config = Node7ClothingConfig or {}
local Core = exports['node7-core']:GetCoreObject()

local catalog
local purchaseLocks = {}

local PAYMENT_ACCOUNTS = {
    cash = true,
    bank = true
}

local PAYMENT_LABELS = {
    cash = (Config.PaymentMethods and Config.PaymentMethods.cash) or 'Cash',
    bank = (Config.PaymentMethods and Config.PaymentMethods.bank) or 'Bank'
}

local function clone(value)
    if type(value) ~= 'table' then return value end

    local result = {}
    for key, item in pairs(value) do
        result[key] = clone(item)
    end
    return result
end

local function debugLog(message)
    if Config.Debug then
        print(('[node7-clothing:server] %s'):format(tostring(message)))
    end
end

local function getPlayer(source)
    if not Core or not Core.Functions or not Core.Functions.GetPlayer then return nil end
    return Core.Functions.GetPlayer(source)
end

local function notifyPlayer(source, message, notificationType)
    if not Core or not Core.Functions or not Core.Functions.Notify then return end

    Core.Functions.Notify(source, {
        title = 'Tailor',
        description = tostring(message or 'Clothing update.'),
        type = notificationType or 'info',
        duration = 5000
    })
end

local function normalizeName(name)
    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #name > 40 then name = name:sub(1, 40) end
    return name
end

local function loadCatalog()
    if catalog then return true end

    local source = LoadResourceFile('node7-appearance', 'data/clothing.lua')
    if not source or source == '' then
        print('[node7-clothing] ERROR: node7-appearance/data/clothing.lua could not be read.')
        return false
    end

    local chunk, compileError = load(source, '@node7-appearance/data/clothing.lua', 't', {})
    if not chunk then
        print(('[node7-clothing] ERROR: clothing catalog compile failed: %s'):format(tostring(compileError)))
        return false
    end

    local ok, data = pcall(chunk)
    if not ok or type(data) ~= 'table' then
        print(('[node7-clothing] ERROR: clothing catalog load failed: %s'):format(tostring(data)))
        return false
    end

    catalog = data
    return true
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

local function sameClothes(left, right)
    for _, category in ipairs(Config.Categories or {}) do
        if not sameItem(left and left[category.name], right and right[category.name]) then
            return false
        end
    end
    return true
end

local function getAppearance(citizenid)
    if GetResourceState('node7-appearance') ~= 'started' then
        return nil, 'node7-appearance is not started.'
    end

    local ok, appearance = pcall(function()
        return exports['node7-appearance']:GetAppearance(citizenid)
    end)

    if not ok or type(appearance) ~= 'table' then
        debugLog(appearance)
        return nil, 'Appearance data could not be loaded.'
    end

    appearance.skin = type(appearance.skin) == 'table' and appearance.skin or {}
    appearance.clothes = type(appearance.clothes) == 'table' and appearance.clothes or {}
    return appearance
end

local function getOutfits(citizenid)
    if GetResourceState('node7-appearance') ~= 'started' then
        return nil, 'node7-appearance is not started.'
    end

    local ok, outfits = pcall(function()
        return exports['node7-appearance']:GetOutfits(citizenid)
    end)

    if not ok or type(outfits) ~= 'table' then
        debugLog(outfits)
        return nil, 'Saved outfits could not be loaded.'
    end

    return outfits
end

local function saveClothes(citizenid, clothes)
    if GetResourceState('node7-appearance') ~= 'started' then
        return false, 'node7-appearance is not started.'
    end

    local ok, result = pcall(function()
        return exports['node7-appearance']:SaveClothes(citizenid, clothes)
    end)

    if not ok or result == false then
        debugLog(result)
        return false, 'Clothing could not be saved.'
    end

    return true
end

local function resolveGender(source, appearance)
    local skin = appearance.skin or {}
    local gender = tostring(skin.gender or ''):lower()
    local sex = tonumber(skin.sex)

    if gender == 'female' or sex == 2 then
        return 'female'
    end

    local ped = GetPlayerPed(source)
    if ped and ped > 0 and GetEntityModel(ped) == GetHashKey('mp_female') then
        return 'female'
    end

    return 'male'
end

local function sanitizeClothes(submitted, saved, gender)
    local merged = clone(saved or {})
    local genderCatalog = catalog and catalog[gender]

    if type(submitted) ~= 'table' or type(genderCatalog) ~= 'table' then
        return nil, 'Invalid clothing data.'
    end

    for _, category in ipairs(Config.Categories or {}) do
        local categoryName = category.name
        local submittedItem = submitted[categoryName]

        if submittedItem ~= nil then
            if type(submittedItem) ~= 'table' then
                return nil, ('Invalid %s selection.'):format(category.label or categoryName)
            end

            local list = genderCatalog[categoryName]
            if type(list) ~= 'table' then
                return nil, ('%s is unavailable for this character.'):format(category.label or categoryName)
            end

            local item = normalizeItem(submittedItem)
            if item.remove then
                merged[categoryName] = {
                    model = 0,
                    texture = 1,
                    remove = true
                }
            else
                if item.model < 1 or item.model > #list then
                    return nil, ('Invalid %s model.'):format(category.label or categoryName)
                end

                local textures = list[item.model]
                if type(textures) ~= 'table' or item.texture < 1 or item.texture > #textures then
                    return nil, ('Invalid %s texture.'):format(category.label or categoryName)
                end

                local catalogItem = textures[item.texture] or {}
                local hash = tonumber(catalogItem.hash)
                if not hash then
                    return nil, ('Invalid %s clothing entry.'):format(category.label or categoryName)
                end

                merged[categoryName] = {
                    model = item.model,
                    texture = item.texture,
                    hash = hash,
                    remove = false
                }
            end
        end
    end

    return merged
end

local function calculateTotal(saved, merged)
    local total = 0.0
    local changed = 0

    for _, category in ipairs(Config.Categories or {}) do
        local before = saved and saved[category.name]
        local after = merged and merged[category.name]

        if not sameItem(before, after) then
            changed = changed + 1
            local item = normalizeItem(after)

            if Config.ChargeForRemoval == true or not item.remove then
                total = total + math.max(0.0, tonumber(category.price) or 0.0)
            end
        end
    end

    return tonumber(string.format('%.2f', total)), changed
end

local function removePayment(player, account, amount)
    if amount <= 0 then return true end
    if not player or not player.Functions or not player.Functions.RemoveMoney then
        return false, 'money_api_unavailable'
    end

    return player.Functions.RemoveMoney(account, amount, 'node7-clothing:purchase')
end

local function refundPayment(player, account, amount)
    if amount <= 0 then return true end
    if not player or not player.Functions or not player.Functions.AddMoney then
        return false, 'money_api_unavailable'
    end

    return player.Functions.AddMoney(account, amount, 'node7-clothing:refund')
end

local function paymentErrorMessage(account, amount, reason)
    local label = account == 'bank' and 'bank funds' or 'cash'

    if reason == 'insufficient_funds' or reason == 'minus_limit' then
        return ('Not enough %s. You need $%.2f.'):format(label, amount)
    end

    if reason == 'cashitem_not_started' or reason == 'cashitem_export_failed' then
        return 'Cash payments are currently unavailable.'
    end

    if reason == 'invalid_money_type' then
        return 'That payment method is unavailable.'
    end

    return 'Payment could not be processed.'
end

local function persistOutfit(citizenid, name, clothes)
    name = normalizeName(name)
    if name == '' then return true end

    local ok, err = pcall(function()
        MySQL.query.await([[
            INSERT INTO `player_clothing_outfits` (`citizenid`, `name`, `clothing`)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `clothing` = VALUES(`clothing`),
                `updated_at` = CURRENT_TIMESTAMP
        ]], { citizenid, name, json.encode(clothes) })
    end)

    if not ok then debugLog(err) end
    return ok
end

local function sendPurchaseResult(source, requestId, result)
    TriggerClientEvent(
        'node7-clothing:client:purchaseResult',
        source,
        tostring(requestId or ''),
        result
    )
end

local function sendOutfitResult(source, requestId, result)
    TriggerClientEvent(
        'node7-clothing:client:outfitActionResult',
        source,
        tostring(requestId or ''),
        result
    )
end

local function finishPurchase(source, requestId, result)
    purchaseLocks[source] = nil
    sendPurchaseResult(source, requestId, result)
    notifyPlayer(source, result.message, result.success and 'success' or (result.notificationType or 'error'))
end

local function processPurchase(source, paymentMethod, submitted, outfitName)
    local method = tostring(paymentMethod or ''):lower()
    if not PAYMENT_ACCOUNTS[method] then
        return { success = false, message = 'Choose Cash or Bank.' }
    end

    local player = getPlayer(source)
    if not player or not player.PlayerData or not player.PlayerData.citizenid then
        return { success = false, message = 'Player data is not loaded.' }
    end

    if not loadCatalog() then
        return { success = false, message = 'Clothing catalog is unavailable.' }
    end

    local normalizedOutfitName = normalizeName(outfitName)
    if normalizedOutfitName ~= '' and #normalizedOutfitName < 2 then
        return { success = false, message = 'Enter an outfit name.' }
    end

    local citizenid = player.PlayerData.citizenid
    local appearance, appearanceError = getAppearance(citizenid)
    if not appearance then
        return { success = false, message = appearanceError }
    end

    local merged, validationError = sanitizeClothes(
        submitted,
        appearance.clothes,
        resolveGender(source, appearance)
    )

    if not merged then
        return { success = false, message = validationError or 'Invalid clothing selection.' }
    end

    local total, changed = calculateTotal(appearance.clothes, merged)
    if changed <= 0 then
        return {
            success = false,
            message = 'No clothing changes were selected.',
            notificationType = 'info'
        }
    end

    local paid = false
    if total > 0 then
        local paymentOk, paymentResult = removePayment(player, method, total)
        if not paymentOk then
            return {
                success = false,
                message = paymentErrorMessage(method, total, paymentResult)
            }
        end
        paid = true
    end

    local savedOk = saveClothes(citizenid, merged)
    if not savedOk then
        if paid then
            local refundOk = refundPayment(player, method, total)
            if refundOk then
                return {
                    success = false,
                    message = 'Clothing could not be saved. Your payment was refunded.'
                }
            end

            return {
                success = false,
                message = 'Clothing could not be saved and the automatic refund failed. Contact server staff.'
            }
        end

        return { success = false, message = 'Clothing could not be saved.' }
    end

    local outfitSaved = persistOutfit(citizenid, normalizedOutfitName, merged)
    local paymentLabel = tostring(PAYMENT_LABELS[method])
    local message

    if total > 0 then
        message = ('$%.2f paid from %s for %d clothing change%s.'):format(
            total,
            paymentLabel,
            changed,
            changed == 1 and '' or 's'
        )
    else
        message = ('%d clothing change%s saved at no charge.'):format(
            changed,
            changed == 1 and '' or 's'
        )
    end

    if normalizedOutfitName ~= '' and not outfitSaved then
        message = message .. ' The outfit name could not be saved.'
    end

    return {
        success = true,
        clothes = merged,
        total = total,
        paymentMethod = method,
        changed = changed,
        outfitSaved = outfitSaved,
        message = message
    }
end

RegisterNetEvent('node7-clothing:server:getOutfits', function(requestId)
    local src = source
    local player = getPlayer(src)
    local response = {}

    if player and player.PlayerData and player.PlayerData.citizenid then
        local outfits = getOutfits(player.PlayerData.citizenid)
        if outfits then
            for _, outfit in ipairs(outfits) do
                if type(outfit.clothing) == 'table' then
                    response[#response + 1] = {
                        outfitname = outfit.name or ('Outfit ' .. tostring(outfit.id or '')),
                        outfitId = outfit.id,
                        skin = outfit.clothing
                    }
                end
            end
        end
    end

    TriggerClientEvent('node7-clothing:client:outfitsResponse', src, requestId, response)
end)

RegisterNetEvent('node7-clothing:server:useOutfit', function(requestId, submittedClothes)
    local src = source
    local player = getPlayer(src)

    if not player or not player.PlayerData or not player.PlayerData.citizenid then
        local result = { success = false, message = 'Player data is not loaded.' }
        sendOutfitResult(src, requestId, result)
        notifyPlayer(src, result.message, 'error')
        return
    end

    local outfits, outfitsError = getOutfits(player.PlayerData.citizenid)
    if not outfits then
        local result = { success = false, message = outfitsError }
        sendOutfitResult(src, requestId, result)
        notifyPlayer(src, result.message, 'error')
        return
    end

    local selected
    for _, outfit in ipairs(outfits) do
        if type(outfit.clothing) == 'table' and sameClothes(outfit.clothing, submittedClothes) then
            selected = clone(outfit.clothing)
            break
        end
    end

    if not selected then
        local result = { success = false, message = 'That saved outfit could not be verified.' }
        sendOutfitResult(src, requestId, result)
        notifyPlayer(src, result.message, 'error')
        return
    end

    local savedOk = saveClothes(player.PlayerData.citizenid, selected)
    local result

    if savedOk then
        result = {
            success = true,
            clothes = selected,
            message = 'Saved outfit equipped.'
        }
    else
        result = { success = false, message = 'The saved outfit could not be equipped.' }
    end

    sendOutfitResult(src, requestId, result)
    notifyPlayer(src, result.message, result.success and 'success' or 'error')
end)

RegisterNetEvent('node7-clothing:server:saveCurrentOutfit', function(requestId, outfitName)
    local src = source
    local player = getPlayer(src)
    local name = normalizeName(outfitName)

    if not player or not player.PlayerData or not player.PlayerData.citizenid then
        local result = { success = false, message = 'Player data is not loaded.' }
        sendOutfitResult(src, requestId, result)
        notifyPlayer(src, result.message, 'error')
        return
    end

    if #name < 2 then
        local result = { success = false, message = 'Enter an outfit name.' }
        sendOutfitResult(src, requestId, result)
        notifyPlayer(src, result.message, 'error')
        return
    end

    local appearance, appearanceError = getAppearance(player.PlayerData.citizenid)
    if not appearance then
        local result = { success = false, message = appearanceError }
        sendOutfitResult(src, requestId, result)
        notifyPlayer(src, result.message, 'error')
        return
    end

    local saved = persistOutfit(player.PlayerData.citizenid, name, appearance.clothes)
    local result = {
        success = saved,
        clothes = saved and appearance.clothes or nil,
        message = saved and ('Outfit "%s" saved.'):format(name) or 'The outfit could not be saved.'
    }

    sendOutfitResult(src, requestId, result)
    notifyPlayer(src, result.message, saved and 'success' or 'error')
end)

RegisterNetEvent('node7-clothing:server:purchase', function(requestId, paymentMethod, submitted, outfitName)
    local src = source

    if purchaseLocks[src] then
        local result = {
            success = false,
            message = 'A clothing purchase is already processing.'
        }
        sendPurchaseResult(src, requestId, result)
        notifyPlayer(src, result.message, 'error')
        return
    end

    purchaseLocks[src] = true

    local ok, result = xpcall(function()
        return processPurchase(src, paymentMethod, submitted, outfitName)
    end, debug.traceback)

    if not ok then
        print(('[node7-clothing] ERROR: purchase failed for player %s: %s'):format(src, tostring(result)))
        result = {
            success = false,
            message = 'The tailor could not process this purchase.'
        }
    end

    finishPurchase(src, requestId, result)
end)

AddEventHandler('playerDropped', function()
    purchaseLocks[source] = nil
end)
