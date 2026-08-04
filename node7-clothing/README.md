# node7-clothing

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

Saved outfits are free to equip, but the server verifies them against the player's actual stored wardrobe before applying them. The resource does not register fallback chat commands.
