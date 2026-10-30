# NX Ports Catalog

A Catalog for [Frontport](https://github.com/svich/frontport), the macOS app that installs and runs sandboxed Ports: Mac versions of Nintendo Switch games built from source by [nxnative](https://github.com/seedds/nxnative) and [MacNativeGames](https://github.com/ly05010419/MacNativeGames).

| Project | Games |
|---|---|
| nxnative | Super Mario Bros. Wonder, Tears of the Kingdom, Fire Emblem: Three Houses, Link’s Awakening |
| MacNativeGames | Tears of the Kingdom |

## Adding it to Frontport

In Frontport, choose **Settings › Catalogs › Add…** and paste:

```
https://raw.githubusercontent.com/nx-ports/nx-ports-catalog/main/
```

Frontport reads the Catalog's public key from `catalog.pub` and shows its fingerprint before you add it. It should be:

```
014a efc4 f913 b390 b7a7 6e23 1070 fc12
```

From then on, Frontport accepts only versions of this Catalog signed with that key.

## Bring your own games

This Catalog includes no games and downloads none: no game files, firmware or console keys. Each Port needs your own copy of its game, your own console keys and, for MacNativeGames, your own firmware, all dumped from your own Switch, which you add to Frontport yourself. The Ports' Recipes decrypt them only on your Mac, inside Frontport's build sandbox, with the pinned upstream tools hactool and nsz.

Neither Frontport nor this Catalog is affiliated with Nintendo or with the Projects whose Ports it lists. Nintendo Switch and the games' names are trademarks of Nintendo.

## Files

| File | What it is |
|---|---|
| `catalog.json` | The Catalog, in Frontport's format (see Frontport's [`catalog/README.md`](https://github.com/svich/frontport/blob/main/catalog/README.md)) |
| `catalog.json.sig` | Base64 Ed25519 signature over the exact bytes of `catalog.json`, then a newline |
| `catalog.pub` | The public key the Catalog is signed with, base64 |
| `recipes/nxnative.sh`, `recipes/macnativegames.sh` | The Recipes that build the Ports, each pinned by a `recipeSHA256` in `catalog.json` |

## Changing the Catalog

Every change to `catalog.json` or a Recipe needs a new signature, and `issued` bumped. From Frontport's `FrontportKit` folder:

```sh
swift run frontport-catalog sign --key ../../nx-ports-catalog/switch.key --update-recipe-hashes ../../nx-ports-catalog/catalog.json
swift run frontport-catalog verify --public-key "$(cat ../../nx-ports-catalog/catalog.pub)" ../../nx-ports-catalog/catalog.json
```

`switch.key`, the private key, is gitignored and never committed.

To build a Recipe outside Frontport, from Frontport's `FrontportKit` folder:

```sh
FRONTPORT_NETWORK_TESTS=1 FRONTPORT_RECIPE=nxnative FRONTPORT_RECIPE_PORT=nxnative-totk \
FRONTPORT_RECIPE_FILE=../../nx-ports-catalog/recipes/nxnative.sh \
FRONTPORT_RECIPE_REF=6a0687721a1da9a6a0273c6ce2f11eedcf4af445 \
FRONTPORT_RECIPE_ROMS=/path/game.nsp,/path/update.nsp,/path/prod.keys swift test --filter RecipeIntegrationTests
```

MacNativeGames' Recipe is `macnativegames`, at `4b3fc724f9c84fa7273dee4016932c820d9e9b19`.

## Sources

Every fact below was read from the upstream repositories with `gh` in October 2026. Links are pinned to the commit they describe.

### ROM hashes

| Game | ROMs | Source |
|---|---|---|
| Super Mario Bros. Wonder | 1.0.0 from a game card (as an NSP) and from the eShop, and the 1.2.1 update, as `.nsp` | The game card base is a dump's; its NCAs match their content IDs. The eShop base and the update: content IDs from [blawar/titledb `cnmts.json`](https://github.com/blawar/titledb/blob/master/cnmts.json) (`010015100b514000` version `0`, `010015100b514800` version `327680`). Its program's build IDs there, `cd6e42ae…` and `ff773e90…`, are the `main` builds nxnative's profile registers ([`game.tsv`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/dm/games/010015100B514000/game.tsv)). The update matches the dump |
| Tears of the Kingdom | 1.0.0 from a game card (as an NSP) and from the eShop, and the 1.4.3 update, as `.nsp` | The game card base and the update are the dumps the Recipe was tested with. The eShop base and the update are in titledb (`0100f2c0115b6000` version `0`, `0100f2c0115b6800` version `720896`): the update's content IDs and program build `277178b7…` match the dump and nxnative's [profile](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/dm/games/0100F2C0115B6000/game.tsv) |
| Fire Emblem: Three Houses | 1.0.0 from a game card (as an NSP) and from the eShop, the 1.2.0 update, and six DLC, as `.nsp` | The game card base's hash is its NCAs' as on the card: the dump it was taken from, which a converter had marked as downloaded, was put back by a version of Frontport that still did that ([ADR 0006](https://github.com/svich/frontport/blob/main/docs/adr/0006-identify-switch-files-by-content.md)). A converted dump is now kept Unverified ([ADR 0011](https://github.com/svich/frontport/blob/main/docs/adr/0011-keep-unlisted-files-unverified.md)). The eShop base, the update and the DLC are in titledb (`010055d009f78000` version `0`, `010055d009f78800` version `327680`, `010055d009f79001`–`79006` at versions `196608` and `262144`): the update's program build `89048449…` is the `main` nxnative's [profile](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/dm/games/010055D009F78000/game.tsv) registers, and the update and every DLC match the dumps the Port was tested with |
| Link's Awakening | 1.0.0 from the eShop and the 1.1.0 update, as `.nsp` (an `.nsz` is kept Unverified) | Content IDs from titledb's `cnmts.json` (`01006bb00c6f0000` version `0`, `01006bb00c6f0800` version `131072`). The update's program build `909e904a…` is the `main` build nxnative's [profile](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/dm/games/01006BB00C6F0000/game.tsv) registers (1.0.1, `65536`, has the same `main` but isn't the profile's version). Both match the NSZ dumps the Port was tested with |
| Switch console keys | Through `master_key_15`, then one fewer each down to `master_key_0a` (newest first: a Requirement accepts them from the newest on, without a gap) | The standard forms of a `prod.keys` dumped from firmware 22.5.0. Each version's `requiredSystemVersion` in titledb names the newest master key it may need: Wonder 1.2.1 needs 22.1.0 (`master_key_15`), Tears of the Kingdom 1.4.3 21.2.0 (`master_key_14`), Three Houses 1.2.0 9.1.0 (`master_key_0a`), Link's Awakening 1.1.0 20.0.1 (`master_key_13`). Firmware versions per master key are Atmosphère's [`pkg1_key_generation.hpp`](https://github.com/Atmosphere-NX/Atmosphere/blob/master/libraries/libexosphere/include/exosphere/pkg1/pkg1_key_generation.hpp) |
| Switch firmware | 22.5.0, as its folder of NCAs ([ADR 0007](https://github.com/svich/frontport/blob/main/docs/adr/0007-take-a-pc-game-as-a-folder.md)) | The firmware dump the Port was tested with: 238 NCAs, named by content ID, meta NCAs as `.cnmt.nca`. An NSP holds no system fonts, so MacNativeGames takes the six shared fonts from a firmware ([`extract_shared_fonts.py`](https://github.com/ly05010419/MacNativeGames/blob/4b3fc724f9c84fa7273dee4016932c820d9e9b19/games/totk/scripts/extract_shared_fonts.py)) and binds the game to their bytes: the reference dump's pass its pinned hashes, another firmware's pass as valid BFTTF fonts ([`build_app.py`](https://github.com/ly05010419/MacNativeGames/blob/4b3fc724f9c84fa7273dee4016932c820d9e9b19/build_app.py#L468-L486)) |

Switch files are identified by content ([ADR 0006](https://github.com/svich/frontport/blob/main/docs/adr/0006-identify-switch-files-by-content.md)): an NSP's or XCI's hash is the SHA-1 of its NCAs' sorted content IDs but the meta NCA's, one per line, and console keys are reduced to the keys every console shares. Nothing is decrypted: an NSZ or XCZ, or a dump a tool made from an XCI, gets a hash no ROM in the Catalog has, and is kept Unverified as the ROM the user chooses ([ADR 0011](https://github.com/svich/frontport/blob/main/docs/adr/0011-keep-unlisted-files-unverified.md)), so the Catalog lists each version once, as `nsp` or `xci`. `FRONTPORT_SWITCH_FILES=<file>,… swift test --filter SwitchFileHashes` in `FrontportKit` prints them for real files (never a key's value).

### Ports

| Port | Releases | Where the ROM goes (relative to Data) | Code-signing exceptions | Sources |
|---|---|---|---|---|
| nxnative-wonder | Source build of commit `6a06877` (2026-10-25). Upstream has no Releases and no Mac app: its Mac host, `dmhost`, is for development, run from files its NSP script prepares | Build Stage: the base game, the 1.2.1 update and the console keys. The Recipe runs [`build_ipa_from_nsp.py --platform mac`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/docs/development.md#a-mac-only-build-for-development) and leaves its RomFS, rewritten modules, Metal shader libraries and shader tables at `Contents/Resources/game`. The app's one executable is `dmhost` built again with `-Dmain=dmhost_main` ([`main.c`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/dm/host/main.c#L124) holds the host's only `main`) and linked with a launcher as `main`, which sets the host's paths ([`hle_fs.c`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/dm/host/hle_fs.c#L1-L5)), with saves in `Library/Application Support/nxnative` in the container. A launcher that execs `dmhost` doesn't work: Frontport signs it with `inherit`, and AppKit then aborts its check-in | `allow-unsigned-executable-memory`: the loader maps the rewritten code writable, then executable ([`loader.c`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/dm/host/loader.c#L538-L556)) | [README](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/README.md), [`docs/development.md`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/docs/development.md) (on the Mac, Wonder's menu and dialogue text render blank) |
| nxnative-totk | The same source build, from the same Recipe | Build Stage: the base game, the 1.4.3 update and the console keys, as Wonder's | `allow-unsigned-executable-memory` | [`docs/development.md`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/docs/development.md) (60 fps through its frame step) |
| nxnative-three-houses | The same source build, from the same Recipe | Build Stage: the base game, the 1.2.0 update and the console keys, and its DLC as extras, which the NSP script extracts to `aoc/` in the Build Assets; the launcher then sets `DM_AOC_DIR`, without which a save made with DLC stops at a "DLC deleted" dialog. The NSP script boots the game headless in the Mac host it builds, to capture the 9 shaders the game compiles as it starts ([`docs/development.md`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/docs/development.md)), so the build sandbox grants the GPU | `allow-unsigned-executable-memory` | [Game notes](https://github.com/seedds/nxnative/blob/846c54c63ca85667dca0900610ed18117ed79d83/dm/games/010055D009F78000/README.md) (60 fps through rewriter cuts of 1.2.0's `main`), [README](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/README.md) (small square patches where decals land) |
| nxnative-links-awakening | The same source build, from the same Recipe | Build Stage: the base game, the 1.1.0 update and the console keys, as Wonder's. An NSZ is made into an NSP first, by nsz's own decompressor, in `Builds/<port>/unpacked` | `allow-unsigned-executable-memory` | [`game.tsv`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/dm/games/01006BB00C6F0000/game.tsv) and [`patches.py`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/dm/games/01006BB00C6F0000/patches.py) (the physics fix), [`docs/development.md`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/docs/development.md) (the title wants L+R), [`front_mac.m`](https://github.com/seedds/nxnative/blob/6a0687721a1da9a6a0273c6ce2f11eedcf4af445/dm/host/front_mac.m#L4) (Q is L, E is R) |
| macnativegames-totk | Source build of commit `4b3fc72` (2026-10-25). Upstream's Releases are source snapshots: its [`build_app.py`](https://github.com/ly05010419/MacNativeGames/blob/4b3fc724f9c84fa7273dee4016932c820d9e9b19/build_app.py) makes the app on the user's Mac from their files | Build Stage: the base game, the 1.4.3 update, the console keys and a firmware. The Recipe runs `build_app.py`'s steps from its own functions, then leaves the game folder upstream keeps at `Contents/Resources/totk` (rewritten code modules, the merged RomFS image and its overlays, the shared fonts, the startup shaders and their Metal libraries) as the Build Assets. Saves, the shader cache and settings go to `Library/Application Support/MacNativeGames/TOTK` in the container. Upstream's launcher [`execv`s](https://github.com/ly05010419/MacNativeGames/blob/4b3fc724f9c84fa7273dee4016932c820d9e9b19/games/totk/app/launcher.m#L255) the game, a second program, as nxnative's did, so the Recipe links the game into it with its `main` renamed; it compiles the game with `_NSGetExecutablePath` answering upstream's path, which the game finds its files from ([`totk_shader_rt.m`](https://github.com/ly05010419/MacNativeGames/blob/4b3fc724f9c84fa7273dee4016932c820d9e9b19/games/totk/third_party/d2r_gfx/gfx/nvn/totk_shader_rt.m#L56-L61)), and puts spirv-cross and the shader translator, which the game starts, in `Contents/Helpers`, since the sandbox runs programs only from inside the app | `allow-unsigned-executable-memory`: the loader maps the rewritten modules writable, then makes their code executable ([`loader.c`](https://github.com/ly05010419/MacNativeGames/blob/4b3fc724f9c84fa7273dee4016932c820d9e9b19/games/totk/runtime/loader.c#L252-L264)) | [`docs/install.md`](https://github.com/ly05010419/MacNativeGames/blob/4b3fc724f9c84fa7273dee4016932c820d9e9b19/docs/install.md) (versions, controls, the settings panel, known issues), [`docs/how-it-works.md`](https://github.com/ly05010419/MacNativeGames/blob/4b3fc724f9c84fa7273dee4016932c820d9e9b19/docs/how-it-works.md) |

nxnative has no Mac app to mirror, and MacNativeGames' app is signed ad-hoc on the user's Mac, without the hardened runtime. Both need `allow-unsigned-executable-memory`, as OpenGOAL does in Frontport's Catalog: `dmhost` and MacNativeGames' loader copy the rewritten modules into memory they then make executable.

### First Releases

`firstRelease` is the publish date of upstream's oldest non-draft GitHub Release, or, without one, of the commit noted.

| Port | First Release |
|---|---|
| nxnative-wonder | No GitHub Releases: [`d1b1708`](https://github.com/seedds/nxnative/commit/d1b17080), 2026-10-12, the first commit, which boots Mario Wonder on the Mac host |
| nxnative-totk | No GitHub Releases: the commit adding its game profile, 2026-10-18, "Tears of the Kingdom reaches gameplay on the Mac" |
| nxnative-three-houses | No GitHub Releases: [`8b21049`](https://github.com/seedds/nxnative/commit/8b21049), the commit adding its game profile, 2026-10-18, "Age of Calamity and Three Houses play on the Mac" |
| nxnative-links-awakening | No GitHub Releases: [`e734ced`](https://github.com/seedds/nxnative/commit/e734ced), 2026-10-17, which adds its game profile: "Zelda Link's Awakening runs on the Mac" |
| macnativegames-totk | [`v2026.10.25`](https://github.com/ly05010419/MacNativeGames/releases/tag/v2026.10.25), 2026-10-25, its first, a source snapshot |

### Choices made

- **nxnative:** one Port per game, `nxnative-wonder`, `nxnative-totk`, `nxnative-three-houses` and `nxnative-links-awakening`, built by `nxnative.sh`, which takes the game from the Port id. Each accepts only the version upstream brought its game up on, so the Recipe never builds from a profile nxnative derives for another version: that profile's host would no longer match Build Assets made again later. An Unverified game file can be any version, so before the long steps the Recipe reads each one's content meta (title ID, version and kind, from its meta NCA, which hactool decrypts) and stops unless it's the base game, the update the game profile packs, or the game's DLC. `buildAssets.format` is the nxnative commit, since code rewritten by one commit runs only in that commit's host, so every new pin makes the Build Assets again; the launcher refuses Build Assets stamped with another commit. Settings go in `Library/Application Support/nxnative/env.txt` in the container, one `DM_…=value` per line, as `Documents/env.txt` on an iPhone. Each shows its Game's artwork, since SteamGridDB has no entry for nxnative. Three Houses takes its DLC as extras of the base game: a Requirement can't be optional, and the game plays without it. The app's icon is the game's own, which the Recipe takes from the user's NSP. The Build Assets get clones of the extracted game, so the next build, an update's included, reuses nxnative's extraction instead of taking up to half an hour again.
- **MacNativeGames:** one Port, `macnativegames-totk`, built by `macnativegames.sh` with upstream's `build_app.py` doing the work: it extracts and checks every file against the hashes it pins for the version, rewrites the code, merges the RomFS and translates the startup shaders. Upstream makes 1.0.0, 1.2.1 and 1.4.3; the Port takes 1.4.3, the version upstream tested most and the one the Catalog already lists. `buildAssets.format` is the upstream commit: the game's binary carries tables made from the rewritten code, so the Build Assets and the app are made together. hactool (`-t keygen`) derives the keys upstream reads from the shared keys Frontport keeps, and the Recipe checks each game file's content meta first, as nxnative's does: the base game and the 1.4.3 update. It never makes the base game's own RomFS, which a 1.4.3 build doesn't use (17 GB). Upstream's shader-list reminder can't send anything from the sandbox, so it only opens GitHub's form. The first start builds all 23,226 render and compute pipelines before the title: about 11 minutes on an M4 with the screen locked, against upstream's 90 seconds; later starts take them from the pipeline archive in the container. It shows its Game's artwork, as nxnative-totk does. The firmware is a folder ROM, as the user dumps it, so each firmware version the Catalog accepts is listed by its hash.

## Verified

What was run with these Ports, from Frontport's design notes.

| Test | Result |
|---|---|
| `nxnative.sh` for Tears of the Kingdom, game card base and the 1.4.3 update, with keys from firmware 22.5.0 (`RecipeIntegrationTests`) | Fetches its pins, builds .NET's `nx_extract`, spirv-cross, zstd and `dmhost` in the sandbox, and the NSP script identifies both NSPs though they're named by hash. Extraction 26 min (304,248 files, 15.9 GB), rewrite 1 min, shader split 15 min, 28,669 Metal libraries 79 min, all on an APFS sparse bundle on a USB SSD formatted exFAT, which FSKit serves at about 500 small writes a second. The app is 2.3 MB; its Build Assets hold the rest |
| Tears of the Kingdom installed through the Library (`AppRootTests`), its ROMs added through intake (the game card NSP, the eShop update and a `prod.keys` from firmware 22.5.0) | Intake gives the three files the Catalog's hashes and keeps only the shared keys. The Library builds, packages and signs the Port with the Build Assets beside it, and the Launcher starts it: sandboxed, it reaches the title screen through the Build Assets link, keeps its save in the container, runs for 159 s and quits cleanly when stopped, with no sandbox denials |
| Link's Awakening installed through the Library (`AppRootTests`), its ROMs added through intake (the eShop base and 1.1.0 update as NSZs, and a `prod.keys` from firmware 22.5.0) | Intake rebuilds and checks every NCZ (12 s for both, from a USB SSD), gives both NSZs the hashes titledb's content IDs give, and keeps them compressed. In the build sandbox the Recipe makes them into NSPs, each NCA checked against its content ID again, and nxnative builds from them: 34 min, 29 of them for 9,698 Metal libraries. Sandboxed, the app reaches the title screen ("Press L+R"), presents 9,300 frames with no `[RED]` line, and quits cleanly when stopped after 160 s. Since [ADR 0011](https://github.com/svich/frontport/blob/main/docs/adr/0011-keep-unlisted-files-unverified.md), intake no longer rebuilds NCZs: NSZs are kept Unverified, and the Recipe decompresses them with nsz |
| `nxnative.sh`'s `make_icon` in the build sandbox, on Tears of the Kingdom's `icon.jpg` | A clang-built tool reads the 256-pixel JPEG with ImageIO and writes a 1024-pixel PNG on the icon grid, which the Recipe wraps as `ic10`; macOS shows it for the app as it is. Wonder's full build gives its app the icon |
| `nxnative.sh` for Super Mario Bros. Wonder, game card base and the 1.2.1 update, with keys from firmware 22.5.0 (`RecipeIntegrationTests`) | Builds in 61 min on the same sparse bundle, after the drive was reconnected and while other builds loaded the Mac: extraction 2 min (two versions of 3.5 GB and 19,000 files each), rewrite 6 min, shader split 2 min, 16,268 Metal libraries 47 min. Not yet installed or launched |
| Wonder installed through the Library (`AppRootTests`) after that build | Intake gives the game card base, the update and the keys the Catalog's hashes. The Library's build reuses nxnative's extraction of the base, the rewrite and the shaders, and extracts only the update again (35 s, since the Recipe then moved its RomFS into the Build Assets), so the install takes about 2 minutes. Not launched for long enough to check |
| `nxnative.sh` cloning the RomFS into the Build Assets, Wonder built twice more | The first build extracts the update once more (38 s), its RomFS having been moved out before; the next reuses both extractions, the rewrite and the shaders, and takes 2 min. Cloning Wonder's 19,179 RomFS files takes 3 s |
| `nxnative.sh` for Super Mario Bros. Wonder without ROMs | Builds its app in the sandbox in 92 s on the internal disk. Not run with a game: no dump of it was on hand |
| A Switch game card dump converted to an NSP (Fire Emblem: Three Houses, 2026-10-25) | Every NCA's header said downloaded (distribution type 0), and none matched its content ID. Decrypted with the shared `header_key` and set back to game card (1), all four did, so intake puts them back as on the card ([ADR 0006](https://github.com/svich/frontport/blob/main/docs/adr/0006-identify-switch-files-by-content.md)): hashing both forms takes one pass, 30 s for the 11.8 GB program NCA from the USB SSD. Since [ADR 0011](https://github.com/svich/frontport/blob/main/docs/adr/0011-keep-unlisted-files-unverified.md), intake decrypts nothing and such a dump is kept Unverified |
| Fire Emblem: Three Houses installed through the Library (`AppRootTests`), its ROMs added through intake (prod.keys from firmware 22.5.0, the converted game card base, the 1.2.0 update and six DLC, all in one drop) | Intake adds the keys first, then restores the base's four NCA headers. The build extracts both versions and the DLC, rewrites the modules, boots the game headless in the build sandbox to capture its 9 run-time shaders (1 s), splits 1,372 shaders and compiles them to Metal in 3 min, all on the internal disk. Launched sandboxed, it runs the opening movie at 60 fps (p50 16.75 ms), mounts the six DLC, and after a scripted Plus reaches the title screen with "The Expansion Pass has been applied" and the Side Story menu. Since [ADR 0011](https://github.com/svich/frontport/blob/main/docs/adr/0011-keep-unlisted-files-unverified.md), the converted base is kept Unverified instead |

| Port | Latest Release | macOS asset | Notes |
|---|---|---|---|
| nxnative (Super Mario Bros. Wonder, Tears of the Kingdom, Fire Emblem: Three Houses, Link's Awakening) | no Releases; pinned to commit `6a06877`, 2026-10-25 | none: iPhone IPAs only, and a development host on the Mac | Source build, one Port per game. The Recipe runs upstream's NSP script for the Mac, then links its host, `dmhost`, with a launcher as `main` into the app's one executable. Build Stage: the game's NSP or NSZ, its update and the console keys ([ADR 0006](https://github.com/svich/frontport/blob/main/docs/adr/0006-identify-switch-files-by-content.md), [ADR 0009](https://github.com/svich/frontport/blob/main/docs/adr/0009-keep-nsz-files-compressed.md)) |

## License

GNU General Public License v3.0, like Frontport. See [LICENSE](LICENSE).
