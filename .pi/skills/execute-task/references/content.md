# Content task (`type == "content"`)

Loaded by `execute-task` for content sub-tasks. The content agent owns the
copy; this file binds the workflow together.

## Steps

1. Load `references/memory.md` → `references/rag.md` (context, per step 1.5).

2. Write the narrative:
   - Load the `narrative-designer` skill → produce `artifacts/narrative.md`.
   - Voice profile, USP with a number, one concrete pain scenario, journey.

3. Write the content plan:
   - Load the `content-strategist` skill → produce `artifacts/content-plan.md`.
   - H1, subheadline, hero/problem/solution/benefits/cases/CTA blocks.

4. Apply the prose-quality overlay (`references/prose-quality.md`):
   - Grep for banned words/phrases; every benefit claim carries a
     number/constraint; CTA states the actual next step; copy-paste test.

5. Commit and push on the feature branch.

## Success Criteria

- Both artifacts exist in `artifacts/`
- Zero banned words (grep against `prose-quality.md`)
- Acceptance criteria met