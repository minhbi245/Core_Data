# Cookbook App — Core Data Learning Plan

**Mục tiêu:** Học và làm chủ Core Data qua việc xây dựng ứng dụng quản lý công thức nấu ăn.
**Stack:** UIKit + SnapKit + Combine + Core Data | MVVM + Clean Architecture | iOS 15+
**Repo:** https://github.com/minhbi245/Core_Data

---

## Phases

| # | Phase | Core Data Concept | Status |
|---|-------|-------------------|--------|
| 1 | [Project Setup & Core Data Stack](phase-01-project-setup-core-data-stack.md) | NSPersistentContainer, .xcdatamodeld, Entities | [ ] |
| 2 | [Domain Layer & Repository Pattern](phase-02-domain-layer-repository-pattern.md) | NSFetchRequest, NSPredicate, context.save() | [ ] |
| 3 | [Recipe List & NSFetchedResultsController](phase-03-recipe-list-fetched-results-controller.md) | NSFetchedResultsController, sections, delegate | [ ] |
| 4 | [Create & Edit Recipe](phase-04-create-edit-recipe.md) | Relationships, ordered sets, many-to-many | [ ] |
| 5 | [Recipe Detail & Delete](phase-05-recipe-detail-delete.md) | Cascade delete, fetch by ID, update | [ ] |
| 6 | [Category Management](phase-06-category-management.md) | Aggregate fetch, Nullify delete rule | [ ] |
| 7 | [Background Context & Batch Operations](phase-07-background-context-batch-operations.md) | newBackgroundContext, perform{}, batch ops | [ ] |
| 8 | [Data Migration](phase-08-data-migration.md) | Model versioning, lightweight migration | [ ] |
| 9 | [Testing Core Data](phase-09-testing-core-data.md) | NSInMemoryStoreType, test isolation | [ ] |

---

## Key Dependencies
- Xcode project: **tạo thủ công** (user tạo trong Xcode, không dùng CLI)
- SPM: SnapKit 5.0+, Kingfisher 7.0+
- Core Data model: 6 entities (Recipe, Category, Step, Ingredient, RecipeIngredient, Tag)

## Folder Structure
```
CookbookApp/
├── App/               # AppDelegate, SceneDelegate
├── Data/              # CoreData stack, repositories, NSManagedObject subclasses
├── Domain/            # Swift structs (entities), protocols, use cases
├── Presentation/      # ViewControllers, ViewModels, Views
└── Utilities/         # Extensions, constants, helpers
```

## Học Lộ Trình (Learning Path)
- **Phase 1–2:** Nền tảng (setup + data layer) — hiểu cách Core Data hoạt động
- **Phase 3–6:** Xây tính năng — áp dụng Core Data vào UI thực tế
- **Phase 7–9:** Nâng cao — concurrency, migration, testing
