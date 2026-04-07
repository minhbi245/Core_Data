# Cookbook App — Project Overview (PDR)

## Mục Tiêu
Xây dựng ứng dụng quản lý công thức nấu ăn (Cookbook) như một phương tiện học và làm chủ Core Data trên iOS.

## Tech Stack
| Layer | Technology |
|-------|-----------|
| Language | Swift 5.9+ |
| UI Framework | UIKit + SnapKit 5.0+ |
| Reactive | Combine (built-in) |
| Persistence | Core Data (NSPersistentContainer) |
| Image Loading | Kingfisher 7.0+ |
| Dependency Management | Swift Package Manager (SPM) |
| Architecture | MVVM + Clean Architecture |
| Min iOS | 15.0 |

## Architecture Layers
```
Presentation/    ← ViewControllers, ViewModels (Combine bindings)
Domain/          ← Swift Structs (entities), Protocols, UseCases
Data/            ← Core Data Stack, Repositories (implement protocols)
Utilities/       ← Extensions, Constants, Helpers
```

## Core Data Entity Model
```
Recipe ──────────────────────────────────────────────────────┐
  ├── [many-to-one,  Nullify]  → Category (name, icon)       │
  ├── [one-to-many,  Cascade]  → Step (orderIndex, instr.)   │
  ├── [one-to-many,  Cascade]  → RecipeIngredient            │
  │       └── [many-to-one, Nullify] → Ingredient (name)     │
  └── [many-to-many, Nullify]  ↔ Tag (name, colorHex)        │
                                                              │
Recipe attributes: id, name, description, cookTime,          │
  prepTime, servings, rating, isFavorite, createdAt,          │
  imageData, difficulty (v2), notes (v2)                      │
└────────────────────────────────────────────────────────────┘
```

## App Screens
1. **Recipe List** — UITableView + NSFetchedResultsController, sectioned by Category
2. **Recipe Detail** — ScrollView với hero image, stats, ingredients, steps
3. **Create/Edit Recipe** — Inset grouped UITableView form
4. **Category Management** — UITableView với swipe actions

## Learning Path (9 Phases)
| Phase | Concept |
|-------|---------|
| 1 | NSPersistentContainer, .xcdatamodeld, Entities, Relationships |
| 2 | NSFetchRequest, NSPredicate, NSSortDescriptor, Repository Pattern |
| 3 | NSFetchedResultsController, sections, delegate |
| 4 | Insert/update objects, ordered relationships, many-to-many |
| 5 | Cascade delete, fetch by ID, update single attribute |
| 6 | Aggregate fetch (COUNT), Nullify delete rule |
| 7 | Background context, perform{}, batch insert/delete |
| 8 | Model versioning, lightweight migration |
| 9 | In-memory store testing, mock repositories |

## Key Design Decisions
- **Repository Pattern:** ViewModel không biết Core Data tồn tại — phụ thuộc vào protocol
- **DTO Pattern:** NSManagedObject ↔ Domain Swift Struct — thread-safe, testable
- **Simple Navigation:** Push/pop (no Coordinator) — giữ focus vào Core Data learning
- **Local-Only First:** Không có CloudKit sync ở v1 — simplicity over features
- **Image Storage:** `imageData: Data?` trong Core Data + "Allows External Storage" enabled

## GitHub
Repository: https://github.com/minhbi245/Core_Data
