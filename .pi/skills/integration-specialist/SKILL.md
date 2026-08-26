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
   - MSW in dev mode for API mocking
   - Correct asset paths

3. Verify: 3D scene in right place, all components render, no style conflicts, `npm run build` passes.

4. Return the final application.

## Success Criteria
- Application builds (`npm run build`)
- All components visible and working
- 3D scene embedded correctly
