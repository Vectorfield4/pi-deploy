---
name: mui-svg-composition
description: "Author and compose SVG illustrations for MUI projects: layered gradient scenes, IconCircle wrappers, data-driven asset wiring. Raster enough — no inline SVG in JSX."
---

# MUI SVG Composition

Compose vector illustrations and iconography for React + MUI projects. SVGs are
**assets, not components**: render them via `<img>`, never inline `<svg>` in JSX
(or a page that needs a bigger illustration loses readability on both themes).

## Solution illustration template

`src/assets/images/<slug>.svg` — authored illustration for a card/section.

- `viewBox="0 0 800 500"`, background `<rect width="800" height="500" rx="32">`.
- Root `<svg>`: `xmlns`, `viewBox`, `aria-hidden="true"`.
- Header comment: purpose, palette note, "no text by design (i18n)".
- Palette (MUI blue ramp + amber accent):
  `#1976D2` primary · `#1565C0` / `#0D47A1` darker · `#42A5F5` / `#90CAF9` /
  `#BBDEFB` / `#C7E0F8` / `#E3F2FD` lighter · `#FFB74D` accent · `#FFFFFF`.
- Background gradient:
  ```xml
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#E3F2FD"/>
    <stop offset="0.55" stop-color="#C7E0F8"/>
    <stop offset="1" stop-color="#B3D6F4"/>
  </linearGradient>
  ```
- Layer order: bg rect → decorative corner dots/dashed rings → translucent
  drop shadows (`fill="#0D47A1" fill-opacity="0.06–0.07"`) → subject → dashed
  connection lines (`stroke-dasharray="1 10"`, `stroke-linecap="round"`) →
  arrow polygons → amber indicator dots (solid dot + `stroke-opacity="0.35"`
  ring).
- No text anywhere — all copy lives in React (i18n).

## IconCircle wrapper

MUI icon in a translucent tinted circle (from `src/components/IconCircle.tsx`):

```tsx
const IconCircle = styled(Box, {
  shouldForwardProp: (prop) => prop !== "color" && prop !== "size",
})<IconCircleProps>(({ theme, color = "primary", size = 48 }) => ({
  width: size,
  height: size,
  borderRadius: "50%",
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  backgroundColor: alpha(theme.palette[color].main, 0.12),
  color: theme.palette[color].main,
}));
```

Used as `<IconCircle size={64}><Icon fontSize="large" /></IconCircle>` where
`Icon` is an `SvgIconComponent` from `@mui/icons-material`.

## Data-driven wiring

- Illustrations: import each SVG in the data file
  (`import img from "../assets/images/<slug>.svg"`), assign to the model field,
  render via `<Box component="img" src={...}>` with
  `aspectRatio: "8 / 5"`, `objectFit: "cover"`.
- Icons: type the field as `SvgIconComponent`, import the icon in the data
  file, render through `IconCircle`. Adding an entry = adding a row + asset,
  no new components.

## Rules

- Theme-consistency: baked-in colors; SVGs render identically on light and
  dark themes. Do not reference theme palette inside SVG files.
- Never use raster images where an SVG reduces to vectors (icons, diagrams,
  charts, logos).
- Raster/generated assets (`hero`, `cover`, `og`, `background`, `avatar`,
  `thumbnail`, `concept`, `illustration` for photos) go through the `drawer`
  agent; SVG-authorable assets stay inline here.