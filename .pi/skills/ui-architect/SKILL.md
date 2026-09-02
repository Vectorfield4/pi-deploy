---
name: ui-architect
description: "Designs page structure using Atomic Design methodology."
---

# UI Architect

Design page architecture using Atomic Design levels. Stack: React + MUI.

## Instructions

1. Read `artifacts/narrative.md` and `artifacts/content-plan.md`.

2. Define the page using Atomic Design:
   - **Template** — page skeleton, section ordering, responsive grid
   - **Organisms** — complex sections (hero, features, social proof, lead capture)
   - **Molecules** — reusable composites (CTA button, feature card, form field)
   - **Atoms** — smallest units (Button, Typography, Icon)

3. For each organism specify:
   - Contents (molecules/atoms)
   - Responsive behavior (mobile/tablet/desktop)
   - Animation behavior (scroll-triggered, static, interactive)
   - 3D scenes or GSAP insertion points

4. Define architecture:
   - Routes (React Router)
   - Global state (Zustand)
   - Data fetching (TanStack Query)

5. Save to `artifacts/design-spec.md`. Append an `## Asset Table` at the end
   listing every image the page needs:

   ```
   ## Asset Table

   | slug | type | prompt | aspect | source |
   |------|------|--------|--------|--------|
   | hero-main | hero | "Wide cinematic shot of..." | 16:9 | generate |
   | feature-card-1 | illustration | "..." | 4:3 | generate |
   | arrow-icon | icon | — | 1:1 | stock-mui:<IconName> |
   ```

   `type` is the asset class. The full whitelist is
   `hero | cover | og | illustration | concept | background | avatar | thumbnail | diagram`.
   Anything outside it must use `source: stock-*:...` (stock-mui, stock-lucide,
   stock-antd, stock-heroicons) or `existing:...`. Icons, logos, favicons,
   screenshots, charts, text-images, QR codes, and photos of real people are
   never `generate`.

## Final-message contract

- ≤ 4 lines: `✅ spec ready at artifacts/design-spec.md. <N> routes, <M>
  organisms, complexity: <low|med|high>.`
- Worth-reusing decisions → `remember` with tag `design-decision`.

## Tool-call discipline

- `telegram_notify(kind="task", …)` at most twice per turn.
