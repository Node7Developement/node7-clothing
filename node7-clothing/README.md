# node7-clothing

Separate RedM clothing-shop resource for:

- `node7-core`
- `node7-appearance`
- `node7-wardrobe`
- `ox_lib`

## Included

- 10 configured clothing stores
- ox_lib context menus and input dialogs
- live clothing previews using the existing `node7-appearance` catalog
- full-body, torso, and head camera views
- character rotation while editing
- server-side store-distance, model, texture, price, and cash validation
- citizenid persistence through `node7-appearance`
- rollback on cancel or menu exit
- `node7-wardrobe` outfit access
- configurable IMap and interior entity-set loading
- map blips and nearby text interaction

## Install order

```cfg
ensure ox_lib
ensure oxmysql
ensure node7-core
ensure node7-appearance
ensure node7-wardrobe
ensure node7-clothing
```

## Important: disable the old appearance shop points

Your current `node7-appearance/config.lua` still contains its own `Node7AppearanceConfig.Shops` list. Empty that list so only this separate resource handles physical clothing stores:

```lua
Node7AppearanceConfig.Shops = {}
```

Do not remove `node7-appearance`; this resource uses its clothing data, apply exports, and persistence.

## Usage

Walk to a configured store and press `E`.

Fallback command near a store:

```text
/clothingstore
```

## Store-coordinate note

The Valentine, Blackwater, Rhodes, Saint Denis, Strawberry, Tumbleweed, and Armadillo editor points use established RedM clothing-shop layouts. Annesburg, Van Horn, and Wallace Station are enabled as configurable general-store placements; verify those three points against your server map or MLO and adjust `coords`, `editor`, and `exit` in `config.lua` when needed.

## Configuration

Edit `config.lua` to change:

- all 10 store positions
- editor and exit positions
- category prices
- cash account
- interaction and server-validation distance
- blip settings
- camera views
- IMaps and interior entity sets

Example entity-set configuration on a store:

```lua
entitySets = {
    {
        coords = vector3(323.0087, 801.0296, 116.8817),
        sets = { 'val_genstore_night_light' }
    }
}
```

## Exports

Client:

```lua
exports['node7-clothing']:OpenStore('valentine')
exports['node7-clothing']:CloseStore(false)
local store, distance = exports['node7-clothing']:GetNearestStore(20.0)
local shopping = exports['node7-clothing']:IsShopping()
```

Server:

```lua
exports['node7-clothing']:OpenStore(source, 'valentine')
```
