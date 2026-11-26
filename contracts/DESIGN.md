# GoSafe design rules

One look for the mobile app and the agent dashboard, based on Gojek's **Asphalt (Aloha)** design system. Both apps use the tokens below; don't invent new colours, sizes or radii in feature code.

Each value says where it comes from:
- **Asphalt**: stated on [asphalt.gojek.io](https://asphalt.gojek.io/pages/foundations.html).
- **Brand**: Gojek's public brand material.
- **Ours**: our choice where Asphalt's public pages show values only in images that are no longer online (colour swatches, type sizes, shadows, radius). Replace these with the official values once we have the Figma file or the brand guideline PDF.

## Principles (Asphalt)

1. **Consistency:** design with the system, never as one-off screens. Reuse the tokens and components here.
2. **Usability:** users first, business second. In GoSafe that means safety first: the SOS button is always reachable, and nothing may cover it.
3. **Accessibility:** text meets WCAG 2.0 AA, 4.5:1 for normal text and 3:1 for large text.
4. **Aesthetics:** clean and confident, never at the cost of the first three.

Motion follows Asphalt's three ideas: *candid* (human), *contextual* (show, don't tell), *playful*. In a safety product, keep it calm: motion only explains a change, never decorates. Keep it to 150–250 ms ease-out, and turn it off when the device asks for reduced motion.

## Colour

### Brand

| Token | Hex | Source | Use |
|---|---|---|---|
| `green-500` (Gojek green) | `#00AA13` | Brand, Asphalt | Brand moments: logo mark, icons, large or bold text, selected states, progress |
| `green-600` | `#008A10` | Ours (AA-safe shade) | **Fills with normal-size text on them** (primary buttons, chips): white on it is 4.5:1 |
| `green-700` | `#00800E` | Ours | Pressed state; green text on white (5.1:1) |
| `green-50` | `#E6F7E8` | Ours | Light green backgrounds (success banners, "listened" state) |
| `ink` | `#1C1C1C` | Brand (black), softened | Primary text, icons on light backgrounds |

White text on `#00AA13` is only 3.1:1, so it passes AA for large text only (24px, or 19px bold). That's why buttons use `green-600`.

### Neutrals (ours)

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#FFFFFF` | `#121212` | Page background |
| `surface` | `#F7F7F7` | `#1C1C1C` | Cards on the page, grouped areas |
| `line` | `#E5E5E5` | `#2E2E2E` | 1px borders. Asphalt prefers space over dividers, so use these sparingly |
| `muted` | `#6B6B6B` | `#A3A3A3` | Secondary text (5.3:1 on white) |
| `text` | `#1C1C1C` | `#F2F2F2` | Primary text |

Dark theme: Asphalt supports light and dark, following the device setting. Gojek green on `#121212` is 6.0:1, so it works for text in dark mode too.

### Safety meaning (ours, same everywhere)

These colours mean the same thing on the phone and on the dashboard. They are never used for decoration.

| Token | Hex | Text on it | Meaning |
|---|---|---|---|
| `warning` | `#F5A300` | `ink` only (8.2:1) | Warning: an uncomfortable remark |
| `unsafe` | `#E8590C` | `ink` only (4.8:1) | "I feel unsafe" press |
| `high` | `#D92D20` | white (4.8:1) | High flag: harassment or threat detected |
| `sos` | `#7A1414` | white (10.8:1) | SOS press, and the SOS button |
| `danger` | `#D92D20` | white | Destructive actions (suspend driver) |
| `success` | `green-600` | white | Done, safe, agrees |

Each one also has a light tint for backgrounds, at about 10% strength: `warning-50` `#FFF6E0`, `unsafe-50` `#FDEEE6`, `high-50` `#FDECEA`, `sos-50` `#F7E8E8`.

## Typography

**Typeface.** Asphalt uses **Maison Neue** in Book, Demi and Bold, with no italic. Maison Neue is a paid font, so until we have a licence both apps use **Plus Jakarta Sans** (free, open licence, designed for Jakarta), in Regular (400) for Book, SemiBold (600) for Demi and Bold (700). Swapping the font family in one place switches both apps.

**Scale.** Asphalt: base 12, scale factor 1.3, line height = size × 1.3 rounded to a multiple of 4. The sizes below come from that rule (ours; the official table was an image):

| Token | Size / line height | Weight | Use |
|---|---|---|---|
| `title-hero` | 44 / 56 | Bold | Big numbers on the dashboard (rare) |
| `title-large` | 34 / 44 | Bold | Mobile home headline |
| `title-medium` | 26 / 36 | Bold | Page titles ("Order GR-DEMO-1") |
| `title-small` | 20 / 28 | Demi | Card and section titles |
| `title-tiny` | 16 / 20 | Demi | Labels, list titles, buttons |
| `body-moderate` | 16 / 24 | Book | Body text, messages |
| `body-small` | 14 / 20 | Book | Secondary text, transcript lines |
| `caption` | 12 / 16 | Book | Timestamps, hints. Use sparingly (Asphalt) |

## Spacing (Asphalt)

4px base, 4px grid. Use the same steps inside and between components: `4, 8, 12, 16, 20, 24, 32, 40, 48, 64`.

- Group things with space, not dividers (Asphalt).
- Give the most important element extra space: on the phone, the SOS button.
- Screen padding: 16 on mobile, 24 on the dashboard.

## Shape and elevation

**Radius (ours):**

| Token | Value | Use |
|---|---|---|
| `radius-s` | 8 | Chips, inputs, small tags |
| `radius-m` | 12 | Cards |
| `radius-l` | 16 | Dialogs, bottom sheets |
| `radius-pill` | 999 | Buttons |

**Elevation.** Asphalt has two shadow levels, and every component is 1px thick:

| Token | Value (ours) | Use |
|---|---|---|
| `shadow-low` | `0 1px 2px rgb(0 0 0 / 0.06), 0 1px 3px rgb(0 0 0 / 0.08)` | Cards, sticky bars |
| `shadow-high` | `0 8px 24px rgb(0 0 0 / 0.12)` | Dialogs, menus |

## Components

Asphalt's components: Alert, Badge, Bottom Navbar, Button, Card, Coachmark, Divider, Indicator, Input Field, Keyboard, Marker, Selection Control and Toast. How GoSafe uses them:

| Component | Rule |
|---|---|
| **Button** | Pill. Height 48 on mobile, 40 on the dashboard (56 for the mobile Start ride and 64 for SOS). Primary: `green-600` fill, white `title-tiny` text. Secondary: outlined with `line`, `text` colour. Danger: `sos` fill for SOS, `danger` for destructive actions. One primary button per view. |
| **Alert** | The warning and status messages. Light tint of the meaning colour, ink text, an icon at the start. Shown at the **top**, never over the bottom buttons. |
| **Toast** | Not used: a toast at the bottom would cover SOS. Use an Alert at the top instead. |
| **Card** | `surface` or `bg` with `line` border, `radius-m`, `shadow-low` only when it floats. 16 padding (mobile), 20 to 24 (dashboard). |
| **Badge** | Priority, trigger and flag kind. `radius-s`, `caption` or `body-small` Demi, a meaning colour with its tint or solid. |
| **Selection control** | Radios for the agent's decision, as full-width cards. Checkboxes in `green-600`. |
| **Input field** | `radius-s`, 1px `line` border, focus ring in `green-500`. |
| **Marker** | Flag pins on the ride timeline, in the meaning colours. |

## Writing

- **Short, caring, never alarming** (all the wording lives in the mobile app's `SafetyText`). Say what happened and what we're doing: "We're on it. Our safety team will contact you right away."
- No blame in messages both people can see. The warning is about the conversation, not a person.
- Sentence case everywhere ("Start ride", not "Start Ride").
- Times on the dashboard are in WIB.

## Where the tokens live

| App | File |
|---|---|
| Dashboard | `dashboard/src/app/globals.css`: Tailwind `@theme` variables (`--color-*`, `--radius-*`, `--shadow-*`, `--font-sans`) |
| Mobile | `mobile/lib/theme.dart`: `GoSafeColors`, `GoSafeType`, `ThemeData` for light and dark |

## Sources and gaps

Read: Asphalt [foundations](https://asphalt.gojek.io/pages/foundations.html), [colours](https://asphalt.gojek.io/pages/foundations_colors.html), [typography](https://asphalt.gojek.io/pages/foundations_typography.html), [spacing](https://asphalt.gojek.io/pages/foundations_spacings.html), [shadows](https://asphalt.gojek.io/pages/foundations_shadows.html), [motion](https://asphalt.gojek.io/pages/foundations_motion.html), [principles](https://asphalt.gojek.io/pages/principles.html), [components](https://asphalt.gojek.io/pages/components.html); [Gojek's rebrand story](https://www.gojek.io/blog/gojeks-rebrand-story-the-new-logo) (Maison Neue); third-party palettes for `#00AA13` ([brandpalettes](https://brandpalettes.com/gojek-logo-colors/)).

Not readable yet: the brand guideline PDF (too large to fetch), the Behance case study (blocks automated access), Figma and Dribbble (need a person to look), and Asphalt's swatch, type-scale and shadow images (missing from the site). Values marked "Ours" should be checked against those.
