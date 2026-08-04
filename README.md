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
