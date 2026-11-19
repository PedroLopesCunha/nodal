# Product bundles

Bundles are Nodal products composed of two or more existing sellable variants. They have a fixed price, ordinary product categories and photos, and optional homepage placement. They have no SKU or ERP reference of their own and cannot contain other bundles or internal base variants of variable products.

## Back office

Open Products → Bundles. Create the name and price, search for each component by name or reference, select the exact variant and required quantity, and publish when ready. Homepage promotion is independent of publication; position controls the order in that section. Ordinary stock/variant editors do not edit a bundle's derived inventory.

The component section precedes pricing and previews base unit prices, required quantities, subtotals, total component value and physical bundle stock. Pricing then shows the difference in money and percent. Physical preview stock uses tracked quantities even when a sale policy permits backorders; untracked components do not impose a finite limit. This is a read-only calculation and does not reserve stock or change sale policies. A missing component price keeps its stock visible and leaves the monetary total unknown.

Saving opens the back-office bundle detail page, which shares the product information card and displays the composition, pricing comparison and calculated stock. The list's name and view action open this detail page; editing is a separate action.

## Storefront and stock

Bundles appear in the product catalogue, an automatic Bundles filter and assigned ordinary categories. Selected bundles appear in the homepage section. Individual component products link to their bundle opportunities. The bundle page lists its fixed components and compares the customer's separate-purchase prices with the bundle price; savings appear only when positive.

Members browsing without impersonation compare base prices, excluding public and customer discounts. Customer views use the discounts applicable to separate purchases, including the existing ERP commercial discount. The separate total is struck through only when there is a saving; a highlighted savings label shows the difference. Purchase controls appear above the full-width component list. In the cart, bundles share the ordinary product table and mobile card layout, with automatic quantity updates through the existing stepper and the same confirmed trash action; there is no separate save button. The component table shows separate and allocated bundle unit prices rounded to two decimals for display, with exact totals in its footer. Save-to-list sits beside the quantity selector. Availability follows the product availability setting; numeric stock and stock bands use the same stock_display_label helper and customer permission as normal products. Internal allocations retain their original precision. Related products fall back to component categories when the bundle has no categories, respecting existing visibility and related-product settings. Allocation is shared with the cart's actual component lines.

Availability comes from the least available component relative to the required quantity. Existing policies for untracked stock and backorders remain applicable to components. Finite stock is checked across all individual and bundle lines in the cart. A bundle is never partially added or capped by editing just one component. Cart changes to quantity/removal operate on the whole group. Checkout rechecks combined availability, including under an organisation policy allowing ordinary backorders.

## Prices and order history

The fixed bundle price excludes further Nodal line, customer, campaign, coupon and manual discounts. The existing ERP commercial customer discount still applies, as agreed. Bundle components are excluded from discount qualification thresholds. Percentage/fixed order adjustments and the organisation discount cap act on the ordinary lines only.

Largest-remainder allocation distributes the fixed bundle price exactly in cents among component lines. Component totals are stored separately from their rounded display unit prices, so repeated quantities do not lose cents. The unmodified ERP exporter receives real component references, quantities and net unit prices through its existing four-decimal representability check.

While a cart is a draft, a changed bundle price is refreshed through the existing price-change notification/confirmation policy. If its composition changes, the saved cart group must be removed and added again; no silent component substitution occurs. Once placed, the name, composition, quantities and amounts are historical snapshots. Reordering creates a new group from the current bundle definition and price.

## Database and validation

Two migrations add product bundle flags, component definitions, order groups and line allocation fields. The existing unique index on ordinary cart lines becomes partial; each group separately enforces one line per component variant. Positive quantities, valid amounts and foreign keys are constrained in the database. Tenant checks apply to component selection and all cart operations.

All migrations and tests during implementation run against the local test database. No production configuration, ERP connection or deployment is required to review the branch.

## Deferred: ERP discount rounding across multiple bundles

Accepted for the first version: retain the current ERP commercial discount rounding per aggregated component line. Multiplying a displayed discounted bundle price by the quantity can therefore differ from the cart total by cents. Reproduced with a EUR 99 bundle allocated as 2031, 5838 and 2031 cents before a 20% ERP discount: one bundle totals EUR 79.20; two total EUR 158.41 rather than EUR 158.40. This affects the calculated order amount, not just its display.

TODO: evaluate discount calculation per bundle and deterministic cent allocation across component lines, checking ERP export/recalculation compatibility before changing the rule. Keep storefront, cart, checkout, order, emails and PDF consistent. Do not change the ERP exporter or current pricing rule as part of the first version for this issue.

## Quick add

Bundles use the existing quick-add modal and cart counter response, with quantity selection and ERP-adjusted price. Both the organisation quick_add_enabled setting and the bundle quick_add_enabled switch must be on. The bundle switch is available in BO creation/editing using the same label and hint as products. Submissions use BundleCartService so grouped stock validation and component allocation remain unchanged; JSON validation errors keep the modal open.

Bundle component quantities are defined by the BO composition and are exempt from the component products' individual and combined purchase minimums at checkout. Ordinary lines retain their minimum rules; bundled quantities do not satisfy the combined minimum for ordinary purchases.

Confirmation emails (HTML and text), storefront order details and the PDF present each saved bundle once, with its bundle quantity and ERP-adjusted component-line total. Components use the saved composition, including references and variants, under an explicit per-bundle label. Ordinary purchases remain separate rows. No component rows are exported differently as a result of this presentation change.

## On-demand ERP component refresh

The BO bundle detail includes a component ERP sync action under the same ERP configuration and admin/owner permission as product sync. It queues a tracked job, syncs only selected component variants through the existing single-product sync service, and refreshes bundle capacity without changing the fixed bundle price. Missing/invalid references are recorded while other products continue; partial failures mark the task failed. The existing progress controller refreshes the detail on success.
