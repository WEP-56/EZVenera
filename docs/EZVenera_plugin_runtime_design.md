# EZVenera Plugin Runtime Design

## Goal

EZVenera plugin runtime is designed around four constraints:

- compatible with existing `venera-configs`
- only keep EZVenera-required capabilities
- ignore unsupported fields instead of failing
- remain transparent and maintainable instead of becoming a black box

## Supported capability surface

EZVenera runtime currently parses and exposes these plugin capabilities:

- `account`
- `search`
- `category`
- `categoryComics`
- `comic.loadInfo`
- `comic.loadEp`
- `comic.onImageLoad`
- `comic.onThumbnailLoad`
- `settings`
- `comic.link`
- `comic.idMatch`
- `search.onTagSuggestionSelected`
- `translation`

## Compatibility rule

For existing Venera plugin files:

- supported fields are parsed into typed EZVenera capability objects
- unsupported fields are ignored
- unsupported fields do not block plugin loading unless they break class construction itself

This means EZVenera can load the original config files while deliberately not carrying the original full feature surface.

## Runtime structure

Core code lives in:

- [plugin_runtime.dart](D:\venera\EZVenera\lib\src\plugin_runtime\plugin_runtime.dart)
- [plugin_source_parser.dart](D:\venera\EZVenera\lib\src\plugin_runtime\parser\plugin_source_parser.dart)
- [plugin_js_engine.dart](D:\venera\EZVenera\lib\src\plugin_runtime\engine\plugin_js_engine.dart)
- [plugin_source_repository.dart](D:\venera\EZVenera\lib\src\plugin_runtime\repository\plugin_source_repository.dart)
- [plugin_data_store.dart](D:\venera\EZVenera\lib\src\plugin_runtime\storage\plugin_data_store.dart)
- [cookie_store.dart](D:\venera\EZVenera\lib\src\plugin_runtime\storage\cookie_store.dart)
- [models.dart](D:\venera\EZVenera\lib\src\plugin_runtime\models.dart)

### Layer split

`models`

- typed source and capability definitions
- keeps app-facing API explicit

`parser`

- converts original JS source definitions into typed EZVenera capability objects
- applies compatibility filtering

`engine`

- executes JS and serves the retained bridge protocol
- handles `http`, `html`, `convert`, cookies, `load_data`, `load_setting`, `compute`

`repository`

- manages source file installation, loading and removal

`storage`

- persists per-source data and cookies

## Why this is simpler than original Venera

Compared with original Venera:

- no giant all-purpose `ComicSource` runtime object exposed to the rest of the app
- no feature coupling to explore, comments, network favorites, follow updates, archive download
- parser responsibility is limited to retained capability translation
- runtime persistence is isolated
- unsupported plugin sections are explicitly non-goals instead of half-supported legacy burden

## Runtime directories

Current runtime storage root:

- app support dir `/plugin_runtime`

Inside it:

- `/sources` for installed `.js` source files
- `/data` for per-source persisted data
- `cookies.db` for source cookies

## Non-goals in current runtime

These original Venera areas are intentionally not implemented in EZVenera runtime:

- `explore`
- `favorites`
- `comments`
- `chapterComments`
- `likeComic`
- `likeComment`
- `voteComment`
- `starRating`
- `archive`
- settings callback UI

If these fields appear in original plugin files, EZVenera ignores them.

## Maintenance rule

When adding new runtime behavior:

1. Add a typed model first.
2. Add parser support second.
3. Add engine bridge support only if the feature requires JS-side runtime messages.
4. Document whether the feature is fully supported, partially supported, or intentionally ignored.

This rule keeps EZVenera maintainable as the codebase grows.
