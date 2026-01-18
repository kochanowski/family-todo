# Family To-Do App - MVP Wireframe 03: Task Form (Add/Edit)

**Data:** 2026-01-17
**Cel:** Formularz dodawania i edycji zadania

---

## Wireframe

```
╔══════════════════════════════════════════════════╗
║ [Cancel]          New Task              [Done]  ║
╠══════════════════════════════════════════════════╣
║  Title                                          ║
║  ┌───────────────────────────────────────────┐ ║
║  │ Buy milk                                  │ ║
║  └───────────────────────────────────────────┘ ║
║                                                ║
║  Details                                        ║
║  ┌───────────────────────────────────────────┐ ║
║  │ Assigned to            You           >    │ ║
║  └───────────────────────────────────────────┘ ║
║  ┌───────────────────────────────────────────┐ ║
║  │ Area                   Kitchen       >    │ ║
║  └───────────────────────────────────────────┘ ║
║  ┌───────────────────────────────────────────┐ ║
║  │ Due date               Today         >    │ ║
║  └───────────────────────────────────────────┘ ║
║  ┌───────────────────────────────────────────┐ ║
║  │ Status                 Next          >    │ ║
║  └───────────────────────────────────────────┘ ║
║  ┌───────────────────────────────────────────┐ ║
║  │ Recurring              Off        [toggle]│ ║
║  └───────────────────────────────────────────┘ ║
║                                                ║
║  Notes (optional)                               ║
║  ┌───────────────────────────────────────────┐ ║
║  │                                           │ ║
║  └───────────────────────────────────────────┘ ║
╚══════════════════════════════════════════════════╝
```

## Interakcje
- Tap `[Done]` → zapisuje zadanie
- Tap `[Cancel]` → zamyka bez zapisu
- Tap wiersz → otwiera picker (Assignee, Area, Due date, Status)
- Toggle `Recurring` → pokazuje opcje częstotliwości

## Notatki UX
- Domyślny `Status` to `Next` tylko jeśli limit WIP nie jest przekroczony
