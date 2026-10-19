---
name: GAMA storefront
description: Freshly reference adapted to GAMA stationery, office supplies and computing.
colors:
  primary: "#176072"
  primary-action: "#176072"
  accent: "#e4884f"
  accent-action: "#b65325"
  on-action: "#fff"
  ink: "#20292e"
  muted: "#616b70"
  line: "#e5e9eb"
  soft: "#f7f8f8"
  surface: "#fff"
  warm: "#fbe8d9"
  primary-soft: "#eef6f6"
  danger: "#a93535"
typography:
  headline:
    fontFamily: "Inter, Arial, sans-serif"
    fontSize: "30px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.03em"
  section:
    fontFamily: "Inter, Arial, sans-serif"
    fontSize: "28px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.03em"
  title:
    fontFamily: "Inter, Arial, sans-serif"
    fontSize: "16px"
    fontWeight: 600
  body:
    fontFamily: "Inter, Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.6
  product-name:
    fontFamily: "Inter, Arial, sans-serif"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.5
  label:
    fontFamily: "Inter, Arial, sans-serif"
    fontSize: "11px"
    fontWeight: 550
    lineHeight: 1.4
  button:
    fontFamily: "Inter, Arial, sans-serif"
    fontSize: "13px"
    fontWeight: 550
    lineHeight: 1.6
  price:
    fontFamily: "Inter, Arial, sans-serif"
    fontSize: "19px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "-0.02em"
rounded:
  photo-frame: "4px"
  card: "5px"
  control: "6px"
  dialog: "8px"
  editorial: "10px"
  pill: "999px"
spacing:
  xs: "8px"
  sm: "12px"
  md: "16px"
  card: "20px"
  lg: "24px"
  heading: "28px"
  xl: "32px"
  section: "44px"
  wide: "48px"
components:
  button-primary:
    backgroundColor: "{colors.primary-action}"
    textColor: "{colors.on-action}"
    typography: "{typography.button}"
    rounded: "{rounded.pill}"
    padding: "11px 23px"
  button-outline:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary-action}"
    typography: "{typography.button}"
    rounded: "{rounded.pill}"
    padding: "11px 23px"
  button-light:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary-action}"
    typography: "{typography.button}"
    rounded: "{rounded.pill}"
    padding: "11px 23px"
  button-add:
    backgroundColor: "{colors.primary-soft}"
    textColor: "{colors.primary-action}"
    rounded: "{rounded.pill}"
    padding: "9px 13px"
  search:
    backgroundColor: "{colors.soft}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    height: "42px"
  category-filter:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "9px 14px"
  category-filter-active:
    backgroundColor: "{colors.primary-action}"
    textColor: "{colors.on-action}"
    rounded: "{rounded.pill}"
    padding: "9px 14px"
  navigation:
    rounded: "{rounded.photo-frame}"
    padding: "0 16px"
  product-card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "13px"
  category-card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "7px 5px"
  detail-tabs:
    textColor: "{colors.muted}"
    padding: "10px 4px"
---

# Design System: GAMA storefront

## Overview

**Creative North Star: "GAMA / Freshly"**

This system applies only to the public catalogue and connected customer surfaces in [src/storefront](src/storefront/). It records the implemented adaptation of the owner's [Freshly reference by Junaki](https://dribbble.com/shots/26664219-Grocery-Website-Design), selected on 19 October 2026. It does not govern Coco ERP; its [internal design system](docs/design-system.md) remains separate.

The character is compact and commercial: petrol blue anchors white surfaces, orange marks the search action, and delicate borders organize dense product information. GAMA's identity, local Inter font and actual catalogue photography remain. The catalogue composition and its owner-mandated density are recorded in the [surface brief](.impeccable/surfaces/src-storefront-index-html.md).

**Key Characteristics:**

- White, finely bordered product cards with contained photography.
- Petrol prices and primary actions; orange search cap and visible focus.
- Pill controls, restrained corners and compact labels.
- Circular category illustrations, a warm editorial panel and a full petrol footer.

The frontmatter records CSS defaults, not immutable administrator settings. [site.js](src/storefront/site.js) applies valid configured brand colors and derives action colors for white-label contrast. The sidecar’s synthesized tonal ramps are swatch previews, not additional CSS tokens. Sources of truth are [site.css](src/storefront/site.css), [customer.css](src/storefront/customer.css) and the rendered components in [index.html](src/storefront/index.html).

## Colors

The palette combines GAMA petrol and orange with cool white surfaces and a warm closing panel.

- **Primary — GAMA petrol:** identity, prices, selected controls, outline details and footer. The separate primary-action role supports configured contrast adjustment.
- **Secondary — GAMA orange:** search cap and quotation count. Deep orange supplies focus outlines, selected favorites and quotation line totals.
- **Neutral:** ink carries primary text; muted carries references and supporting copy; line separates surfaces. White remains the page and photo ground, soft appears in fields, and pale petrol marks selected or hovered controls.
- **Warm:** the pale orange editorial panel. Danger identifies existing error and destructive-action text.

**The Brand and Action Rule.** Preserve administrator brand colors; derive filled action colors with the existing contrast function instead of replacing the brand palette. The search cap uses dark text on the configured accent.

## Typography

Inter is loaded locally as a variable font; Arial and sans-serif are fallbacks. The hierarchy favors compact labels and strong prices over display typography. The frontmatter captures base roles, with these implemented contextual adjustments:

- Catalogue heading: base headline size, reduced to 24px at 600px and below.
- Product name: base product-name role; 11px in the ten-column catalogue and at 360px and below. Names wrap rather than truncate.
- Product price: base price role; 16px in the ten-column catalogue, 18px on phones, 24px in list view. Detail price is 36px, 30px at 1000px and below, and 31px at 600px and below.
- Product references, categories and supporting labels remain 11px. Prices and counts use tabular numerals.
- Customer account heading is 26px, or 23px on phones; login heading is 29px, or 26px on phones. Form inputs become 16px on phones.

## Layout

The main container is capped at 1440px, otherwise viewport width minus 96px. Its total side allowance becomes 48px at 1200px, 28px at 600px and 24px at 360px. Default sections use the section spacing token; phones use 28px vertical padding.

The catalogue retains 100 products per page, progressively painted in batches of 30 + 30 + 30 + 10. Its actual grid is:

| Viewport width | Catalogue columns | Category ribbon items visible |
| --- | ---: | ---: |
| Up to 600px | 2 | 2 |
| 601–800px | 3 | 3 |
| 801–1000px | 4 | 4 |
| 1001–1023px | 5 | 5 |
| 1024–1200px | 10 | 5 |
| Above 1200px | 10 | 6 |

The category strip stays one horizontally scrolling row. Arrows move it by 90% of its viewport, with disabled endpoints, touch scrolling and focusable category buttons. Office supplies, school supplies, computing and office equipment precede other categories. Each selection updates the existing catalogue filter.

The sticky white header contains the logo, outlined category control, search and account/quotation actions, followed by navigation and a telephone panel when configured. At 600px and below, search moves to a second row and the telephone panel is hidden. The current catalogue begins directly after the category ribbon, with no hero or separate featured-products section.

Product details use a two-column photo/information composition and stack at 600px. The quotation dialog stacks at 800px. Related products use four columns, then two at 800px; they do not inherit the ten-column catalogue. Connected customer tables scroll within their wrapper.

**The Contained Overflow Rule.** Keep long product names available and let ribbons, filters and tables scroll within their own containers rather than widening the document.

## Elevation & Depth

Cards stay flat, with a fine border and a slightly stronger hover border. Depth is reserved for the existing dialogs and transient confirmation notice. The dialog shadow is `0 24px 80px #12333c30`; the notice shadow is `0 10px 32px #102f3926`. Dialog backdrops dim the page; customer access uses its own slightly darker backdrop.

Color and border changes use 180ms. Product photos scale to 1.045 over 300ms with `cubic-bezier(.16,1,.3,1)`. Reduced motion removes CSS transitions and animations and makes category-arrow scrolling instant.

**The Flat Card Rule.** Product cards communicate hierarchy through borders, typography and photography; reserve elevation for overlays and notices.

## Shapes

Almost square cards use the card radius. The product-detail photo has a two-pixel petrol frame and the photo-frame radius. Dialogs and the editorial panel use the larger recorded corners; buttons, quantity fields and filters use the pill radius. Circular category illustrations use a 50% radius. The configured control radius affects elements that use that token; it does not replace these component-specific shapes.

## Components

- **Buttons:** primary is petrol with white text; outline is white with a fine border; light is white for colored sections. Shared buttons have a 44px minimum height. The add action starts pale petrol and fills petrol on hover. In the ten-column grid its height is 40px and the quantity field is 36px; phones retain their larger controls.
- **Search and fields:** the search is a soft pill with an orange right cap; its border turns petrol on focus. Other inputs use white surfaces and fine borders. Public keyboard focus is a three-pixel deep-orange outline with a three-pixel offset; customer buttons and favorites use petrol focus.
- **Filters and navigation:** category filter pills fill petrol when selected. Header navigation is a small outlined horizontal strip, unframed on phones. Customer navigation uses horizontally scrolling pills and a petrol current state.
- **Category ribbon:** illustration circles sit beside wrapping labels and live counts. The existing category illustration mapping supplies images; unmapped categories use the box SVG fallback. Hover and selected states use pale petrol and a subtle border.
- **Product cards:** white square image space, category, reference/brand pill, bold price, full name and quantity/action. Photos use `object-fit: contain`; product photographs and “Foto ilustrativa” notices remain intact. List view additionally exposes description and availability information.
- **Product detail:** a single actual photo, title/reference, price and quantity form, followed by real description/additional-information tabs and up to four published related products. Tabs support arrows, Home and End; additional information is initially selected. Do not fabricate a gallery when the data supplies one image.
- **Quotation and customer surfaces:** retain the existing consent, status, retry and customer-access behavior. The shared photo, form, pill and table treatment applies within the storefront only. Authored action icons are inline stroke SVGs.

## Do's and Don'ts

### Do:

- **Do** preserve GAMA's logo, administrator copy and Spanish interface labels.
- **Do** preserve actual product photos, full names and illustrative-photo notices.
- **Do** retain 100 products per page and ten catalogue columns from 1024px.
- **Do** use the same storefront palette and controls before and after customer login.
- **Do** keep keyboard focus visible and respect reduced motion.

### Don't:

- **Don't** apply this storefront system to the ERP modules.
- **Don't** invent ratings, discounts, payment methods or delivery promises from the reference.
- **Don't** add a hero or separate featured-products section to the current catalogue composition.
- **Don't** substitute category illustrations for product photography or invent alternate product views.
- **Don't** change quotations, permissions or customer scope as a visual styling decision.
