# Family To-Do App - Documentation

This directory contains all technical documentation, guides, and architecture decision records for the Family To-Do App project.

## 📚 Documentation Index

### Getting Started Guides

- **[CloudKit Setup Guide](2026-01-10_cloudkit-setup-guide.md)** - Complete guide to configure CloudKit backend for iOS app
- **[GitHub Actions Setup](2026-01-10_github-actions-setup.md)** - Configure CI/CD pipeline for automated builds and TestFlight deployment

### Technical Reference

- **[CloudKit Schema](2026-01-11_cloudkit-schema.md)** - Complete database schema: entities, fields, relationships, and Swift models

### Design Documentation

- **[Core Screens Wireframes](2026-01-12_core-screens-wireframes.md)** - Low-fidelity wireframes for all MVP screens (Home, Task Create, Settings, Invitations)
- **[Cards UI Spec](2026-01-18_cards-ui-spec.md)** - Book-style card pager with glass UI and interactions

### Concepts Explained

- **[ADR Explained](2026-01-10_adr-explained.md)** - What are Architecture Decision Records and how to use them
- **[Wireframe Explained](2026-01-10_wireframe-explained.md)** - What are wireframes, tools, and best practices for iOS UX design

### Future Features Documentation

Comprehensive guides for post-MVP features with implementation instructions, cost estimates, and trade-off analysis:

- **[Analytics Explained](2026-01-10_analytics-explained.md)** - App Store Connect analytics and metrics (FREE, automatic)
- **[Monetization Explained](2026-01-10_monetization-explained.md)** - In-app purchases, subscriptions, StoreKit 2 implementation
- **[Localization Explained](2026-01-10_localization-explained.md)** - Multi-language support with DIY AI translation approach
- **[Testing Strategy](2026-01-10_testing-strategy.md)** - Unit, UI, and integration testing approaches and trade-offs
- **[Marketing Strategy](2026-01-11_marketing-strategy-explained.md)** - App promotion, advertising channels, ASO, launch strategy ($50-200/month budget)
- **[Getting Started Checklist](2026-01-10_getting-started-checklist.md)** - Prerequisites and steps to begin development

### Architecture Decision Records (ADRs)

- **[ADR-001: CloudKit Backend](2026-01-10_adr-001-cloudkit-backend.md)** - Decision to use CloudKit as backend for Family To-Do App
- **[ADR-002: Error Handling & Offline-First](2026-01-12_adr-002-error-handling-offline-first.md)** - Offline-first architecture, conflict resolution (Last-Write-Wins), and error handling strategy

---

## 📁 Documentation Structure

```
docs/
├── README.md                                    ← You are here
│
├── Getting Started Guides:
│   ├── 2026-01-10_cloudkit-setup-guide.md      ← CloudKit setup instructions
│   ├── 2026-01-10_github-actions-setup.md      ← GitHub Actions CI/CD setup
│   └── 2026-01-10_getting-started-checklist.md ← Development prerequisites
│
├── Technical Reference:
│   └── 2026-01-11_cloudkit-schema.md           ← Database schema documentation
│
├── Design Documentation:
│   ├── 2026-01-12_core-screens-wireframes.md   ← MVP screen wireframes
│   └── 2026-01-18_cards-ui-spec.md             ← Book-style card UI spec
│
├── Concepts Explained:
│   ├── 2026-01-10_adr-explained.md             ← ADR methodology
│   └── 2026-01-10_wireframe-explained.md       ← UX design wireframes
│
├── Future Features (Post-MVP):
│   ├── 2026-01-10_analytics-explained.md       ← App metrics & tracking
│   ├── 2026-01-10_monetization-explained.md    ← In-app purchases & subscriptions
│   ├── 2026-01-10_localization-explained.md    ← Multi-language support
│   ├── 2026-01-10_testing-strategy.md          ← Automated testing approaches
│   └── 2026-01-11_marketing-strategy-explained.md ← App promotion & advertising
│
└── Architecture Decision Records (ADRs):
    ├── 2026-01-10_adr-001-cloudkit-backend.md  ← ADR #001: CloudKit choice
    └── 2026-01-12_adr-002-error-handling-offline-first.md ← ADR #002: Offline-first & errors
```

---

## 🎯 Quick Links

### For Developers

**Starting development?**
1. Read [CLAUDE.md](../CLAUDE.md) - Project overview and design principles
2. Read [instructions.md](../instructions.md) - Product requirements (Polish)
3. Review [CloudKit Schema](2026-01-11_cloudkit-schema.md) - Understand data model
4. Review [Core Screens Wireframes](2026-01-12_core-screens-wireframes.md) - See UX design
5. Follow [CloudKit Setup Guide](2026-01-10_cloudkit-setup-guide.md)
6. Setup [GitHub Actions](2026-01-10_github-actions-setup.md)

**Making architectural decisions?**
1. Read [ADR Explained](2026-01-10_adr-explained.md)
2. Review existing ADRs (ADR-001, ADR-002)
3. Create new ADR when needed

**Designing UI?**
1. Read [Wireframe Explained](2026-01-10_wireframe-explained.md)
2. Review [Core Screens Wireframes](2026-01-12_core-screens-wireframes.md)
3. Follow iOS Human Interface Guidelines
4. Create low-fidelity wireframes before coding

### For Product/UX

**Understanding the product?**
- [instructions.md](../instructions.md) - Full product requirements
- [CLAUDE.md](../CLAUDE.md) - Core design principles and domain model
- [Wireframe examples](2026-01-10_wireframe-explained.md#wireframe-dla-recurring-chores-family-to-do)

---

## 📝 Documentation Conventions

### File Naming

All documentation files follow this pattern:
```
YYYY-MM-DD_descriptive-title.md
```

**Examples:**
- `2026-01-10_cloudkit-setup-guide.md`
- `2026-01-10_adr-001-cloudkit-backend.md`

### ADR Numbering

ADRs are numbered sequentially:
```
adr-001-short-title.md
adr-002-short-title.md
adr-003-short-title.md
```

### Language

- **Code & Technical Docs:** English
- **Product Requirements:** Polish (instructions.md)
- **Comments:** English only

---

## 🚀 Contributing Documentation

When adding new documentation:

1. **Follow naming convention:** `YYYY-MM-DD_title.md`
2. **Add entry to this README** in appropriate section
3. **Include metadata:**
   ```markdown
   **Date:** YYYY-MM-DD
   **Project:** Family To-Do App
   **Purpose:** Brief description
   ```
4. **Keep it practical:** Focus on actionable information
5. **Use examples:** Show, don't just tell

---

## 📌 Important Files Outside docs/

- **[CLAUDE.md](../CLAUDE.md)** - Developer guidance for Claude Code
- **[instructions.md](../instructions.md)** - Product requirements (Polish)
- **[.github/workflows/ios-ci.yml](../.github/workflows/ios-ci.yml)** - CI/CD pipeline
- **[ExportOptions.plist](../ExportOptions.plist)** - iOS build export config
- **[.swiftlint.yml](../.swiftlint.yml)** - Swift code style rules

---

## 🔗 External Resources

- [iOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [CloudKit Documentation](https://developer.apple.com/documentation/cloudkit)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [GitHub Actions for iOS](https://docs.github.com/en/actions/deployment/deploying-xcode-applications)

---

**Last Updated:** 2026-01-18
