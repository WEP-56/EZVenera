# EZVenera Plugin Document

## Overview

EZVenera uses JavaScript source plugins and is intentionally compatible with original `venera-configs`.

The compatibility rule is simple:

- if a field is supported by EZVenera, it will be parsed and used
- if a field is not supported by EZVenera, it will be ignored

This allows existing Venera source files to continue loading without forcing plugin authors to maintain a separate config format.

## Supported fields

EZVenera currently supports these plugin sections:

### Basic metadata

- `name`
- `key`
- `version`
- `minAppVersion`
- `url`

### Account

- `account.login`
- `account.loginWithWebview`
- `account.loginWithCookies`
- `account.logout`
- `account.registerWebsite`

### Search

- `search.load`
- `search.loadNext`
- `search.optionList`
- `search.enableTagsSuggestions`
- `search.onTagSuggestionSelected`

### Category

- `category`
- `categoryComics.load`
- `categoryComics.optionList`
- `categoryComics.ranking`

### Comic

- `comic.loadInfo`
- `comic.loadEp`
- `comic.onImageLoad`
- `comic.onThumbnailLoad`
- `comic.link`
- `comic.idMatch`

### Settings

EZVenera currently supports these setting types:

- `select`
- `switch`
- `input`

### Translation

- `translation`

## Ignored fields

These sections from original Venera are currently ignored by EZVenera:

- `explore`
- `favorites`
- `comic.loadComments`
- `comic.sendComment`
- `comic.loadChapterComments`
- `comic.sendChapterComment`
- `comic.likeComic`
- `comic.likeComment`
- `comic.voteComment`
- `comic.starRating`
- `comic.archive`
- settings `callback` type

If your plugin still contains them, EZVenera will skip them.

## Authoring guidance

If you already maintain a Venera plugin:

- keep the file structure unchanged
- keep unsupported fields if you still need original Venera compatibility
- do not rely on ignored fields inside EZVenera UI flows

If you write a new EZVenera-oriented plugin:

- focus on `account`, `search`, `category`, `categoryComics`, `comic.loadInfo`, `comic.loadEp`
- only add `comic.onImageLoad` or `comic.onThumbnailLoad` when the source really needs request/header/image adaptation
- prefer `select`, `switch`, `input` for source settings

## Minimal source capability checklist

A practical EZVenera source usually needs:

1. basic metadata
2. search or category entry
3. `comic.loadInfo`
4. `comic.loadEp`

Optional:

- account login
- image loading hooks
- link parsing
- source settings

## Compatibility notes

### `category`

EZVenera supports both old-style and newer category declarations as long as they still resolve to searchable or category jump targets.

### `search`

If `search.load` exists, it is preferred.

If `search.load` does not exist and `search.loadNext` exists, EZVenera uses `loadNext`.

### `settings`

Unsupported setting types are ignored instead of causing parse failure.

### `translation`

Translation maps are preserved so source labels can still be localized by the app.

## Runtime behavior

EZVenera source runtime still provides the original JS helper environment through `assets/init.js`, including:

- `Network`
- `Convert`
- `HtmlDocument`
- `Comic`
- `ComicDetails`
- `ImageLoadingConfig`
- `APP`

This is what makes existing `venera-configs` largely reusable.

## Recommended migration style from original Venera

If your source is written for original Venera and you want it to work well in EZVenera:

- keep all core retained fields
- leave optional unsupported sections in place if you still need cross-app compatibility
- avoid depending on explore-only or comment-only behavior for the main user path

## Current implementation references

Main runtime files:

- [plugin_runtime.dart](D:\venera\EZVenera\lib\src\plugin_runtime\plugin_runtime.dart)
- [plugin_source_parser.dart](D:\venera\EZVenera\lib\src\plugin_runtime\parser\plugin_source_parser.dart)
- [plugin_js_engine.dart](D:\venera\EZVenera\lib\src\plugin_runtime\engine\plugin_js_engine.dart)
