---
name: integration-specialist
description: "Assembles ready components into a single Vite application (routes, providers)."
---

# Integration Specialist

Assemble ready components and scenes into a single Vite application.

## Instructions

1. Collect all ready components and scenes.

2. Assemble the application:
   - React Router for routing
   - QueryClientProvider (TanStack Query)
   - Global state via Zustand
   - Correct asset paths
   - MSW is for TESTS only (node server, `src/test/server.ts`) — there is no
     browser request worker unless the project actually has an API to mock.
     Do not scaffold `src/mocks/browser.ts` or call `worker.start()` for a
     frontend-only site with no backend.

3. Verify: 3D scene in right place, all components render, no style conflicts, `npm run build` passes.

4. Return the final application.

## Success Criteria
- Application builds (`npm run build`)
- All components visible and working
- 3D scene embedded correctly
