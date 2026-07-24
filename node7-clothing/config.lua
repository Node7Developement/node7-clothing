Node7ClothingConfig = {}

local Config = Node7ClothingConfig

Config.Debug = false
Config.NotifyTitle = 'NODE7 Clothing'
Config.Currency = 'cash'
Config.OpenControl = 0xCEFD9220 -- INPUT_CONTEXT / E
Config.InteractionDistance = 2.15
Config.ServerValidationDistance = 12.0
Config.DrawDistance = 35.0
Config.UseBlips = true
Config.BlipSprite = 1195729388
Config.BlipScale = 0.20
Config.TeleportToEditor = true
Config.FadeDuringEditorMove = true
Config.ChargeForRemoval = false
Config.EnableCommand = true
Config.Command = 'clothingstore'

Config.Camera = {
    distance = 2.15,
    focus = 'full',
    views = {
        full = { label = 'Full Body', cameraZ = 0.85, focusZ = 0.75, distance = 2.65 },
        torso = { label = 'Torso', cameraZ = 1.12, focusZ = 1.05, distance = 2.05 },
        head = { label = 'Head', cameraZ = 1.47, focusZ = 1.45, distance = 1.30 }
    },
    rotateStep = 15.0
}

Config.Interiors = {
    enabled = true,
    loadAtStart = true,
    reloadDelay = 5000
}

Config.Categories = {
    { name = 'hats', label = 'Hats', price = 8.00, icon = 'hat-cowboy' },
    { name = 'masks', label = 'Masks', price = 9.00, icon = 'masks-theater' },
    { name = 'neckwear', label = 'Neckwear', price = 5.00, icon = 'user-tie' },
    { name = 'shirts_full', label = 'Shirts', price = 10.00, icon = 'shirt' },
    { name = 'vests', label = 'Vests', price = 12.00, icon = 'vest' },
    { name = 'coats', label = 'Coats', price = 18.00, icon = 'user' },
    { name = 'coats_closed', label = 'Closed Coats', price = 18.00, icon = 'user' },
    { name = 'ponchos', label = 'Ponchos', price = 16.00, icon = 'user' },
    { name = 'cloaks', label = 'Cloaks', price = 20.00, icon = 'user' },
    { name = 'gloves', label = 'Gloves', price = 6.00, icon = 'mitten' },
    { name = 'pants', label = 'Pants', price = 11.00, icon = 'person' },
    { name = 'skirts', label = 'Skirts', price = 11.00, icon = 'person-dress' },
    { name = 'chaps', label = 'Chaps', price = 13.00, icon = 'person' },
    { name = 'boots', label = 'Boots', price = 12.00, icon = 'shoe-prints' },
    { name = 'spats', label = 'Spats', price = 5.00, icon = 'shoe-prints' },
    { name = 'boot_accessories', label = 'Boot Accessories', price = 6.00, icon = 'shoe-prints' },
    { name = 'belts', label = 'Belts', price = 7.00, icon = 'ring' },
    { name = 'buckles', label = 'Buckles', price = 7.00, icon = 'certificate' },
    { name = 'gunbelts', label = 'Gunbelts', price = 14.00, icon = 'person-rifle' },
    { name = 'holsters_left', label = 'Left Holsters', price = 10.00, icon = 'person-rifle' },
    { name = 'belts_holsters', label = 'Belt Holsters', price = 10.00, icon = 'person-rifle' },
    { name = 'accessories', label = 'Accessories', price = 7.00, icon = 'gem' },
    { name = 'jewelry_rings_left', label = 'Left Rings', price = 5.00, icon = 'ring' },
    { name = 'jewelry_rings_right', label = 'Right Rings', price = 5.00, icon = 'ring' },
    { name = 'satchels', label = 'Satchels', price = 12.00, icon = 'briefcase' },
    { name = 'loadouts', label = 'Loadouts', price = 10.00, icon = 'person-rifle' }
}

-- Store coordinates are fully editable. The first seven use established RedM clothing-store layouts.
-- Annesburg, Van Horn, and Wallace Station are configurable defaults; verify them against your map/MLO.
-- imaps and entitySets are optional and are loaded by client/interiors.lua.
Config.Stores = {
    {
        id = 'valentine', label = 'Valentine Clothing Store',
        coords = vector3(-326.10, 774.48, 117.46),
        editor = vector4(-329.43, 775.29, 121.63, 278.17),
        exit = vector4(-323.12, 774.47, 121.63, 186.42),
        imaps = { 903666582, 637874199 }
    },
    {
        id = 'blackwater', label = 'Blackwater Clothing Store',
        coords = vector3(-766.53, -1293.13, 43.84),
        editor = vector4(-767.98, -1294.88, 43.83, 263.09),
        exit = vector4(-766.53, -1293.13, 43.84, 357.64),
        imaps = {}
    },
    {
        id = 'rhodes', label = 'Rhodes Clothing Store',
        coords = vector3(1324.78, -1292.34, 77.08),
        editor = vector4(1324.24, -1287.88, 77.07, 164.22),
        exit = vector4(1324.78, -1292.34, 77.08, 250.13),
        imaps = {}
    },
    {
        id = 'saintdenis', label = 'Saint Denis Clothing Store',
        coords = vector3(2552.40, -1165.22, 53.73),
        editor = vector4(2556.66, -1159.76, 53.75, 191.14),
        exit = vector4(2553.00, -1161.22, 53.73, 85.61),
        imaps = {}
    },
    {
        id = 'strawberry', label = 'Strawberry Clothing Store',
        coords = vector3(-1793.69, -390.33, 160.26),
        editor = vector4(-1794.40, -395.25, 160.34, 326.06),
        exit = vector4(-1793.69, -390.33, 160.26, 61.55),
        imaps = {}
    },
    {
        id = 'tumbleweed', label = 'Tumbleweed Clothing Store',
        coords = vector3(-5483.24, -2933.42, -0.35),
        editor = vector4(-5480.05, -2932.88, -0.32, 229.49),
        exit = vector4(-5483.36, -2934.59, -0.35, 89.65),
        imaps = {}
    },
    {
        id = 'armadillo', label = 'Armadillo Clothing Store',
        coords = vector3(-3686.21, -2626.60, -13.38),
        editor = vector4(-3688.98, -2630.14, -13.35, 6.45),
        exit = vector4(-3685.82, -2627.58, -13.38, 316.62),
        imaps = {}
    },
    {
        id = 'annesburg', label = 'Annesburg Clothing Store',
        coords = vector3(2934.13, 1301.54, 44.48),
        editor = vector4(2935.25, 1300.45, 44.48, 225.0),
        exit = vector4(2934.13, 1301.54, 44.48, 45.0),
        imaps = {}
    },
    {
        id = 'vanhorn', label = 'Van Horn Clothing Store',
        coords = vector3(3026.85, 561.83, 44.72),
        editor = vector4(3028.15, 561.35, 44.72, 255.0),
        exit = vector4(3026.85, 561.83, 44.72, 75.0),
        imaps = {}
    },
    {
        id = 'wallace', label = 'Wallace Station Clothing Store',
        coords = vector3(-1295.34, 393.17, 95.38),
        editor = vector4(-1297.10, 394.65, 95.38, 160.0),
        exit = vector4(-1295.34, 393.17, 95.38, 340.0),
        imaps = {}
    }
}
