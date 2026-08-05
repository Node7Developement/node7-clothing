[README.md](https://github.com/user-attachments/files/30730048/README.md)
[README.md](https://github.com/user-attachments/files/30713560/README.md)
# node7-clothing











<img width="1602" height="1074" alt="clothingupdateeeeeeeee" src="https://github.com/user-attachments/assets/d9ce29e2-5e21-4216-8734-6792df0b648c" />


<img width="1920" height="1080" alt="clothingscript" src="https://github.com/user-attachments/assets/6388ab14-49ca-4e7e-aa46-027bf8845afc" />

Node7 Clothing Script Replicated off of QBR CLothing and updated to work with cash and bank payments with confirmation! clothing and outfit interface connected directly to `node7-core` and `node7-appearance`.

## Dependencies

- node7-core
- node7-appearance
- oxmysql

## Start order

```cfg
ensure oxmysql
ensure node7-core# node7-clothing

QBR-format RedM clothing and outfit interface connected directly to `node7-core` and `node7-appearance`.

## Dependencies

- node7-core
- node7-appearance
- oxmysql

## Start order

```cfg
ensure oxmysql
ensure node7-core
ensure node7-appearance
ensure node7-clothing
```

At a configured tailor:

- `J` opens Clothing Customization.
- `ENTER` opens saved outfits from the NODE7 appearance wardrobe.

## Payments

Clothing customization checkout supports **Cash** and **Bank**. Prices are configured per category in `shared/config.lua`.

Payments are validated and removed server-side through the native `node7-core` player money functions. Failed appearance saves automatically attempt to refund the same account. Purchase results use the built-in NODE7 notification UI.

Saved outfits are free to equip, but the server verifies them against the player's actual stored wardrobe before applying them. Wearable commands are registered directly by `node7-clothing`; `node7-wardrobe` remains outfit-only.

## Barber compatibility

Clothing component changes are applied in one native batch and then signal `node7-barbers` to restore its saved hair, beard, eyebrow, eye, and facial state. Masks, bandanas, outfits, and wardrobe changes therefore no longer remove barber customization. `node7-barbers` remains optional and is not a hard dependency.


## Clothing commands

Temporary clothing controls now live exclusively in this resource. Available commands include `/hat`, `/shirt`, `/pants`, `/boots`, `/coat`, `/closedcoat`, `/gloves`, `/poncho`, `/vest`, `/eyewear`, `/belt`, `/cloak`, `/chaps`, `/mask`, `/neckwear`, `/accessories`, `/gauntlets`, `/neckties`, `/loadouts`, `/suspenders`, `/satchels`, `/gunbelt`, `/buckle`, `/skirt`, `/armor`, `/hairaccessories`, `/leftring`, `/rightring`, `/leftholster`, `/rightholster`, `/bootaccessories`, `/spats`, `/badges`, `/bracelets`, `/apron`, `/sleeve`, `/collar1`, and `/collar2`.

`/undress` temporarily removes safe outer clothing and `/dress` restores those hidden pieces. `/neckwear` remains the general neckwear toggle, including equipped bandanas.


## 2.4.0 beard-safe face coverings
- Face-covering clothing uses the dedicated shop-item removal native instead of rebuilding the full MetaPed head.
- Face-covering toggles restore only the purchased beard through `node7-barbers`.
- Corrected RedM shop-item apply flags.


## 2.4.2 mask-off player load
- Saved masks are removed from the live ped after character appearance finishes loading.
- The purchased/saved mask is kept available for `/mask`; it is not deleted from wardrobe or appearance data.
- No other clothing category is changed during player load.

ensure node7-appearance
ensure node7-clothing
```

At a configured tailor:

- `J` opens Clothing Customization.
- `ENTER` opens saved outfits from the NODE7 appearance wardrobe.

## Payments

Clothing customization checkout supports **Cash** and **Bank**. Prices are configured per category in `shared/config.lua`.

Payments are validated and removed server-side through the native `node7-core` player money functions. Failed appearance saves automatically attempt to refund the same account. Purchase results use the built-in NODE7 notification UI.

Saved outfits are free to equip, but the server verifies them against the player's actual stored wardrobe before applying them. The resource does not register fallback chat commands.
