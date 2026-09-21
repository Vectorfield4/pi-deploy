# Feature-Sliced Design

Frontend architecture standard for the Astro 7 (SSG) + React 19 / TypeScript
stack with StyleX. Layers divide code by responsibility, slices by domain,
segments by purpose. The standard dropped the `processes` layer; the layer set
is `app` / `pages` / `widgets` / `features` / `entities` / `shared`. The page
shell lives in `app/layouts/`, global base styles in `app/styles/`. Imports go
only downward.

## Rules

1. **Folder whitelist.** `src/` holds: `app`, `pages`, `widgets`, `features`,
   `entities`, `shared`. `shared` and `app` split into segments directly.
   `entities`, `features` and `widgets` split into slices with the segments
   `ui`, `model`, `i18n`, `api`.
   `test/` and Storybook (`stories/`) live at the project root, outside `src/`.
2. **Import direction.** A slice imports strictly lower layers and its own files.
3. **Public API.** Each slice exposes `index.ts`; every cross-slice import
   resolves it. Exports are named (no `export *`).
4. **Same-layer isolation.** Sibling slices share behavior through a lower layer.
5. **Shared boundaries.** `shared` carries infrastructure and route/i18n/data
   glue; business rules live in entities and features.
6. **Entity links.** Cross-entity relations reference the target by id from
   fixture data, never by cross-importing another entity slice. A feature
   resolves and renders the relations.
7. **Widget restraint.** `widgets/` stays thin; new code prefers features and
   shared until a third place demands a widget home.
8. **Extraction timing.** A slice appears when three places share the same
   behavior or shared state demands a single home.

## Layers

| Layer | Carrier |
|---|---|
| app | `app/layouts/BaseLayout.astro` (page shell), `app/styles/global.css` (base styles) |
| widgets | app-shell widgets: nav, theme/language toggles, drawer (island) |
| pages | thin `.astro` routes: `getStaticPaths` + root layout + section composition |
| features | reusable user interactions: filters, catalogs, relation blocks |
| entities | business concepts with model + ui + i18n |
| shared | infrastructure and UI kit |

`app` and `shared` have no slices. They split into segments directly and
import each other freely.

## Segment anatomy

Slices on widgets, entities and features hold segments:

| Segment | Carrier |
|---|---|
| ui | presentational components |
| model | types, fixture-driven getters, pure logic |
| i18n | per-entity dictionaries (`<plural>Ru` / `<plural>En`) |
| api | request functions, dto types (empty for pure-SSG projects — no async IO) |

`model/` files carry domain names: `cases.ts`, `services.ts`, `solutions.ts`.
Level rules for the `ui/` components live in `atomic-design.md`.

## Import rule

| Rule | Statement |
|---|---|
| Layer direction | a slice imports only from strictly lower layers and from its own files |
| Same layer | reuse between slices of one layer routes through shared |
| Public API | every slice exposes `index.ts`; cross-slice imports resolve it |

## Public API

`index.ts` re-exports what consumers need, by name. Named exports keep the
contract visible; `export *` hides it until a rename breaks silently.

## Entity relationships

Entities reference each other through a relation field on fixture data
(`relevants?: EntityRef[]`, `WithRelevants`). The relation source→target is
resolved and rendered by a relations feature slice — titles/links resolve via
the shared data getters. No cross-imports between entity slices.

## Shared

Shared segments: `ui`, `design`, `config`, `data`, `hooks`, `i18n`, `mocks`,
`assets`, `types`. (`api/` and `lib/` may exist but stay empty placeholders in
pure-SSG projects.)

- `ui/atoms|molecules|organisms` — domain-free UI kit (see `atomic-design.md`).
- `design/` — StyleX tokens (`tokens.stylex.ts`) and theme (`theme.ts`).
- `config/` — breakpoints and constants.
- `data/` — the data layer: `entities.ts` (fixture getters), `routes.ts`
  (`routeUrl`, `CLEAN_ROUTE_PATHS`), `seo.ts` (`resolvePageMeta`), icon and
  service catalogs.
- `hooks/` — `useMatchMedia`, `useT`.
- `i18n/` — build-time translations: `t.ts` (`createT`), `dict.ts`
  (`astroDictRu`/`astroDictEn`), `ru/` and `en/` namespace files.
- `mocks/` — `fixtures/` as the single source of truth for entities (+ tests);
  reads are synchronous fixture getters.
- `types/` — shared display models.
- `assets/images/` — authored SVGs and generated raster.

Shared may carry application-aware code (route constants, catalogs, branding).
It holds business rules owned by entities or features and imports nothing from
those layers.

## Widgets

The standard discourages the widgets layer because its role overlaps features.
Prefer a concrete carrier:

| Need | Carrier |
|---|---|
| one-screen user flow | a feature slice |
| layout grouping several routes | the app-level layout |
| app shell across all pages | a widget slice |

A widget slice appears only when an independent composition serves many pages.
Do not grow `src/widgets/` without a third consumer.

## Extraction rule

Give an entity its own slice when domain logic or state reuses across consumers
and needs one authoritative home. Give a feature its own slice when an
interaction reuses across consumers with a focused responsibility. Extraction
happens when a third place needs the same behavior.

## Canonical tree

Astro emits a route for every `{srcDir}/pages/**/*.astro`. Do not put `.astro`
files inside a slice `ui/` folder — thin routes stay directly in `pages/`.

```
src/
├── app/
│   ├── layouts/
│   │   └── BaseLayout.astro       # page shell: head (SEO), theme bootstrap, slot
│   └── styles/
│       └── global.css             # base styles, imported by the layout
├── widgets/
│   └── app-bar/
│       ├── ui/                    # app shell: nav, theme/language toggles, drawer
│       └── index.ts
├── pages/
│   ├── index.astro                # SSG root; rest under [lang]/ or [slug]/
│   ├── 404.astro
│   ├── [lang]/
│   │   ├── index.astro
│   │   ├── services.astro
│   │   ├── services/[slug].astro
│   │   └── 404.astro
│   └── [slug]/…                   # detail routes via getStaticPaths
├── features/
│   ├── case-filters/
│   │   ├── ui/                    # filter chips
│   │   └── index.ts
│   ├── home-solutions/
│   │   ├── ui/                    # home catalog: filtering grid (+ test)
│   │   └── index.ts
│   └── relevant-items/
│       ├── model/                 # relation types, grouping, block-title keys
│       ├── ui/                    # relation section, relation card, source→target blocks
│       └── index.ts
├── entities/
│   ├── case/
│   │   ├── model/                 # getters + per-case sections
│   │   ├── ui/organisms/          # entity card, entity hero
│   │   ├── i18n/                  # <plural>Ru / <plural>En
│   │   ├── api/                   # (empty placeholder)
│   │   └── index.ts
│   ├── service/
│   │   ├── model/                 # getters
│   │   ├── ui/organisms/          # service card
│   │   ├── i18n/                  # <plural>Ru / <plural>En
│   │   └── index.ts
│   └── solution/
│       ├── model/                 # getters
│       ├── ui/organisms/          # solution card
│       ├── i18n/                 # <plural>Ru / <plural>En
│       └── index.ts
└── shared/
    ├── ui/atoms|molecules|organisms/   # domain-free blocks (see atomic-design.md)
    ├── design/                   # StyleX tokens + theme
    ├── config/                   # breakpoints, constants
    ├── data/                     # entities, routes, seo, iconCatalog, serviceCatalog
    ├── hooks/                    # useMatchMedia, useT
    ├── i18n/                     # t.ts (createT), dict.ts (astroDicts), ru/, en/
    ├── mocks/fixtures/           # services/solutions/cases (+ tests)
    ├── types/                    # shared display models
    ├── assets/images/
    ├── api/                      # (empty placeholder)
    └── lib/                      # (empty placeholder)
```

File names inside slices are roles, not a contract — the structure above is
the reference; component names may change without a doc edit.

Every slice carries `index.ts`. Project root keeps `test/` (Vitest setup,
i18n parity, component tests) and Storybook stories at `stories/` outside the
layers.

## Validation

Biome (lint + format) enforces code style and import hygiene in CI.
`npm run lint` runs the Biome check. Follow the import rule and public API
contract by hand; the slice structure above is the reference. `npm run test`
(Vitest) guards dictionary parity, fixtures and component behaviour.