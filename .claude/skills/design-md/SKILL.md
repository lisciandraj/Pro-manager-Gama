---
name: design-md
description: "Create, validate and apply DESIGN.md files — Google Labs' format (github.com/google-labs-code/design.md) that describes a visual identity to coding agents: YAML design tokens (colors, typography, rounded, spacing, components) plus markdown rationale. Use when asked to write or update a project's DESIGN.md, extract an existing design system into one, check it (broken token references, WCAG contrast), diff two versions, export it to Tailwind/DTCG tokens, or build UI that must follow a DESIGN.md."
---

# DESIGN.md

A DESIGN.md is one file at the project root: YAML front matter with exact
design tokens, then markdown sections that explain why those values exist and
how to use them. Tokens give exact values; prose gives intent.

The full specification is in `references/spec.md` (upstream `docs/spec.md`,
Apache-2.0, see `references/LICENSE-design.md`); a complete real example is in
`references/example-DESIGN.md`. Read the spec before writing or editing a file.

## Writing one

1. If the project already has a design system (CSS custom properties, token
   files, Tailwind config, component styles), extract its real values — never
   invent a palette the code does not use.
2. Front matter: `name`, then `colors`, `typography`, `rounded`, `spacing` and
   `components` as the spec defines them. Always define a `primary` color and
   typography tokens (the linter warns otherwise). Component tokens reference
   other tokens instead of repeating raw values.
3. Body: follow the section order in the spec (Overview, Colors, Typography,
   …). Say what each token is for and when not to use it.

## Checking and using it (CLI, via npx — no install needed)

```bash
npx -y @google/design.md lint DESIGN.md                 # errors, warnings, WCAG contrast
npx -y @google/design.md lint --format json DESIGN.md   # structured findings
npx -y @google/design.md diff DESIGN.md DESIGN-v2.md    # token and prose regressions
npx -y @google/design.md export --format css-tailwind DESIGN.md > theme.css
npx -y @google/design.md export --format json-tailwind DESIGN.md > tailwind.theme.json
npx -y @google/design.md export --format dtcg DESIGN.md > tokens.json
npx -y @google/design.md spec --rules                   # the lint rules
```

Run `lint` after every change and fix every error before reporting done;
treat contrast warnings as findings to report, not to hide.

## Building UI from a DESIGN.md

Read the whole file first. Use its tokens, not look-alike values; follow the
prose for hierarchy and usage. If a needed value is missing, add it to the
DESIGN.md (and lint) rather than hard-coding it in the component.
