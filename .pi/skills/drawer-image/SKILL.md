---
name: drawer-image
description: "Image generation for the drawer agent: HF primary, generate_image fallback, whitelist gate, repo placement."
---

# Drawer Image

Generate image assets and place them in the repo on your own images branch.

## Gate

For each row in `metadata.assets`:

1. Lowercase `type`. Whitelist:
   `hero | cover | og | illustration | concept | background | avatar | thumbnail | diagram`.
2. Blacklist. Do not generate. Rewrite the row and add
   `findings: blacklisted-asset`:
   `icon | logo | favicon | text-image | qr | barcode | photo-of-real-person | screenshot-of-our-app | chart`.
3. Type on neither list. Same rewrite and
   `findings: unclassified-asset`. Do not invent new types.

Substitutes for blacklisted rows: `stock-mui:*` / `stock-lucide:*` /
`stock-antd:*` / `stock-heroicons:*` for icons; `existing:...` for everything
else.

## Generation

For each surviving row:

1. Primary. Call:
   ```
   hf_generate_image(
     prompt=<row.prompt>,
     aspectRatio=<row.aspect>,   // default 1:1
     save="custom",
     saveDir=<from pi-huggingface-image-gen.json>
   )
   ```
   No `imageSize`, no `quality`.

2. Fallback. When the primary call throws, or returns `details.saveError`,
   or the error carries `code: "insufficient_balance" | "rate_limited"`:
   ```
   generate_image(
     prompt=<row.prompt>,
     aspectRatio=<row.aspect>,   // default 1:1
     save="custom",
     saveDir=<from pi-openai-image-generation.json>
   )
   ```

3. Copy `details.savedPath` to `repo_path` inside your worktree, overriding
   the `<ext>`: `src/assets/images/<slug>.<ext>`. The cache name is the
   tool's; the repo name is yours.

4. If both tools fail for a row, report it in the final message. Do not
   commit a placeholder.

## Deliverable

- All assets committed and pushed on the images branch:
  `feat(images): add <slugs>`.
- `repo_path` corrected in the asset list for `.ext` differences.