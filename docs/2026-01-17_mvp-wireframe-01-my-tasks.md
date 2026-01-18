# Family To-Do App - MVP Wireframe 01: My Tasks

**Data:** 2026-01-17
**Cel:** Główny ekran zadań użytkownika (Next/Backlog/Done)

---

## Wireframe

```
╔══════════════════════════════════════════════════╗
║  9:41                                     100%  ║
╠══════════════════════════════════════════════════╣
║  My Tasks                              [+ Add]  ║
║                                                ║
║  ┌───────────┬───────────┬───────────┐         ║
║  │   Next    │  Backlog  │   Done    │         ║
║  │  [===]    │           │           │         ║
║  └───────────┴───────────┴───────────┘         ║
║                                                ║
║  TODAY                                         ║
║  ┌───────────────────────────────────────────┐ ║
║  │ [ ] Buy milk                              │ ║
║  │     Area: Kitchen · Assignee: You         │ ║
║  │     Due: Today                            │ ║
║  └───────────────────────────────────────────┘ ║
║                                                ║
║  THIS WEEK                                     ║
║  ┌───────────────────────────────────────────┐ ║
║  │ [ ] Clean bathroom                        │ ║
║  │     Area: Bathroom · Assignee: Partner     │ ║
║  │     Due: Friday                           │ ║
║  └───────────────────────────────────────────┘ ║
║                                                ║
║  Notice: Next has 3 tasks (limit reached)     ║
║                                                ║
╠══════════════════════════════════════════════════╣
║ [My Tasks]     [Household]     [Settings]       ║
╚══════════════════════════════════════════════════╝
```

## Interakcje
- Tap na zadaniu → Task Detail
- Swipe right → Mark as Done (przenosi do Done)
- Swipe left → Szybkie akcje (Edit, Delete)
- Tap `[+ Add]` → otwiera modal Add Task
- Tap segment → zmiana widoku (Next/Backlog/Done)
- Pull to refresh → synchronizacja

## Notatki UX
- WIP limit: max 3 zadania w `Next`
- Sekcje `TODAY` i `THIS WEEK` grupują zadania po czasie
