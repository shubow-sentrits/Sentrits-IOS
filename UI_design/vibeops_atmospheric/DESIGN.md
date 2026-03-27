# Design System Specification: Atmospheric Control

## 1. Overview & Creative North Star: "The Silent Navigator"
The Creative North Star for this design system is **The Silent Navigator**. In an era of loud, "hacker-chic" aesthetics and neon-drenched terminal emulators, this system chooses a path of quiet authority and organic warmth. It is designed to feel like a high-end physical studio—think matte slate surfaces, warm ambient lighting, and tactile precision.

We break the "standard app" template by leaning into **intentional atmospheric depth**. Instead of rigid grids separated by lines, we use a "topographic" layout where hierarchy is defined by light and elevation. The experience should feel expansive yet focused, providing a sense of "calm control" over complex remote operations.

---

## 2. Color Theory & Tonal Architecture
The palette moves away from sterile blacks into deep, warm charcoals and slates, using earthy accents to signal status without inducing anxiety.

### The "No-Line" Rule
**Explicit Instruction:** Solid 1px borders are prohibited for sectioning. Boundaries must be defined solely through background color shifts. To separate a session card from the main feed, place a `surface-container-high` element on a `surface` background. The transition of tone is the only permissible divider.

### Surface Hierarchy & Nesting
Treat the UI as a series of nested physical layers. 
- **Base Layer:** `surface` (#0c0e10)
- **Primary Layout Sections:** `surface-container-low` (#111416)
- **Interactive Cards:** `surface-container` (#161a1e)
- **Floating Overlays/Active Elements:** `surface-container-highest` (#20262c)

### The Glass & Gradient Rule
To achieve "High-End Editorial" polish, main CTAs and hero terminal headers should utilize a subtle linear gradient transitioning from `primary` (#bdce89) to `primary-container` (#3e4c16) at a 135-degree angle. Floating elements must use **Glassmorphism**: semi-transparent `surface-variant` with a `backdrop-filter: blur(20px)` to allow the "warmth" of the background to bleed through.

---

## 3. Typography: The Editorial Edge
The typographic system pairs the humanist clarity of **Inter** with the geometric authority of **Manrope**, punctuated by **Space Grotesk** for technical data.

- **Display & Headlines (Manrope):** Use `display-lg` to `headline-sm` for high-impact session titles. The generous tracking and scale convey a "premium magazine" feel.
- **Body & Interface (Inter):** All functional UI text uses Inter. It is the "workhorse" that ensures legibility in high-density terminal views.
- **The Technical Label (Space Grotesk):** Use `label-md` and `label-sm` for terminal tiles, git hashes, and micro-indicators. The slight eccentricity of Space Grotesk provides a "refined mono" feel without the clunkiness of traditional monospaced fonts.

---

## 4. Elevation & Depth: Tonal Layering
We reject traditional drop shadows in favor of **Ambient Light**.

- **The Layering Principle:** Depth is achieved by "stacking." A `surface-container-lowest` card placed on a `surface-container-low` section creates a natural "recessed" look. 
- **Ambient Shadows:** For floating action buttons or modal sheets, use an ultra-diffused shadow: `box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4)`. The shadow must feel like a soft glow of "un-light" rather than a hard edge.
- **The Ghost Border Fallback:** If accessibility requires a stroke (e.g., in high-glare environments), use the **Ghost Border**: `outline-variant` (#42494e) at **15% opacity**. Never 100%.

---

## 5. Signature Components

### Elegant Session Cards
- **Structure:** `surface-container` background with `xl` (1.5rem) rounded corners.
- **Micro-indicators:** Use `primary` for active git branches and `secondary` (#ffbf00) for pending changes. These should be small 4px dots or `label-sm` text—never heavy badges.
- **Spacing:** Use `spacing-4` (1.4rem) internal padding to maintain the "Editorial" breathability.

### Compact Terminal Tiles
- **Background:** `surface-container-highest` with a 10% opacity `surface-tint` overlay.
- **Typography:** High-contrast `on-surface` text using `label-md`. 
- **Interaction:** On press, the tile should scale down slightly (98%) and increase in "glow" using a subtle `primary-dim` outer shadow.

### Immersive Terminal View
- **Canvas:** Full-screen `surface-container-lowest` (#000000).
- **Header:** A glassmorphic blur bar using `surface-bright` at 60% opacity.
- **Focus Mode:** All non-essential UI elements (navigation, status bars) should fade to 20% opacity using `on-surface-variant` to ensure "Calm Control."

### Buttons & Inputs
- **Primary Button:** Gradient-fill (`primary` to `primary-container`) with `on-primary` text. No border. `xl` rounding.
- **Input Fields:** `surface-container-high` background. No border. The focus state is indicated by a subtle shift to `surface-bright` and a `primary` "Ghost Border" at 20% opacity.

---

## 6. Do’s and Don’ts

### Do:
- **Use Asymmetry:** Place status indicators or timestamps in unexpected but balanced locations (e.g., bottom-right of a card rather than top-right) to break the "grid" feel.
- **Embrace Whitespace:** Use `spacing-8` or `spacing-10` between major sections. Space is a premium material; treat it as such.
- **Soft Transitions:** All state changes (hover, active, focus) must use a minimum 300ms ease-in-out transition.

### Don’t:
- **No Divider Lines:** Never use a horizontal rule `<hr>` or border-bottom to separate content. Use a `spacing-3` gap or a tonal shift.
- **No Pure White:** Never use `#FFFFFF`. The brightest element should be `tertiary` (#f7faf8) or `on-background` (#e0e6ed) to preserve the atmospheric "warm dark" vibe.
- **No Sharp Corners:** Avoid the `none` or `sm` rounding tokens unless for 1px terminal accents. Stick to `lg` and `xl` to maintain the "Soft Minimalism" soul.