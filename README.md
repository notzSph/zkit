# zkit

![version](https://img.shields.io/badge/version-3.0.0-blue.svg)
![status](https://img.shields.io/badge/status-stable-success.svg)
![license](https://img.shields.io/badge/license-MITX-grey.svg)

**zkit** is a Swiss-army knife kit for Sass:  
Global design tokens, SCSS Utils and a couple of React/Next.js hooks for layout and fullscreen state.

---

## Features

**Sass design tokens**  
  Centralized variables for:
  - heights
  - border radius
  - font sizes & font weights
  - margins & paddings
  - line heights
  - transition timings
  - base colors

**Utility-first SCSS**  
  Handful of core utility files:
  - width / height / min / max
  - margin & padding
  - flexbox
  - position & placement
  - overflow
  - display helpers (e.g. `.d-none`)
  - interaction helpers (e.g. `.c-pointer`, `.unselect-undrag`)

**Responsive-friendly**  
  Breakpoint utilities and layout tokens that play nicely with Next.js / React layouts.

**Tiny React hooks (no extra deps)**  
  - Layout state (desktop / tablet / mobile)
  - Fullscreen state for a given element

## Requirements

In order for the lib to work you'd need:

- **react >= 18**

- **rxjs >= 7**

- **sass >= 1.60.0** – can be used in any project with a Sass/SCSS pipeline.

```bash
npm install react rxjs saas

---

## Project structure

Typical layout:

```text
lib/
├── hooks/
│   ├── layout.ts
│   └── fullscreen.ts
└── styles/
    ├── breakpoints.scss
    ├── core.scss
    ├── display.scss
    ├── flex.scss
    ├── height.scss
    ├── margin-padding.scss
    ├── max-height.scss
    ├── max-width.scss
    ├── min-height.scss
    ├── min-width.scss
    ├── overflow.scss
    ├── placement.scss
    ├── position.scss
    ├── variables.scss
    └── width.scss
