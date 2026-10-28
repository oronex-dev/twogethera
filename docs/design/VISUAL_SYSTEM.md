# Twogethera visual system · CP-003A

Status: **visual direction approved by the user**. Product/architecture decisions D01–D11 remain pending. This visual work does not amend their proposals or implement the product data model.

## Identity

The original Together mark pairs rose and lavender loop forms with a peach highlight and reflected-light strokes. It is drawn with a Flutter CustomPainter in `lib/shared/widgets/together_mark.dart`, scales to its bounds, and requires no downloaded artwork, font, paid service, raster asset, blur filter, or animation dependency. The shadow is a simple translucent path, not a live blur. It remains decorative in accessibility semantics; the accompanying Twogethera wordmark supplies the name.

This is a proposed visual identity for review, not a trademark clearance or final store-icon package. Flutter-generated app/launcher icons remain unchanged for this phase.

## Color and typography

| Token / role | Light | Dark / usage |
| --- | --- | --- |
| Canvas | `#FAF8F6` warm porcelain | `#17141C` plum charcoal |
| Panel | `#FFFFFF` | `#231F2A` |
| Border | `#E7DFE7` | `#443A4C` |
| Hero gradient | `#F8EBED` → `#EDE7F8` | `#30243B` → `#382530` |
| Primary seed | Rosewood `#8E3F62` | Material-generated accessible foreground/container pairs |
| Secondary seed | `#75528C` | Material-generated secondary pairs |
| Decorative palette | Quiet lilac `#BA9CE9`, first light `#FFE3D5` | Artwork/swatches; not assumed safe as arbitrary text colors |

`BrandColors` is a ThemeExtension with copy/lerp support; Material ColorScheme supplies semantic on-surface, on-container, interactive, disabled, and focus states. Avoid manually putting white text on light decorative gradients. Palette labels retain readable foregrounds and hexadecimal values so information never depends on color alone.

Typography uses Flutter's bundled/default platform-compatible typography, with no added font package, custom remote-font loader, or proprietary Apple font files. Flutter web engine assets/font fallbacks retain SDK defaults; offline/PWA delivery is not verified in this phase. Display: 54 px, weight 600, 1.08 height, -2 tracking; compact headline: 34 px, weight 600, 1.15 height, -1 tracking; titles: 21 px, weight 600; body: 16 px, 1.6 height. These are logical-pixel defaults; system text scaling is preserved rather than clamped. The larger display style is used only when sufficient content width is available.

## Layout and navigation

| Viewport / condition | Navigation | Content behavior |
| --- | --- | --- |
| Under 600 logical px | Material bottom navigation | One-column wrapping content |
| Under 600 with scaled 14 px text above 20 px | Accessible drawer via app bar | Avoid crowded bottom labels; existing home/back action retained |
| 600–1099 | Material navigation rail; tooltips, icon-only at large text | Content-aware one/two-column cards, scrollable rail on short screens |
| 1100 and above | 236 px sidebar | Bounded editorial content, up to three cards per row |

Content max width is 1200 px. Page padding is 20 px below 720 content pixels and 40 px above; cards generally use 24 px, hero 28 px. Layout spacing tokens are 8, 12, 20, 28, 40 px. Hero radius: 32; panel radius: 28; controls: 16. Card rows wrap and grow with text, rather than fixing their heights. AdaptiveGrid accounts for text scale when choosing column count. Mobile/tablet hero layouts switch according to available content width, not device names.

All three navigation destinations are actual GoRouter routes inside an adaptive ShellRoute:

- `/`: refined home preview, retaining the original headline and foundation navigation intent.
- `/studio`: visual language and interactive component gallery.
- `/settings`: existing working system/light/dark theme choice, restyled without persistence.

Unknown-route recovery remains available. The router provider lifecycle, root ProviderScope, app bootstrap, configuration, and global error handling remain intact. Router navigation improves presentation only; it does not introduce authentication/authorization behavior.

## Reusable components

| Component | Purpose |
| --- | --- |
| `BrandColors`, `AppSpace`, `AppLayout` | Semantic brand surfaces, spacing, and viewport/content bounds |
| `TogetherMark` | Original scalable static vector identity |
| `AdaptiveShell` | Bottom navigation, large-text drawer, rail, and sidebar with selected/focus states |
| `ResponsivePage` | Safe-area bounded scrolling and full available content width |
| `SurfaceCard` | Shared panel shape/border/padding |
| `SectionHeading` | Heading semantics plus readable supporting text |
| `PreviewBadge` | Content-sized status label using a semantic container pair |
| `AdaptiveGrid` | Content-sized wrapping cards responsive to width and text scale |
| `IdeaCard` | Reusable noninteractive editorial preview card |
| Material themed controls | Filled/outlined buttons, choice chips, switch, radio group, text field, feedback snackbar, and disabled state |

Studio accent/spacing/input choices are ephemeral widget state and reset after leaving/re-entering the route. They do not alter account preferences, store notes, simulate synchronization, or implement planner features. The global appearance choice continues to last only for the running session. Home editorial cards are intentionally static and do not pretend to open completed product modules. Both home actions open the Studio.

## Accessibility and motion

- Native Material controls retain keyboard focus, hover, disabled, selected, and screen-reader semantics.
- Navigation, theme selection, feedback dismissal, and all active actions have accessible names.
- Active buttons have at least 48×52 logical-pixel minimum size; standard navigation/chip controls retain Material tap-target padding.
- Decorative artwork/swatches are excluded from semantics; section titles are marked as headings. Color swatches also have textual names/values.
- Text scales normally; long copy wraps, cards grow, content scrolls, and large-text mobile navigation uses a drawer.
- No continuously running animation, parallax, flashing, simulated loading, or custom motion is introduced. Normal Material interaction/theme transitions remain.
- Automated guideline checks cover text contrast, labels, and Android-sized tap targets (48 px) across all three screens in both themes. This does not substitute for VoiceOver/TalkBack testing on physical devices.

## Review

The app is intentionally a visual foundation: no accounts, couple linking, migrations, Supabase connections, persistence, financial records, calendars, or implemented planner modules. D01–D11 are still awaiting explicit product decisions. The [implementation report](../CP-003A.md) records the exact verification and limitations; the accompanying preview gallery shows actual Flutter renders.
