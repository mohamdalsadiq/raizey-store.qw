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
