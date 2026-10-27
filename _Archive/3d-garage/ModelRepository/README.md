# LOT 3D car repository

LOT shows a 3D car in the Garage. Models come from a **repository**: a JSON manifest plus the files it points to.
LOT ships with a small built-in repository (`CACPROJECTYEAHH/ModelLibrary`, the CC0 Kenney Car Kit). You can add an
online repository so new cars appear in the app without an app update: put the files on any static HTTPS host
(GitHub Pages works well), then paste the manifest link into Settings → 3D car library.

## Manifest format (`lot-library-manifest.json`)

```json
{
  "version": 1,
  "name": "My school's cars",
  "models": [
    {
      "id": "honda-civic-2006-2011",
      "name": "Honda Civic (8th gen)",
      "bodyStyle": "sedan",
      "make": "Honda",
      "model": "Civic",
      "yearFrom": 2006,
      "yearTo": 2011,
      "file": "models/honda-civic.usdz",
      "texture": null,
      "paintRegions": null,
      "sizeBytes": 4200000,
      "sha256": "<sha-256 of the .usdz, lowercase hex>",
      "license": "CC-BY 4.0",
      "author": "Model author's name",
      "sourceURL": "https://where-you-got-it",
      "attributionRequired": true
    }
  ]
}
```

- `file` and `texture` are relative to the manifest's URL. They must be `https`.
- `bodyStyle` is one of `sedan`, `hatchback`, `suv`, `pickup`, `coupe`, `van`.
- Leave `make` and `model` empty for a generic model of that body type.
- Matching: LOT prefers an entry whose make and model match the car (and whose year range includes it), then falls back
  to generic models of the same body type. Common model names (Civic, CR-V, Tacoma...) map to a body type automatically.
- `sha256` is optional but recommended. LOT rejects a download whose hash doesn't match, and anything over 60 MB.
- `paintRegions` (`[[x, y, w, h], ...]` in texture pixels) is only for palette-textured models like the Kenney kit,
  where the body paint is a block of the shared palette. Leave it `null` for normal textured models, which show as made.

## Adding a car

1. Get a model you have the right to use (see below) as `.usdz`. `.glb`/`.obj` can be converted with Apple's Reality
   Converter, or with `Tools/convert_model.swift` for OBJ.
2. Keep it small (a few MB). Phones don't need 500k-polygon showroom models.
3. Add the file to the repository, add an entry to the manifest (with `sha256`: `shasum -a 256 file.usdz`), push.
4. Open the app. It refreshes the manifest on launch and downloads a model the first time a car uses it.

## Licensing rules (please follow these)

- Only host models whose license lets you redistribute them: CC0, or CC-BY with the author credited
  (LOT shows `author` and `license` under every model it displays).
- Don't redistribute models you only have a personal or "free download" license for, and don't rip models from games.
- Car makes and models are trademarks and many detailed car models are copyrighted by the artist. A model of a
  specific car is fine only when its license allows your use.

## Generic vs exact models

The built-in kit is generic: a sedan, a hatchback, an SUV and so on, repainted in the car's color. It is not an exact
copy of a particular make and model. Exact models come from whatever you add to a repository.

## Rebuilding the built-in set

`Tools/build_library.py` converts the Kenney OBJ files to `.usdz`, finds each model's paint region, and writes the
manifest. It needs Python with Pillow, plus `Tools/convert_model.swift` compiled with `swiftc`.

## Not built: Sketchfab search

Sketchfab has a very large library with a download API that returns `.usdz`, but each user must sign in to their own
Sketchfab account through OAuth, and the team must register an OAuth app. Most models there are CC-BY and need
attribution. It's a good next step if you want to search by make and model inside the app.
