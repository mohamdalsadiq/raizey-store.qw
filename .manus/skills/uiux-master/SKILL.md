---
name: uiux-master
description: Advanced UI/UX, Web Design Systems, Responsive Layouts, and Tailwind CSS Best Practices.
---

# UI/UX & Web Design Mastery

## Core Guidelines
- Implement modern, responsive, mobile-first design architectures.
- Enforce strict WCAG 2.1 AA accessibility standards (contrast ratios, clean focus rings, proper ARIA labels).
- Use dynamic theme tokens for seamless Dark/Light mode support.
- Apply consistent 8px spacing scales and refined visual hierarchy for typography.
- Ensure all interactive elements have rich state feedback (hover, focus, active, disabled).

## Source Provenance

The URL requested for retrieval was:

`https://raw.githubusercontent.com/patrickjs/awesome-cursorrules/main/rules/tailwind-css-best-practices.md`

That exact path currently returns HTTP 404. The repository's current canonical Tailwind rule file, `rules/tailwind.mdc`, was retrieved from the same repository and its rule content is included below without changing its guidance. Re-check the requested URL before replacing this source in a future update.

## Tailwind CSS Best Practices

### Project Setup

- Use proper Tailwind configuration.
- Configure theme extension properly.
- Set up proper purge configuration.
- Use proper plugin integration.
- Configure custom spacing and breakpoints.
- Set up a proper color palette.

### Component Styling

- Use utility classes over custom CSS.
- Group related utilities with `@apply` when needed.
- Use proper responsive design utilities.
- Implement dark mode properly.
- Use proper state variants.
- Keep component styles consistent.

### Layout

- Use Flexbox and Grid utilities effectively.
- Implement a proper spacing system.
- Use container queries when needed.
- Implement proper responsive breakpoints.
- Use proper padding and margin utilities.
- Implement proper alignment utilities.

### Typography

- Use proper font-size utilities.
- Implement proper line-height.
- Use proper font-weight utilities.
- Configure custom fonts properly.
- Use proper text alignment.
- Implement proper text decoration.

### Colors

- Use semantic color naming.
- Implement proper color contrast.
- Use opacity utilities effectively.
- Configure custom colors properly.
- Use proper gradient utilities.
- Implement proper hover states.

### Components

- Use shadcn/ui components when available.
- Extend components properly.
- Keep component variants consistent.
- Implement proper animations.
- Use proper transition utilities.
- Keep accessibility in mind.

### Responsive Design

- Use a mobile-first approach.
- Implement proper breakpoints.
- Use container queries effectively.
- Handle different screen sizes properly.
- Implement proper responsive typography.
- Use proper responsive spacing.

### Performance

- Use proper purge configuration.
- Minimize custom CSS.
- Use proper caching strategies.
- Implement proper code splitting.
- Optimize for production.
- Monitor bundle size.

### Best Practices

- Follow naming conventions.
- Keep styles organized.
- Use proper documentation.
- Implement proper testing.
- Follow accessibility guidelines.
- Use proper version control.

## Implementation Workflow

1. Inspect the existing design tokens, component primitives, typography, and layout constraints before changing code.
2. Preserve the product's existing brand language unless the task explicitly requests a rebrand.
3. Define or reuse semantic theme tokens before adding one-off colors, spacing, radii, or shadows.
4. Build mobile-first, then verify tablet and desktop breakpoints without allowing text or controls to collapse.
5. Prefer semantic HTML, keyboard-accessible controls, visible `:focus-visible` states, and meaningful ARIA labels.
6. Give every interactive element clear hover, focus, active, disabled, loading, success, and error feedback where applicable.
7. Keep responsive spacing on a consistent 8px-derived scale and use typography hierarchy to encode information rather than decoration.
8. Use utility classes for Tailwind projects; keep custom CSS small, intentional, and documented when utilities are insufficient.
9. Use `object-fit`, aspect-ratio containers, and intrinsic sizing deliberately so images remain complete and do not create layout shifts.
10. Test representative mobile widths, long Arabic and English text, keyboard navigation, reduced motion, and empty/error states before delivery.
11. Review the result visually and remove unnecessary decoration; reserve the strongest visual emphasis for the page's primary action.


## Section 2: Application Security & Database Hardening (SEC)

- **Input Sanitization & Schema Validation:** Enforce strict runtime schema validation, such as Zod, on all API payloads. Never trust client data.
- **Data Isolation & RLS:** Enable and strictly enforce Row Level Security (RLS) or tenant-isolation policies on all database tables.
- **Atomic Transactions & Race Conditions:** Wrap all financial, balance, or transactional state changes inside safe database functions or RPCs with row locking to eliminate race conditions.
- **SQL Injection & XSS Shielding:** Use parameterized ORM queries exclusively. Escape all dynamically rendered user strings.
- **API Rate Limiting & Auth Validation:** Secure all public and private API endpoints with rate-limit middleware, secure JWT/session verification, and properly scoped CORS settings.
- **Zero Credentials Policy:** Ensure that no secrets, private keys, or database credentials exist in public client bundles or version control. Use environment variables strictly.

## Section 3: Performance & Smooth User Experience (Perf UX)

- **Core Web Vitals Optimization:** Maintain LCP below 2.5 seconds, CLS below 0.1, and FID/INP below 100 milliseconds where the target environment supports those measurements.
- **Asset Optimization:** Implement lazy loading for images, use WebP/AVIF media formats where supported, and configure proper static-asset caching.
- **Optimistic UI Updates:** Apply immediate visual updates for interactive elements such as likes, items added to a cart, and state toggles, with automatic rollback on server errors.
- **Skeleton Loaders:** Replace raw loading spinners with skeleton screens to reduce perceived latency and communicate the shape of incoming content.

## Section 4: AI Engine & Native LLM Integrations

- **Streaming Responses:** Support chunked UI rendering through SSE or WebSockets for real-time AI responses and live status updates.
- **Structured JSON Outputs:** Force AI APIs to return strict JSON-schema data to prevent parse errors during UI rendering.
- **Graceful Degradation:** Provide fallback UIs and bounded automatic retry policies when AI services or external APIs experience downtime, rate limits, or timeouts.

## Section 5: Code Quality & Enterprise Standards

- **Clean Architecture:** Keep UI components modular and highly reusable, with a strict separation between presentation, business logic, data access, and API hooks.
- **Strict Typing:** Enforce explicit TypeScript types across all API payloads, database schemas, server responses, and component interfaces.
- **Error Handling & Toast Notifications:** Wrap asynchronous operations in global error boundaries where applicable and present user-friendly Toast notifications without revealing system stack traces, secrets, or internal implementation details.

## Fullstack Delivery Checklist

Before delivery, verify the complete request path rather than only the visual layer. Validate untrusted input at the boundary, authorize the current user or tenant, execute sensitive state changes atomically, and return only the minimum response data required by the UI. Confirm that failures are observable to developers but understandable and safe for end users.

For every performance-sensitive page, verify loading, empty, error, retry, success, and disabled states. Measure representative mobile and desktop layouts, confirm that images do not cause layout shifts, and ensure keyboard, reduced-motion, and screen-reader behavior remains usable. Keep credentials out of source control and inspect the final bundle for accidental exposure before publishing.

## Section 6: Data Hierarchy & E-Commerce Architecture Rules (CRITICAL)

- **Strict Data Scoping:** Never merge Categories, Sub-Categories, and Multi-variant Product logic into a flat array or complex hybrid UI. Keep each level independently scoped in data fetching, state, rendering, and CRUD operations.
- **Optional Form Fields:** Never enforce nested sub-variant dynamic inputs unless explicitly toggled by the admin user. Standard products must support simple single-price creation without mandating variants.
- **Clean Naming Conventions:** Standardize UI terms strictly to:
  1. `Category` (قسم رئيسي)
  2. `Subcategory / Brand` (تصنيف / باقة)
  3. `Product Variant` (المنتج التفصيلي والخيارات)
- **Zero Regression Principle:** Before altering database schemas or UI controllers for catalog structures, strictly preserve independent CRUD flows for primary categories and individual products. Validate existing create, read, update, delete, selection, cart, checkout, and admin permission flows before delivery.
