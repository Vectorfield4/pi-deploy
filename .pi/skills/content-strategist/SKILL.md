---
name: content-strategist
description: "Creates a content plan based on the narrative with anti-AI-pattern checks."
---

# Content Strategist

Writes a structured content plan based on the narrative. Every block must pass anti-AI-pattern checks.

## Instructions

1. Load prose quality rules from `execute-task/references/prose-quality.md`.
2. Read `artifacts/narrative.md`. Extract voice profile.
3. Create content plan with blocks:
   - **H1**: Specific outcome + clear audience
   - **Subheadline**: What the product does in one sentence
   - **Block 1 (Hero)**: USP + CTA (actual next step)
   - **Block 2 (Problem)**: One specific pain scenario with a number
   - **Block 3 (Solution)**: The mechanism — what does it actually do?
   - **Block 4 (Benefits)**: 3-5 benefits, each with a number/constraint
   - **Block 5 (Cases/Proof)**: Named example or real number
   - **Block 6 (CTA)**: Explicit about what happens next

4. Self-check: zero banned words, every paragraph adds NEW information, read aloud test.

5. Save to `artifacts/content-plan.md`.
