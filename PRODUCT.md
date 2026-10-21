# Coco ERP and the GAMA public catalogue

<!-- impeccable:product-schema 1 -->

Scope: this brief describes the public GAMA catalogue. For internal ERP screens (Dashboard, audit trail and operational modules), use [docs/architecture.md](docs/architecture.md), [docs/modules/navigation.md](docs/modules/navigation.md) and [docs/design-system.md](docs/design-system.md).

## Platform

web

## Users

Coco ERP supports a distribution business in Quito, Ecuador. The public GAMA catalogue serves customers buying stationery, office supplies and computing equipment, alongside the other published categories. Visitors use desktop, tablet and phone browsers.

## Product Purpose

Let customers find published products, assemble a selection and request a quotation. Associated business accounts use their negotiated prices and company documents in the same catalogue.

## Operating Context

The public storefront is built separately from Coco ERP and hosted at gama-coco.pages.dev. Its configuration and catalogue come from Coco. The ERP is maintained separately in this repository.

## Capabilities and Constraints

- Preserve search, sorting, category and brand filters, product details, quantities, minimums and multiples, quotation retries, customer access and documents.
- Preserve 100 products per page and ten columns on large desktop screens, as explicitly requested by the owner.
- Public prices are indicative; the existing server rechecks quotations. No online payment is provided.
- Preserve Spanish public copy and administrator-managed settings, the actual product photographs and the notices identifying illustrative photographs.
- Edit canonical sources and run the existing build and relevant tests. No database, permission or ERP appearance change is part of this storefront redesign.

## Brand Commitments

GAMA's existing name, logo, blue and orange remain. The owner selected https://dribbble.com/shots/26664219-Grocery-Website-Design as the visual reference on 19 October 2026 and requested faithful adaptation to stationery and computing.

## Evidence on Hand

Product, category and company content comes from the existing storefront API. Category illustrations are already available under src/storefront/category-images. No evidence supports adding ratings, discounts, payment methods or delivery promises from the reference.

## Product Principles

- Keep customer tasks and permissions intact during visual work.
- Present actual catalogue information and distinguish illustrations.
- Make search, quantities and quotation actions clear on every screen size.
- Keep the public site independent of the ERP interface.
