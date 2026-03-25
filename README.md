# WP Theme Variables

A native macOS app for browsing, searching, and copying the CSS custom properties that WordPress generates from a theme's `theme.json` file.

Point it at a folder containing one or more WordPress installations and it scans for every `wp-content/themes/*/theme.json`, parses the settings, reconstructs the CSS variables WordPress would output, and presents them in a clean two-column table — with live pixel annotations for every value.

<img width="1231" height="844" alt="Screenshot 2026-03-25 at 11 08 04 AM" src="https://github.com/user-attachments/assets/2bff214d-4e80-4652-9cb0-5f090f886dd2" />

---

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later (to build from source)

---

## Building

1. Unzip the project folder.
2. Open `ThemeJsonViewer.xcodeproj` in Xcode.
3. Select your Mac as the run destination.
4. Press **⌘R**.

No dependencies, no Swift Package Manager, no CocoaPods. The entire app is five Swift files.

---

## Getting Started

On first launch the sidebar shows an **Open Directory…** button. Click it (or press **⌘O**, or go to **Settings → Directory → Open…**) and choose:

- a single WordPress site root (the folder that contains `wp-content/`), or
- a parent folder that holds multiple WordPress sites side by side.

The app recursively scans the chosen folder, skipping `node_modules`, `vendor`, `.git`, `dist`, `build`, and other non-source directories. Themes appear in the sidebar as they are found — you do not need to wait for the scan to complete before clicking one.

---

## Interface

### Sidebar

Themes are grouped into collapsible **sections** by project name. Each row shows the theme's human-readable name (from `style.css`) with the directory slug underneath in monospace, and a variable count on the right.

Use the **search field** at the top of the sidebar to filter across theme name, directory slug, and project name simultaneously.

### Variables tab

The main table has two columns:

| Variable | Value |
|---|---|
| `--wp--preset--color--primary` | `#3a86ff` |
| `--wp--preset--font-size--lg` | `clamp(1.125rem, …, 1.5rem)` |

**Click any cell** — name or value — to copy it to the clipboard. A brief highlight and "Copied!" indicator confirm the action. The click target is a full-height row, not just the text.

#### Value annotations

Every value in the right column receives an automatic grey annotation where possible:

| Value type | Annotation shown |
|---|---|
| `1.5rem` | `= 24px` |
| `clamp(0.875rem, …, 1.5rem)` | `≈ 14px – 24px` |
| `var(--wp--preset--color--base)` | `→ #ffffff` (resolved from the theme's own variables) |
| `calc(1rem + 4px)` | `≈ 20px` |

The `clamp()` annotation extracts the first and last arguments and converts them to pixels, giving you the **minimum and maximum rendered size** at a glance without needing to read the fluid formula.

#### Filtering by category

A dropdown next to the search field filters variables by type:

- 🎨 Color
- 🌈 Gradient
- ◑ Duotone
- 🔤 Font Size
- 🔠 Font Family
- 📐 Spacing
- 🌑 Shadow
- ⬜ Border
- 📏 Dimension
- ✨ Custom

#### Base pixel size

In the top-right corner of the variables view is a small **Base px** field, defaulting to `16`. Change this per theme if its root font size is not the browser default — all `rem` and `em` annotations update instantly. The value is remembered per theme for the session.

### Raw JSON tab

Switch to **Raw JSON** to see the exact contents of `theme.json` as loaded from disk — useful for debugging why a theme shows fewer variables than expected. A **Copy JSON** button copies the entire file to the clipboard.

If the file declares a `$schema` URL, a clickable link appears in the tab bar so you can open the schema in a browser.

---

## What variables are generated

The app mirrors WordPress's own CSS variable generation logic from `theme.json` settings:

| JSON path | CSS property prefix |
|---|---|
| `settings.color.palette` | `--wp--preset--color--` |
| `settings.color.gradients` | `--wp--preset--gradient--` |
| `settings.color.duotone` | `--wp--preset--duotone--` |
| `settings.typography.fontSizes` | `--wp--preset--font-size--` |
| `settings.typography.fontFamilies` | `--wp--preset--font-family--` |
| `settings.spacing.spacingSizes` | `--wp--preset--spacing--` |
| `settings.spacing.spacingScale` | `--wp--preset--spacing--` (auto-generated scale) |
| `settings.border.radiusSizes` | `--wp--preset--border-radius--` |
| `settings.shadow.presets` | `--wp--preset--shadow--` |
| `settings.dimensions.dimensionSizes` | `--wp--preset--dimension--` |
| `settings.custom` (any depth) | `--wp--custom--` (recursively flattened) |

#### Fluid font sizes

Font sizes that use WordPress's fluid typography system are resolved to their `clamp()` output using the same algorithm as `wp_get_typography_font_size_value()`:

- Per-size `fluid: { min, max }` — uses the explicit bounds.
- Per-size `fluid: true` or `fluid` omitted, with global `settings.typography.fluid: true` — auto-calculates a 75% scale factor minimum.
- Per-size `fluid: false` — skipped; the static `size` value is used.

The minimum and maximum viewport widths and the minimum font size limit are taken from `settings.typography.fluid` when present, falling back to WordPress defaults (320 px / 1000 px / 14 px).

---

## Settings

Open **Settings** (⚙ gear icon in the sidebar toolbar).

### Directory

Shows the currently scanned path. Click **Open…** to choose a different folder.

### Display

**Use human-readable theme name** — when enabled (the default), the sidebar and detail header show the `Theme Name:` value from `style.css` rather than the directory slug. The slug is shown in small monospace text below the name when the two differ.

### Project Name: Skip Folders

When the app works out what to call a "project" in the sidebar section header, it walks up the directory tree from `/wp-content/` looking for a meaningful folder name. Folders in this list are skipped — the first ancestor *not* on the list becomes the project name.

This solves the common local development structure where the actual site name lives above generic wrapper folders:

```
Sites/
  mysite.test/
    app/          ← skipped
      public/     ← skipped
        wp-content/
```

Here `mysite.test` would be used as the project name because `app` and `public` are in the skip list.

**Default skip list:** `public`, `app`, `www`, `htdocs`, `html`, `web`, `webroot`

You can add your own entries, remove defaults, and drag to reorder (order does not affect the walk-up logic — any matching folder is skipped regardless of list position). **Reset to defaults** restores the original list.

---

## File structure

```
ThemeJsonViewer/
├── ThemeJsonViewerApp.swift      Entry point, menu commands
├── AppState.swift                Observable state, directory scanning, site parsing
├── WordPressCSSGenerator.swift   theme.json models + CSS variable generation
├── ContentView.swift             Sidebar, detail tabs, settings sheet
├── ThemeVariablesView.swift      Variable table, ValueAnnotator, CopyableCell
└── Assets.xcassets/             App icon
```

---

## Limitations & known gaps

- **Inherited variables** — WordPress child themes and block themes can inherit variables from parent themes or from WordPress core itself. This app only reads the `theme.json` in each theme folder; it does not merge parent or core defaults. If a theme has very few variables it likely relies heavily on inheritance from a parent theme or from core's built-in presets. The Raw JSON tab helps confirm what the file actually contains.

- **`var()` resolution** — cross-variable references are resolved one level deep using the theme's own variable map. References to variables defined in a parent theme or in WordPress core will show as `unresolved`.

- **`vw` units in `clamp()`** — the middle argument of most fluid font-size clamp values is a `vw`-based expression. The annotation shows only the clamped minimum and maximum (the first and last arguments), not the viewport-relative preferred value, since that cannot be computed without knowing the viewport width.

- **No live reload** — changes to `theme.json` files on disk are not detected while the app is running. Re-open the directory to rescan.

---

## License

MIT. Do whatever you like with it.
