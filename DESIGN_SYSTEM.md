# Veya design system

## Identity

**Veya** is a short, friendly working brand name, chosen to feel like a daily companion. The promise is “Your voice, beautifully expressed.” The icon uses five rounded sound bars inside a deep-teal tile; the rhythm peaks at the center. SVG, PNG, Android adaptive/themed and iOS icon assets are included.

## Colour

| Token | Hex | Role |
|---|---|---|
| Ink | `#173F38` | Headlines, icon background, hero |
| Teal | `#235B4E` | Primary controls |
| Paper | `#F7F8F2` | Page background |
| Lime | `#D9F291` | Primary hero action and waveform |
| Soft | `#ECF1E6` | Secondary surfaces |
| Peach | `#F7E8D9` | Drafting and gentle callouts |
| Muted | `#73817B` | Supporting copy |
| Line | `#E5E9DF` | Quiet separators |

## Typography and rhythm

Manrope is bundled rather than fetched at runtime. Display headlines are 36/41px with tight tracking; page titles are 28px; card titles are 20px; primary body copy is 16px with 1.6 line height. Labels use sentence case; small editorial labels use spaced capitals.

Page margins are 24px, spacing follows a 4px rhythm, cards use 24px radii and primary buttons use 18px radii. Main actions have 50–54px minimum height. Layouts use scrolling rather than fixed phone-height assumptions; content width is capped for tablets and desktop.

## Components and behavior

- Four persistent destinations: Home, History, Dictionary, Settings.
- Language is visible near the top; choose it in a bottom sheet.
- The recording control changes both text and icon when active, and shows a moving waveform.
- Tone choices are named in plain language; transformation is explicit.
- The original and result are distinct editable areas. Changing the source removes stale output.
- Empty states suggest the next useful action, without fabricated activity or statistics.
- Transient deletes offer Undo. Clearing all history requires a confirmation because it is irreversible.
- Error states preserve the user's words and point to the next action.
- The Android sheet uses native controls to keep cross-app dictation independent of Flutter navigation.

Canonical Flutter tokens: `lib/core/theme.dart`. Shared components: `lib/widgets/shared.dart`. Native values mirror the Flutter palette.
