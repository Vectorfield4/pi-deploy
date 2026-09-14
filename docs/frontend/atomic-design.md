# Atomic Design

Five ideas organize components: `atoms/`, `molecules/`, `organisms/`, `templates/`, and the pages that fill templates with data. A component lands in the first folder whose definition fits it. The definitions below double as the test.

Create a folder only when it holds at least one component.

## Atoms

Single UI primitive. One element, no inner components, no domain types, no logic.

Button, Input, Icon, Badge, Spinner, Avatar, Tag.

An atom is the smallest thing worth naming. A component that splits into smaller UI pieces belongs higher.

Atoms carry no layout. Margin, position, and width belong to the composition above them.

### Where

- `shared/ui/atoms/` — a primitive reused across two or more consumers: Button, Input, Icon, Badge, Spinner.
- `entities/<name>/ui/atoms/` — a primitive carrying the meaning of one domain concept: CaseStatusDot, CaseTag.

## Molecules

A few atoms bound into one local task. Reusable as a unit, free of domain.

SearchField (Input + Button + Icon), FormRow (Label + Input + Error), MetricRow (Icon + Text + Value), CardHeader (Avatar + Title + Actions).

A label alone does nothing. A label over an input is a form row. That joint meaning is what a molecule exists for.

Test: break the component apart and what remains are atoms or basic tags. Molecule.

### Where

- `shared/ui/molecules/` — a domain-free composite reused across two or more consumers: SearchField, FormRow, MetricRow, CardHeader.
- `entities/<name>/ui/molecules/` — a composite rendering one domain concept: CaseMetricRow, CaseMeta.
- `features/<name>/ui/molecules/` — a composite bound to a single user interaction.
- `pages/<name>/ui/molecules/` — a composite used on one page only.

## Organisms

Molecules and atoms grouped into a standalone section of the interface. The first level that takes final shape.

Component library: Modal, DataTable, Toolbar, Pagination, Form.
Product code: CaseCard, CasePreview, CaseMetrics.

A user recognizes an organism as a piece of the product. Organisms let a page compose sections instead of fragments.

Test: break the component apart and what remains are smaller components (cards, lists, media objects). Organism.

### Where

- `shared/ui/organisms/` — a domain-free block reused across two or more consumers: Modal, DataTable, Toolbar, Pagination, Form.
- `entities/<name>/ui/organisms/` — a block rendering one domain concept: CaseCard, CasePreview, CaseMetrics.
- `features/<name>/ui/organisms/` — a block that owns a single user interaction: CaseFiltersPanel.
- `pages/<name>/ui/organisms/` — a block used on one page only.

## Templates

A page skeleton. Orders and places organisms, exposes slots, owns layout.

ListPageLayout, DetailPageLayout, SidebarLayout, TwoColumnLayout.

A template answers where sections sit. Content arrives through props or children; the template decides order and spacing, and touches no data.

### Where

Templates live in three places only, split by domain and reuse:

- `shared/ui/templates/` — domain-free skeletons reused by two or more pages: ListPageLayout, SidebarLayout, TwoColumnLayout.
- `app/layouts/` — a domain-aware skeleton shared by several routes, mounted through router nesting.
- `pages/<name>/ui/templates/` — a skeleton used by one page only: `pages/cases/[slug]/ui/templates/CaseDetailLayout`.

Every other folder keeps block composition in `organisms/`.

## Stateless components

Atoms and molecules are stateless: props in, JSX out, no data fetching, no store reads.

State belongs where reuse stops and context starts. An organism may hold local interaction state, an open modal, an active tab. A page composes sections and receives data from the data layer.

Reason: a component that pulls its own data drags that data into every page that renders it. Props keep the same component usable in dissimilar contexts.

## Pages

Pages fill templates with content at `src/pages/`. They wire organisms, pass data, and own nothing below composition.