# EZVenera Simplification Execution Plan

## 1. Goal

EZVenera is planned as a simplified fork of `venera`, with these fixed constraints:

- Platform scope: only `Windows` and `Android`
- Core retained capability: plugin source `login`, `search`, `category`, `details`, `reading`, `download`
- Local capability: retain `history` and `local favorites`; downloaded comics must still have an in-app entry point
- Information architecture:
  - Windows: left sidebar
  - Android: bottom navigation
  - Navigation order: `Search` / `Category` / `Local` / `Sources` / `Settings`
- Simplification principle: reduce non-core features first, preserve plugin compatibility first

Current conclusion: EZVenera should be built as a **new app shell + selective migration of core runtime**, not by directly deleting large parts inside the original `venera` app.

## 2. Codebase Audit Summary

### 2.1 Original app entry and navigation

Key files:

- `D:\venera\venera\lib\main.dart`
- `D:\venera\venera\lib\init.dart`
- `D:\venera\venera\lib\pages\main_page.dart`
- `D:\venera\venera\lib\pages\home_page.dart`

Findings:

- Original `MainPage` is `Home / Favorites / Explore / Categories`, with `Search` and `Settings` exposed as actions.
- `HomePage` is not a simple home page. It mixes search entry, data sync, history, local library, follow updates, source summary, image favorites, and download entry.
- This means EZVenera cannot be obtained by only editing the sidebar. The original home page is a feature aggregator and should be removed rather than reused.

### 2.2 Plugin runtime is the real core

Key files:

- `D:\venera\venera\lib\foundation\comic_source\comic_source.dart`
- `D:\venera\venera\lib\foundation\comic_source\parser.dart`
- `D:\venera\venera\lib\foundation\js_engine.dart`
- `D:\venera\venera\lib\foundation\js_pool.dart`
- `D:\venera\venera\lib\network\images.dart`
- `D:\venera\venera\doc\comic_source.md`
- `D:\venera\venera-configs\_venera_.js`

Findings:

- Original source plugins are JavaScript configs executed through `flutter_qjs`.
- The parser currently supports account login, category, category comics, search, favorites, comic details, comments, tag jump, source settings, archive download and image loading hooks.
- Even if EZVenera drops many UI features, plugin compatibility still depends on preserving the JS runtime contract:
  - `sendMessage`
  - `Network`
  - `Convert`
  - `HtmlDocument` / `HtmlElement`
  - `Comic` / `ComicDetails`
  - `ImageLoadingConfig`
  - `UI`
  - `APP`
- Therefore the first engineering constraint is: **do not casually rewrite the plugin bridge**.

### 2.3 Search / category / details / reader / download chain is already separable

Key files:

- `D:\venera\venera\lib\pages\search_page.dart`
- `D:\venera\venera\lib\pages\search_result_page.dart`
- `D:\venera\venera\lib\pages\categories_page.dart`
- `D:\venera\venera\lib\pages\comic_details_page\comic_page.dart`
- `D:\venera\venera\lib\pages\reader\reader.dart`
- `D:\venera\venera\lib\network\download.dart`

Findings:

- Search and category flows are already source-driven and can be ported with moderate pruning.
- Comic details page is feature-rich, but reading and downloading are already wired around `ComicSource.loadComicInfo`, `loadComicPages`, and `ImageDownloader`.
- Reader and downloader are heavy modules, but they are still more reusable than rewriting from scratch.

### 2.4 Local data is usable, but original scope is larger than EZVenera needs

Key files:

- `D:\venera\venera\lib\foundation\appdata.dart`
- `D:\venera\venera\lib\foundation\local.dart`
- `D:\venera\venera\lib\foundation\history.dart`
- `D:\venera\venera\lib\foundation\favorites.dart`

Findings:

- `LocalManager` already covers downloaded comics and task persistence.
- `HistoryManager` already covers reading progress persistence.
- `LocalFavoritesManager` is powerful, but includes folder sync and follow-update support that EZVenera does not need in MVP.
- `Settings` is the biggest coupling point. A large number of settings only exist to serve removed features.

## 3. Recommended Product Boundary for EZVenera

### 3.1 Keep in MVP

- Source install / update / delete
- Source account login
- Search
- Category page
- Category comics page
- Comic details
- Reader
- Download task management
- Local history
- Local favorites
- Downloaded comics entry
- Core settings for reading, network, appearance, language, download

### 3.2 Remove in MVP

- Home aggregation page
- Explore page
- Aggregated search
- Network favorites page
- Follow updates
- Image favorites
- Data sync / WebDAV sync
- App lock / authorization page
- Source in-app code editor
- Headless mode
- Linux / macOS / iOS / Debian packaging
- Debug page

### 3.3 Defer, do not block MVP

- Archive import / restore tools
- Clipboard image collection
- Custom image processing script
- Source-side comment, like, vote, rating UI
- Deep app-link workflows beyond basic compatibility

## 4. Target Information Architecture

### 4.1 Navigation

- `Search`
  - reuse original search logic
  - remove aggregated search toggle in MVP
- `Category`
  - keep behavior consistent with original Venera
  - keep ranking page only when source explicitly supports it
- `Local`
  - first-level tabs or segmented views:
    - `History`
    - `Favorites`
    - `Downloads`
- `Sources`
  - independent source management page
  - source install / update / login / per-source settings
- `Settings`
  - keep most settings that still affect retained flows

### 4.2 Important assumption

Because download is a retained core capability, EZVenera must provide an explicit downloaded-comics entry. Even if the navigation label remains `Local`, the page should contain `Downloads` together with `History` and `Favorites`.

## 5. Reuse / Rewrite Matrix

### 5.1 Prefer direct migration with small pruning

- `foundation/comic_source/*`
- `foundation/js_engine.dart`
- `foundation/js_pool.dart`
- `network/images.dart`
- download runtime in `network/download.dart`
- history persistence in `foundation/history.dart`
- local library persistence in `foundation/local.dart`
- source-driven search/category/detail/reader pages

### 5.2 Rebuild around retained runtime

- app entry
- simplified `MainPage`
- simplified `LocalPage`
- simplified `ComicSourcePage`
- simplified `SettingsPage`
- shared app shell and routing

### 5.3 Remove instead of "temporarily hiding"

- `pages/home_page.dart`
- `pages/explore_page.dart`
- `pages/aggregated_search_page.dart`
- `pages/favorites/network_*`
- `pages/follow_updates_page.dart`
- `pages/image_favorites_page/*`
- `utils/data_sync.dart`
- auth flow and non-target platform packaging code

## 6. Implementation Strategy

## Phase 0: Bootstrap EZVenera shell

Goal:

- make `D:\venera\EZVenera` become an independent Flutter app
- only declare Windows and Android as supported targets

Tasks:

- create new Flutter project shell
- copy minimal app metadata and assets needed for startup
- build new `MainPage` with target 5-tab navigation
- keep theme structure simple and stable

Deliverable:

- app launches on Windows
- empty or placeholder pages for all 5 destinations

## Phase 1: Port plugin runtime first

Goal:

- make existing Venera JS source plugins executable without changing plugin files

Tasks:

- migrate `comic_source` parser/runtime
- migrate `JsEngine`, `JSPool`, cookie handling, HTTP bridge, HTML parser bridge
- migrate image loading bridge and image post-processing pipeline
- verify `_venera_.js` contract coverage against existing source files in `D:\venera\venera-configs`

Acceptance:

- load at least one local `.js` source successfully
- source metadata, source settings and account config can be parsed
- search/category/detail function calls can reach JS side

## Phase 2: Restore the retained business chain

Goal:

- complete "search -> details -> reader -> download -> local entry" closed loop

Tasks:

- port `SearchPage` and `SearchResultPage`, remove aggregated search
- port `CategoriesPage` and category result page
- port comic details page, then trim non-core actions
- port reader
- port download tasks and downloaded-comic entry

Acceptance:

- for a test source, user can search, open details, read, and start download
- downloaded comics can be reopened from `Local`
- history is written during reading

## Phase 3: Build simplified local and source management pages

Goal:

- make the product usable without original home/favorites architecture

Tasks:

- implement `LocalPage` with `History / Favorites / Downloads`
- trim `LocalFavoritesManager` UI to local-only usage
- rebuild `ComicSourcePage` into a smaller page:
  - add source from URL/file
  - update source
  - delete source
  - login/logout
  - source settings
- keep Windows webview login and Android webview login

Acceptance:

- user can independently manage sources
- user can independently inspect history, favorites and downloads

## Phase 4: Retain only effective settings

Goal:

- reduce settings complexity while keeping retained features controllable

Keep:

- appearance: theme, color, language
- reader: reading mode, images per page, tap turning, animation, status bar, chapter comments if retained
- network: proxy, bad certificate handling, cache size, source repo URL
- download: download threads, local path
- search/category related retained defaults

Drop or defer:

- explore page settings
- follow update settings
- sync / WebDAV settings
- authorization settings
- debug settings
- image collection and niche experimental settings

Acceptance:

- settings pages only expose values that still affect EZVenera behavior
- no dead setting keys remain on visible UI

## Phase 5: Stabilization and packaging

Tasks:

- verify Windows build
- verify Android build
- test login webview flow on both platforms
- test download path and Android storage behavior
- test source update flow

Acceptance:

- Windows and Android packages can be built
- no core retained flow depends on removed pages

## 7. MVP Test Set

At least choose representative source types from `D:\venera\venera-configs`:

- one public search source
- one category-heavy source
- one login-required source
- one source using `onImageLoad` or custom image headers

Suggested principle:

- do not test only one source type
- prioritize sources that exercise different bridge capabilities

## 8. Main Technical Risks

### Risk 1: Plugin compatibility breakage

Cause:

- EZVenera simplifies UI, but plugins depend on the existing JS bridge, source parser and image hooks

Mitigation:

- port runtime first
- use original `_venera_.js` API contract as compatibility baseline
- do not remove message handlers before checking actual plugin usage

### Risk 2: Reader is feature-rich and tightly coupled to settings

Cause:

- reader depends on many settings and utility modules

Mitigation:

- first migrate the existing reader
- then cut optional features after the reading loop is stable

### Risk 3: Download and local library are coupled

Cause:

- download completion writes into local DB and expects local entry points

Mitigation:

- design `Local` page before removing original local/favorites pages
- keep `LocalManager` data contract intact in MVP

### Risk 4: Windows and Android login implementations differ

Cause:

- Windows depends on desktop webview handling, Android depends on in-app webview

Mitigation:

- keep both login paths from the original app in first migration
- simplify UI later, not the underlying login bridge

## 9. Recommended First Sprint

Sprint target: make one source run end-to-end in EZVenera.

Backlog:

1. Create EZVenera Flutter shell with 5-tab navigation
2. Port plugin runtime and source loading
3. Port source management page with add/login/update
4. Port search + search result
5. Port comic details + reader
6. Port download task + local persistence
7. Add `Local` page for history/favorites/downloads

Sprint done definition:

- one source can be installed
- one comic can be searched
- details page can open
- reading works
- download works
- local re-entry works

## 10. Final Recommendation

Do not start by deleting modules from `D:\venera\venera`.

Recommended path:

1. Build EZVenera as a new app under `D:\venera\EZVenera`
2. Migrate the plugin runtime and retained business chain first
3. Rebuild navigation and page composition around the retained chain
4. Only then remove non-core modules and settings

This path has the lowest compatibility risk and the clearest delivery cadence.
