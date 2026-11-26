# GoSafe design rules

One look for the mobile app and the agent dashboard, based on **The Gojek Brand Book (2019)** and Gojek's **Asphalt (Aloha)** design system. Both apps use the tokens below; don't invent new colours, sizes or radii in feature code.

Each value says where it comes from:
- **Brand book**: The Gojek Brand Book 2019 (page numbers are the book's printed pages).
- **Asphalt**: [asphalt.gojek.io](https://asphalt.gojek.io/pages/foundations.html).
- **Ours**: our choice, where neither source gives a value (radii, shadow values, light tints, dark-mode neutrals), or where we nudged a value to pass contrast.

## Principles

**Asphalt:**
1. **Consistency:** design with the system, never as one-off screens.
2. **Usability:** users first, business second. For GoSafe that means safety first: the SOS button is always reachable, and nothing may cover it.
3. **Accessibility:** text meets WCAG 2.0 AA, 4.5:1 for normal text and 3:1 for large text.
4. **Aesthetics:** clean and confident, never at the cost of the first three.

**Brand book.** Gojek's archetype is *the Magician*: it makes the complex appear simple. Its slogan is *Pasti Ada Jalan* ("There's always a way"). For GoSafe, that means one clear next step on every screen.

**Motion (Asphalt):** candid, contextual, playful. In a safety product, keep it calm: motion only explains a change, never decorates. Keep it to 150–250 ms ease-out, and turn it off when the device asks for reduced motion. Two exceptions, both to show where playback is and both off under reduced motion: the waveform bars at the playhead pulse while audio plays, and the transcript line that starts playing bounces once (450 ms), gets a green progress bar, and scrolls into view inside the transcript list; lines already heard turn muted.

## Colour

### How Gojek uses colour (brand book p. 70–96)

Six primary colours, one per product family, and "no random colours":

| Colour | Hex | Product family |
|---|---|---|
| **Gojek Green** | `#00AA13` | Travel, transport and logistics: **GoRide, GoCar**, GoSend. GoSafe's home colour |
| Retail Red | `#EE2737` | Food and shopping (GoFood, GoMart) |
| Odd-job Orange | `#EF6A00` | Household services |
| Popcorn Pink | `#DF1995` | Entertainment |
| Payment Blue | `#00AED6` | Payments |
| Partner Purple | `#93328E` | Merchant and driver partners |

GoSafe is a transport feature, so it is **green**. We borrow shades of red and orange only for **safety meaning** (below), never as decoration and never as a product colour.

### Brand

| Token | Hex | Source | Use |
|---|---|---|---|
| `brand` (Gojek Green) | `#00AA13` | Brand book p. 70 | Brand moments: icons, large or bold text, selected states, focus ring |
| `brand-strong` | `#008A10` | Ours: brand book's green 2426C `#008C15` (4.41:1) nudged to pass AA | **Fills with normal-size text** (primary buttons): white on it is 4.5:1 |
| `brand-deep` | `#257226` | Brand book green 2273C | Pressed state; green text on white (6.0:1) |
| `brand-tint` | `#E6F7E8` | Ours | Light green backgrounds ("you listened", success) |

White text on `#00AA13` is only 3.1:1, so it passes AA for large text only (24px, or 19px bold). That's why buttons use `brand-strong`.

### Neutrals (brand book p. 96–97, Pantone Black and Cool Grays)

| Token | Light | Dark (ours) | Source | Use |
|---|---|---|---|---|
| `canvas` | `#FFFFFF` | `#121212` | | Page background |
| `surface` | `#F7F7F7` | `#1C1C1C` | Ours | Grouped areas, chips |
| `line` | `#D9D9D6` | `#2E2E2E` | Cool Gray 1 C | 1px borders. Prefer space over dividers (Asphalt) |
| `muted` | `#63666A` | `#A3A3A3` | Cool Gray 10 C | Secondary text: 5.8:1 on white |
| `fg` / `ink` | `#101820` | `#F2F2F2` | Black 6 C | Primary text: 17.9:1 on white |

Dark theme: Asphalt supports light and dark, following the device setting. Gojek Green on `#121212` is 6.0:1, so it also works as text in dark mode.

### Safety meaning (same in both apps)

Shades from the brand book's red and orange families, used only to say how serious something is:

| Token | Hex | Source | Text on it | Meaning |
|---|---|---|---|---|
| `warn` | `#FF8F1C` | Orange 1495C | `ink` only (7.8:1) | Warning: an uncomfortable remark |
| `unsafe` | `#E35205` | Orange 166C | `ink` only (4.7:1) | "I feel unsafe" press |
| `high` | `#D22730` | Red 1795C | white (5.2:1) | High flag: harassment or threat detected |
| `sos` | `#862633` | Red 202C | white (9.0:1) | SOS press, and the SOS button |
| `danger` | `#D22730` | Red 1795C | white | Destructive actions (suspend driver) |
| `success` | `brand-strong` | | white | Done, safe, agrees |

Light tints for backgrounds: `warn-tint` `#FFF4E5` (ours), `unsafe-tint` `#FDEEE6` (ours), `high-tint` `#F2D4D7` (red 698C), `sos-tint` `#F3E4E6` (ours).

## Typography

**Typeface (brand book p. 138–145, Asphalt).** **Maison Neue**: "precise geometric forms" with a "humanist character".
- **Display**, for titles that stand out: Maison Neue **Extended** (Book, Bold, Extra Bold).
- **Body**, for everything people read: Maison Neue **Book**. Also Demi and Bold.
- **Leading:** 1.5× for body text (brand book). Asphalt's app scale rounds line heights to a multiple of 4.

Maison Neue is a paid font, so until we have a licence both apps use **Plus Jakarta Sans** (free, open licence, designed for Jakarta): Regular (400) for Book, SemiBold (600) for Demi, Bold (700) for Bold and Extended titles. The font family is set in one place per app.

**Scale (Asphalt: base 12, ×1.3, line height rounded to 4).** The official size table is an image no longer online, so the sizes follow the rule:

| Token | Size / line height | Weight | Use |
|---|---|---|---|
| `title-hero` | 44 / 56 | Bold | Big numbers (rare) |
| `title-large` | 34 / 44 | Bold | Mobile home headline |
| `title-medium` | 26 / 36 | Bold | Page titles ("Order RB-182730459") |
| `title-small` | 20 / 28 | Demi | Card and section titles |
| `title-tiny` | 16 / 20 | Demi | Labels, list titles, buttons |
| `body-moderate` | 16 / 24 | Book | Body text, messages (1.5×) |
| `body-small` | 14 / 20 | Book | Secondary text, transcript lines |
| `caption` | 12 / 16 | Book | Timestamps, hints. Use sparingly (Asphalt) |

## Spacing (Asphalt)

4px base, 4px grid. Use the same steps inside and between components: `4, 8, 12, 16, 20, 24, 32, 40, 48, 64`.

- Group things with space, not dividers.
- Give the most important element extra space: on the phone, the SOS button.
- Screen padding: 16 on mobile, 24 on the dashboard.

## Shape and elevation

The brand book's compositions use **curved containers** with rounded corners, so GoSafe leans round.

| Token | Value (ours) | Use |
|---|---|---|
| `radius-chip` | 8 | Chips, inputs, small tags |
| `radius-card` | 12 | Cards |
| `radius-sheet` | 16 | Dialogs, bottom sheets |
| pill | 999 | Buttons |

**Elevation (Asphalt).** There are two levels, and every component is 1px thick:

| Token | Value (ours) | Use |
|---|---|---|
| `shadow-low` | `0 1px 2px rgb(0 0 0 / 0.06), 0 1px 3px rgb(0 0 0 / 0.08)` | Cards when they float, sticky bars |
| `shadow-high` | `0 8px 24px rgb(0 0 0 / 0.12)` | Dialogs, menus |

## Components

Asphalt's components: Alert, Badge, Bottom Navbar, Button, Card, Coachmark, Divider, Indicator, Input Field, Keyboard, Marker, Selection Control and Toast. How GoSafe uses them:

| Component | Rule |
|---|---|
| **Button** | Pill. Height 48 on mobile, 40 on the dashboard (56 for the mobile Start ride and 64 for SOS). Primary: `brand-strong` fill, white `title-tiny` text. Secondary: outlined with `line`, `fg` text. SOS: `sos` fill. Destructive: `danger`. One primary button per view. |
| **Button variants (Asphalt reference screenshot, 2026-11-26)** | Every button is a **pill**. Three styles, each in positive (green) and destructive (red): **Filled** (solid fill, white text), **Outline** (white with a 1px coloured border and coloured text), **Tint** (light tint fill, coloured text, no border). Two sizes: **Regular** (full width, tall) and **Tiny** (short pill that hugs its text). Optional **left or right icon** (a check in a circle); **loading** replaces the label with a spinner in the label's colour; **inactive** is grey in every style (filled `#BBBBBB` with white text, outline grey border with `#6A6A6A` text, tint `#EEEEEE` with `#A9A9A9` text). Also: **swipe action** (filled or outline, a round handle with `»` on the left), **contextual action** (filled, two-line title + description on the left, an amount and an arrow-in-circle on the right) and **circular buttons** (primary: green circle with a white arrow; secondary: white circle with a dark arrow). Colours measured from the screenshot pixels, so roughly: positive green `#3B8628`, tint `#EEFEED`, destructive red `#D82E2D`, destructive tint `#FEF8F8`. Our tokens stay as they are (`brand-strong` `#008A10`, `danger` `#D22730`) until someone checks these against the Figma file. |
| **Email pictures** | Under the email header: the **Gojek support illustration** (an agent with a headset, hands together in apology, on a yellow shape with gear and code doodles; supplied by the team, `art-support.jpg`) for emails to people who reported something, where we sound sorry and caring; an **Asphalt icon tile** (filled rounded icon on a white rounded square with a soft coloured shadow) for the rest: shield (no further action), chat (contact driver), alert (warning, `warn`), lock (suspension, `high`). Images in `backend/app/assets/` (icons PNG, the illustration JPEG to keep emails light), attached inline. |
| **Alert** | Warnings and status messages. Light tint of the meaning colour, `fg` text, an icon at the start. Shown at the **top**, never over the bottom buttons. |
| **Toast** | Not used: a toast at the bottom would cover SOS. Use an Alert at the top instead. |
| **Card** | `canvas` with a 1px `line` border, `radius-card`; `shadow-low` only when it floats. Padding 16 (mobile), 20 (dashboard). |
| **Badge** | Priority, trigger and flag kind. `radius-chip`, Demi weight, a meaning colour with its tint or solid. |
| **Selection control** | Radios for the agent's decision, as cards that turn `brand-tint` when picked. Clicking the picked card again clears it ("Click again to clear" shows next to the group title), so an agent can leave the customer or the driver side without a decision. |
| **Input field** | `radius-chip`, 1px `line` border, `brand` focus ring. |
| **Marker** | Flag pins on the ride timeline, in the meaning colours. |
| **Side nav** (dashboard) | Dark (`ink`) column on desktop with the shield, "GoSafe" and the "Open cases" item (green bar marks the active item); a top bar on small screens. From GoCorp's web dashboard. |
| **Page hero** (dashboard) | `brand-strong` header with a `radius-sheet` curved bottom, white title (`title-medium`) and subtitle; the first cards overlap it. From the GoTransit app. `components/PageHero.tsx` |
| **Status pill** | Rounded pill with a coloured dot: "Waiting for an agent" (brand), "In review" (warn), "Closed" (muted). From GoCorp's "● Active". `components/StatusPill.tsx` |
| **Filter pill and search** (dashboard queue) | Asphalt "Tiny" buttons as filters: off is outline (`line` border, `muted` text), on is tint (`brand-tint`, `brand-deep` text). Search is a pill input with a magnifier. Open/Closed is a segmented control on `surface`. |
| **Bottom pattern** (dashboard) | Three soft curved waves fixed along the bottom, behind the content: `brand-tint`, then `brand` at 7% and 10%. Decoration only (`aria-hidden`). From GoTransit's background curves. |
| **Waveform** | The ride recording as rounded bars on `surface`: unplayed `muted` at 35%, played `brand` (filled smoothly up to the playhead, every frame), flagged moments in their meaning colour. Hover shows the time; click or arrow keys seek. `components/RecordingPlayer.tsx` |

## Logo

GoSafe uses its own shield mark in Gojek Green, not the Gojek logo. If the Gojek logo (*Solv*) is ever shown (brand book p. 36–67): single colour on solid backgrounds, at least 35px in digital, never stretched, outlined, rotated, shadowed or given a gradient, and no random colours.

## Writing (brand book p. 208–213)

Gojek's voice has four traits: **Clear, Casual, Witty, Empathetic**, tuned to who we're talking to and when ("we don't crack jokes with a food partner whose payment is pending").

GoSafe is about safety, so:
- **Clear and empathetic first. Never witty**: no puns or jokes in safety moments.
- **Casual but respectful** with riders: "Hey, this conversation seems to be getting uncomfortable. Let's keep it kind."
- **With drivers, clear over casual** (the brand book's rule for partners): short and sweet, actionable, polite yet personal. Titles must make sense on their own, even if the description is skipped.
- Say what happened and what we're doing: "We're on it. Our safety team will contact you right away."
- No blame in messages both people see. The warning is about the conversation, not a person.
- Sentence case everywhere ("Start ride"). Dashboard times are in WIB.

All rider-facing wording lives in the mobile app's `SafetyText`.

## Where the tokens live

| App | File |
|---|---|
| Dashboard | `dashboard/src/app/globals.css`: Tailwind `@theme` (`--color-*`, `--radius-*`, `--shadow-*`, `--text-*`, `--font-sans`) |
| Mobile | `mobile/lib/theme.dart`: `GoSafeColors`, `GoSafeType`, `goSafeTheme()` for light and dark |

## Sources

- **The Gojek Brand Book 2019**, Gojek Design: brand story, logo, colours (primary, secondary, neutrals), typography, iconography, illustration, tone of voice, composition. It was downloaded from `lelogama.go-jek.com/gojeks_brand_guideline.pdf` to read; it is not stored in this repo.
- **Asphalt (Aloha):** [foundations](https://asphalt.gojek.io/pages/foundations.html), [colours](https://asphalt.gojek.io/pages/foundations_colors.html), [typography](https://asphalt.gojek.io/pages/foundations_typography.html), [spacing](https://asphalt.gojek.io/pages/foundations_spacings.html), [shadows](https://asphalt.gojek.io/pages/foundations_shadows.html), [motion](https://asphalt.gojek.io/pages/foundations_motion.html), [principles](https://asphalt.gojek.io/pages/principles.html), [components](https://asphalt.gojek.io/pages/components.html).
- **Not read:** the Behance case study (blocks automated access), Figma and Dribbble (need a person), and Asphalt's swatch, type-scale and shadow images (missing from the site). Radii and shadow values are ours until someone checks them against the Figma file.
