Node7ClothingConfig = {}
local Config = Node7ClothingConfig

Config.Debug = false

-- Shared QBR-style clothing room used by every tailor.
Config.StaticClothingRoom = vector4(-323.9160, 760.7416, 121.6335, 0.0)

Config.InteractionDistance = 2.0
Config.DrawDistance = 25.0
Config.ShowBlips = true
Config.BlipSprite = 1195729388
Config.BlipScale = 0.20

Config.PaymentMethods = {
    cash = 'Cash',
    bank = 'Bank'
}
Config.ChargeForRemoval = false

-- QBR controls: J opens clothing, ENTER opens saved outfits.
Config.ClothingControl = 0xF3830D8E
Config.OutfitsControl = 0xC7B5340A

-- NODE7 appearance clothing categories. Each category is flattened into the
-- single QBR slider that the original interface expects.
Config.Categories = {
    { name = 'hats', label = 'Hats', price = 8.00 },
    { name = 'masks', label = 'Masks', price = 9.00 },
    { name = 'neckwear', label = 'Neckwear', price = 5.00 },
    { name = 'shirts_full', label = 'Shirts', price = 10.00 },
    { name = 'vests', label = 'Vests', price = 12.00 },
    { name = 'coats', label = 'Coats', price = 18.00 },
    { name = 'coats_closed', label = 'Closed Coats', price = 18.00 },
    { name = 'ponchos', label = 'Ponchos', price = 16.00 },
    { name = 'cloaks', label = 'Cloaks', price = 20.00 },
    { name = 'gloves', label = 'Gloves', price = 6.00 },
    { name = 'pants', label = 'Pants', price = 11.00 },
    { name = 'skirts', label = 'Skirts', price = 11.00 },
    { name = 'chaps', label = 'Chaps', price = 13.00 },
    { name = 'boots', label = 'Boots', price = 12.00 },
    { name = 'spats', label = 'Spats', price = 5.00 },
    { name = 'boot_accessories', label = 'Boot Accessories', price = 6.00 },
    { name = 'belts', label = 'Belts', price = 7.00 },
    { name = 'buckles', label = 'Buckles', price = 7.00 },
    { name = 'gunbelts', label = 'Gunbelts', price = 14.00 },
    { name = 'holsters_left', label = 'Left Holsters', price = 10.00 },
    { name = 'belts_holsters', label = 'Belt Holsters', price = 10.00 },
    { name = 'accessories', label = 'Accessories', price = 7.00 },
    { name = 'jewelry_rings_left', label = 'Left Rings', price = 5.00 },
    { name = 'jewelry_rings_right', label = 'Right Rings', price = 5.00 },
    { name = 'satchels', label = 'Satchels', price = 12.00 },
    { name = 'loadouts', label = 'Loadouts', price = 10.00 }
}

Config.Stores = {
    { name = 'Valentine Clothing Store', location = 'valentine', coords = vector3(-326.10, 774.48, 117.46), showblip = true },
    { name = 'Blackwater Clothing Store', location = 'blackwater', coords = vector3(-766.53, -1293.13, 43.84), showblip = true },
    { name = 'Rhodes Clothing Store', location = 'rhodes', coords = vector3(1324.78, -1292.34, 77.08), showblip = true },
    { name = 'Saint Denis Clothing Store', location = 'saintdenis', coords = vector3(2552.40, -1165.22, 53.73), showblip = true },
    { name = 'Strawberry Clothing Store', location = 'strawberry', coords = vector3(-1793.69, -390.33, 160.26), showblip = true },
    { name = 'Tumbleweed Clothing Store', location = 'tumbleweed', coords = vector3(-5483.24, -2933.42, -0.35), showblip = true },
    { name = 'Armadillo Clothing Store', location = 'armadillo', coords = vector3(-3686.21, -2626.60, -13.38), showblip = true },
    { name = 'Annesburg Clothing Store', location = 'annesburg', coords = vector3(2934.13, 1301.54, 44.48), showblip = true },
    { name = 'Van Horn Clothing Store', location = 'vanhorn', coords = vector3(3026.85, 561.83, 44.72), showblip = true },
    { name = 'Wallace Station Clothing Store', location = 'wallace', coords = vector3(-1295.34, 393.17, 95.38), showblip = true }
}


-- Clothing commands live here exclusively. node7-wardrobe remains outfit-only.
Config.EnableToggleCommands = true
Config.DressCommand = 'dress'
Config.UndressCommand = 'undress'

-- /undress keeps body-critical clothing equipped.
Config.SafeUndressKeep = {
    pants = true,
    boots = true,
    shirts_full = true,
    skirts = true
}

Config.CommandCategories = {
    { command = 'hat',             category = 'hats',                 label = 'Hat' },
    { command = 'shirt',           category = 'shirts_full',          label = 'Shirt' },
    { command = 'pants',           category = 'pants',                label = 'Pants' },
    { command = 'boots',           category = 'boots',                label = 'Boots' },
    { command = 'coat',            category = 'coats',                label = 'Coat' },
    { command = 'closedcoat',      category = 'coats_closed',         label = 'Closed Coat' },
    { command = 'gloves',          category = 'gloves',               label = 'Gloves' },
    { command = 'poncho',          category = 'ponchos',              label = 'Poncho' },
    { command = 'vest',            category = 'vests',                label = 'Vest' },
    { command = 'eyewear',         category = 'eyewear',              label = 'Eyewear' },
    { command = 'belt',            category = 'belts',                label = 'Belt' },
    { command = 'cloak',           category = 'cloaks',               label = 'Cloak' },
    { command = 'chaps',           category = 'chaps',                label = 'Chaps' },
    { command = 'mask',            category = 'masks',                label = 'Mask' },
    { command = 'neckwear',        category = 'neckwear',             label = 'Neckwear' },
    { command = 'accessories',     category = 'accessories',          label = 'Accessories' },
    { command = 'gauntlets',       category = 'gauntlets',            label = 'Gauntlets' },
    { command = 'neckties',        category = 'neckties',             label = 'Neckties' },
    { command = 'loadouts',        category = 'loadouts',             label = 'Loadouts' },
    { command = 'suspenders',      category = 'suspenders',           label = 'Suspenders' },
    { command = 'satchels',        category = 'satchels',             label = 'Satchels' },
    { command = 'gunbelt',         category = 'gunbelts',             label = 'Gunbelt' },
    { command = 'buckle',          category = 'buckles',              label = 'Buckle' },
    { command = 'skirt',           category = 'skirts',               label = 'Skirt' },
    { command = 'armor',           category = 'armor',                label = 'Armor' },
    { command = 'hairaccessories', category = 'hair_accessories',     label = 'Hair Accessory' },
    { command = 'leftring',        category = 'jewelry_rings_left',   label = 'Left Ring' },
    { command = 'rightring',       category = 'jewelry_rings_right',  label = 'Right Ring' },
    { command = 'leftholster',     category = 'holsters_left',        label = 'Left Holster' },
    { command = 'rightholster',    category = 'holsters_right',       label = 'Right Holster' },
    { command = 'bootaccessories', category = 'boot_accessories',     label = 'Boot Accessories' },
    { command = 'spats',           category = 'spats',                label = 'Spats' },
    { command = 'badges',          category = 'badges',               label = 'Badges' },
    { command = 'bracelets',       category = 'jewelry_bracelets',    label = 'Bracelets' },
    { command = 'apron',           category = 'aprons',               label = 'Apron' },
    { command = 'sleeve',          category = 'shirts_full',          label = 'Sleeves', wearable = 'closed_collar_rolled_sleeve' },
    { command = 'collar1',         category = 'shirts_full',          label = 'Open Rolled Collar', wearable = 'open_collar_rolled_sleeve' },
    { command = 'collar2',         category = 'shirts_full',          label = 'Open Full Collar', wearable = 'open_collar_full_sleeve' }
}
