# Atomic Design

Five ideas organize components: `atoms/`, `molecules/`, `organisms/`, and the
thin pages that fill them with data. A component lands in the first folder
whose definition fits it. The definitions below double as the test.

Create a folder only when it holds at least one component.

## Atoms

Single UI primitive. One element, no inner components, no domain types, no
logic.

An atom is the smallest thing worth naming. A component that splits into
smaller UI pieces belongs higher.

Atoms carry no layout. Margin, position, and width belong to the composition
above them.

Every reusable atom is registered in `shared/ui/atoms/index.ts` (named
exports); internal React components import `@/shared/ui/atoms`, pages import
from the barrel too.

### Where

- `shared/ui/atoms/` holds a primitive reused across two or more consumers.
- `entities/<name>/ui/atoms/` would hold a primitive carrying the meaning of
  one domain concept (none currently).

## Molecules

A few atoms bound into one local task. Reusable as a unit, free of domain.

Actual molecules are small bound composites: an icon plus a button, or an
eyebrow plus a title, a subtitle and an optional action link forming a
section header.

A label alone does nothing. A label over an input is a form row. That joint
meaning is what a molecule exists for.

Test: break the component apart and what remains are atoms or basic tags.
Molecule.

### Where

- `shared/ui/molecules/` holds a domain-free composite reused across two or
  more consumers.
- `entities/<name>/ui/molecules/` and `features/<name>/ui/molecules/` would
  hold composites bound to one domain concept or user interaction (none
  currently).

## Organisms

Molecules and atoms grouped into a standalone section of the interface. The
first level that takes final shape.

Product blocks live in `shared/ui/organisms/`: heroes, CTA banners, stat
grids, drawers, section blocks, and the `*Section` wrappers around content
arrays. Entity organisms render a single domain concept and live in
`entities/<name>/ui/organisms/`.

A user recognizes an organism as a piece of the product. Organisms let a page
compose sections instead of fragments.

**New content blocks**: an organism wrapping the shared section shell that
renders an array of i18n keys passed by the page (e.g. a counters block, a
tile grid, a feature-card grid). Data stays in fixtures and i18n keys; the
block never looks up content itself.

Test: break the component apart and what remains are smaller components
(cards, lists, media objects). Organism.

### Where

- `shared/ui/organisms/` holds a domain-free block reused across two or more
  consumers (sections, blocks, a drawer, a fullscreen preview).
- `entities/<name>/ui/organisms/` holds a block rendering one domain concept
  (entity cards and heroes).
- `features/<name>/ui/` holds a block that owns a single user interaction
  (filter chips, relation blocks). No organism layer under features — thin
  wrappers live directly in `ui/`.
- `pages/<name>/ui/` is not used: thin routes compose sections inline.

## Behaviour lives with the component

Animation and interaction state are component behaviour.

- **GSAP** lives next to the component it animates. Reused scroll/hover
  helpers move to `shared/hooks/`.
- **Interactive organisms** are mounted as Astro islands:
  `client:visible` for the app shell and filterable lists, `client:load` for
  sliders and fullscreen previews. Without JS the static markup (sections,
  slider levels) still renders.
- **3D scenes** (Three.js + R3F) are organisms: a `Canvas` lives in the
  owning slice's `ui/organisms/` and mounts as a `client:load` island.
  `useFrame` drives animation; geometries and materials dispose on unmount.
  A poster image in the island slot keeps the area meaningful pre-hydration.

## Templates

A page skeleton. Orders and places organisms, exposes slots, owns layout.

`src/app/layouts/BaseLayout.astro` is the single template: it opens `<html>`,
emits title/description/canonical/hreflang from the SEO resolver, bootstraps
the theme and renders the page `slot`. Page-level layout (hero → sections →
CTA) is composed inline in the thin `.astro` route — there are no page-level
templates and no `shared/ui/templates/`.

## Stateless components

Atoms and molecules are stateless: props in, JSX out, no data fetching, no
store reads.

State belongs where reuse stops and context starts. An organism may hold local
interaction state: an open drawer, active filters, a slider depth, an
open/closed preview flag.

Reason: a component that pulls its own data drags that data into every page
that renders it. Props keep the same component usable in dissimilar contexts.

## Pages

Pages are thin `.astro` files in `src/pages/`: `getStaticPaths`, `BaseLayout`,
composition of sections with `t` created via `createT(currentLang, astroDicts)`
and entities read from the shared data getters. Data comes through props and
fixture getters — never fetched.

Placement tests are unchanged: an entity card is an entity organism, a base
button is a shared atom, a drawer is a shared organism (it carries no domain).