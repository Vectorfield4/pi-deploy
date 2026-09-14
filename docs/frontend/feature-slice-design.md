# Feature-Sliced Design

Frontend architecture standard for the React 19 / MUI 7 / Vite / TypeScript stack. Layers divide code by responsibility, slices by domain, segments by purpose. The standard dropped the `processes` layer; six layers remain.

## Rules

1. **Folder whitelist.** `src/` holds six layers: `app`, `pages`, `widgets`, `features`, `entities`, `shared`. `app` and `shared` split into segments directly; the other layers split into slices that hold the segments `ui`, `api`, `model`, `lib`, `config`. `test/` and Storybook live at the project root, outside `src/`.
2. **Import direction.** A slice imports strictly lower layers and its own files.
3. **Public API.** Each slice exposes `index.ts`; every cross-slice import resolves it.
4. **Same-layer isolation.** Sibling slices share behavior through a lower layer.
5. **Shared boundaries.** `shared` carries infrastructure and application-aware constants; business rules live in entities and features.
6. **Entity links.** Cross-entity types run through `@x`; interactions between entities live in features or pages.
7. **Widget restraint.** New code prefers features for user flows and `app` layouts for route shells.
8. **Extraction timing.** A slice appears when three places share the same behavior or shared state demands a single home.

## Layers

| Layer | Carrier |
|---|---|
| app | entry, providers, router, app-level layouts |
| pages | route-level composition |
| widgets | reusable page chunks (see Widgets) |
| features | reusable user interactions |
| entities | business concepts with model + api + ui |
| shared | infrastructure and UI kit |

App and shared have no slices. They split into segments directly. Their segments import each other freely.

## Segment anatomy

Slices on entities, features, widgets, pages hold segments:

| Segment | Carrier |
|---|---|
| ui | presentational components |
| api | request functions, dto types, mappers |
| model | schemas, stores, business logic |
| lib | slice-local helpers |
| config | slice flags and constants |

`model/` files carry domain names: `user.ts`, `order.ts`. Level rules for the `ui/` components live in `atomic-design.md`.

## Import rule

| Rule | Statement |
|---|---|
| Layer direction | a slice imports only from strictly lower layers and from its own files |
| Same layer | reuse between slices of one layer routes through a lower layer or shared |
| App / Shared | their segments import each other directly |
| Public API | every slice exposes `index.ts`; cross-slice imports resolve it |

## Public API

`index.ts` re-exports what consumers need, by name. Named exports keep the contract visible; `export *` hides it until a rename breaks silently.

A slice that exposes a narrow public API survives internal moves. Consumers import `entities/order`, the feature internals can rearrange behind it.

## Entity relationships

Entities reference each other in the real world and stay isolated in code. The connection runs at the `entities` layer through the @x notation: `entities/order/@x/artist.ts` is the public API that `order` opens for the `artist` slice. Cross-imports stay inside `entities`; interactions between entities belong in features or pages. `entity-ref` resolves through the feature `relevant-items`, not as its own entity slice.

## Shared

Shared segments: `ui`, `api`, `lib`, `config`, `i18n`, `assets`, `types`, `mocks`. Shared may carry application-aware code: route constants, endpoints, DTOs, branding. It holds business rules owned by entities or features and imports nothing from those layers.

## Widgets

The standard discourages the widgets layer because its role overlaps features. Prefer a concrete carrier:

| Need | Carrier |
|---|---|
| one-screen user flow | feature: `features/case-filters`, `features/relevant-items` |
| layout grouping several routes | app layout via router nesting |
| existing widget code | stays; new code goes to features or app layouts |

## Extraction rule

Give an entity its own slice when domain logic or state reuses across consumers and needs one authoritative home. Give a feature its own slice when an interaction reuses across consumers with a focused responsibility. A second consumer alone is a reason to wait, extraction happens when a third place needs the same behavior or shared state demands a single home.

## Canonical tree

```
src/
├── app/
│   ├── App.tsx
│   ├── layouts/                # app-level layout: header, footer, Outlet
│   ├── providers/              # Theme → Query → I18n → Router
│   ├── routes/
│   │   ├── index.tsx           # route registry (single source of truth)
│   │   ├── lazyWithRetry.ts
│   │   └── guards.ts
│   └── seo.ts
├── pages/
│   ├── home/ui/
│   ├── cases/list/ui/
│   ├── cases/[slug]/ui/
│   └── solutions/
│       ├── list/ui/
│       └── [slug]/ui/
├── features/
│   ├── case-filters/
│   │   ├── ui/
│   │   ├── model/
│   │   └── index.ts
│   ├── relevant-items/
│   │   ├── ui/
│   │   ├── model/              # EntityRef union + resolver
│   │   └── index.ts
│   └── add-to-favorites/
│       ├── ui/
│       ├── model/
│       └── index.ts
├── entities/
│   ├── case/
│   │   ├── ui/
│   │   ├── model/              # types, schema, selectors, store
│   │   ├── api/                # dto, mapper, repository, queries, keys
│   │   └── index.ts
│   └── solution/
│       ├── ui/
│       ├── model/
│       ├── api/
│       └── index.ts
└── shared/
    ├── ui/
    ├── api/                    # http client, base repository
    ├── lib/                    # store factory, pure helpers
    ├── hooks/
    ├── config/                 # env validation, constants, theme tokens
    ├── i18n/                   # dictionaries, keys, parity tests
    ├── assets/images/
    ├── types/
    └── mocks/                  # MSW handlers, fixtures, demo registry
```

Every slice carries `index.ts`. Project root keeps `test/` (Vitest setup, `renderWithProviders`, rule tests `i18nKeys.test.ts`, `coverage.test.ts`) and Storybook stories outside the layers.

## Validation

The `steiger` linter with the fsd plugin enforces the import rule, slice structure, and public API presence in CI.