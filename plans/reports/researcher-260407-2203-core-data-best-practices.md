# Core Data Best Practices: Cookbook App Research
**Date:** April 7, 2026 | **Target:** iOS 15+ | **Architecture:** MVVM + Clean Architecture

---

## 1. Core Data Stack Setup (iOS 15+)

### Recommendation: NSPersistentContainer (Standard Path)
**Why:** For local-first Cookbook app without CloudKit sync. Simpler, proven, zero overhead.

```swift
// ✅ Recommended Pattern - Singleton DataController
class DataController {
    static let shared = DataController()
    let container: NSPersistentContainer
    var viewContext: NSManagedObjectContext { container.viewContext }
    
    init() {
        container = NSPersistentContainer(name: "Cookbook")
        // Critical: Set concurrency type BEFORE loading
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        container.loadPersistentStores { storeDescription, error in
            if let error {
                fatalError("Failed to load store: \(error)")
            }
        }
    }
}
```

**If CloudKit sync needed later:** Use `NSPersistentCloudKitContainer` instead (requires entitlements, identical API).

---

## 2. Entity Design: Cookbook Schema

### Core Entities & Relationships

```
Recipe
├── name: String
├── description: String
├── prepTime: Int16 (minutes)
├── cookTime: Int16
├── servings: Int16
├── imageData: Data? (or store URL)
└── Relationships:
    ├── category: Category (many-to-one, Cascade delete)
    ├── ingredients: [RecipeIngredient] (one-to-many, Cascade)
    ├── steps: [Step] (one-to-many, Cascade)
    └── tags: [Tag] (many-to-many, Nullify)

Category
├── name: String (unique, use validation)
└── recipes: [Recipe] (inverse)

RecipeIngredient (Join Entity)
├── quantity: Double
├── unit: String (enum: "cup", "tbsp", "g", etc.)
├── ingredient: Ingredient
└── recipe: Recipe

Ingredient
├── name: String (unique)
└── recipeIngredients: [RecipeIngredient]

Tag
├── name: String (unique)
└── recipes: [Recipe]

Step
├── order: Int16 (for sorting)
├── instruction: String
└── recipe: Recipe
```

### Critical Relationship Rules
- **Inverse relationships: ALWAYS set both directions.** (FRC breaks silently if missing inverse)
- **Delete Rules:**
  - Recipe → Steps/Ingredients: **Cascade** (orphans invalid)
  - Recipe → Category: **Nullify** (categories persist)
  - Recipe → Tags: **Nullify** (tags reusable)
- **RecipeIngredient:** Cascade from both parents (cleanup when recipe/ingredient removed)

---

## 3. Repository Pattern with Core Data

```swift
// Core abstraction - NO Core Data imports in ViewModels
protocol RecipeRepository {
    func fetchRecipes(category: String?) -> [Recipe]
    func saveRecipe(_ recipe: Recipe) throws
    func deleteRecipe(_ id: UUID) throws
    func searchRecipes(query: String) -> [Recipe]
}

// Implementation hides all Core Data details
class CoreDataRecipeRepository: RecipeRepository {
    let dataController: DataController
    
    func fetchRecipes(category: String? = nil) -> [Recipe] {
        let request = NSFetchRequest<RecipeEntity>(entityName: "Recipe")
        
        if let category {
            request.predicate = NSPredicate(format: "category.name == %@", category)
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RecipeEntity.name, ascending: true)]
        
        do {
            let entities = try dataController.viewContext.fetch(request)
            return entities.map { $0.toDomain() } // DTO conversion
        } catch {
            print("Fetch failed: \(error)")
            return []
        }
    }
    
    func saveRecipe(_ recipe: Recipe) throws {
        dataController.viewContext.perform {
            let entity = RecipeEntity(context: self.dataController.viewContext)
            entity.populate(from: recipe)
            try? self.dataController.viewContext.save()
        }
    }
}

// ViewModel depends on protocol ONLY
class RecipeListViewModel {
    let repository: RecipeRepository // ✅ No Core Data here
    @Published var recipes: [Recipe] = []
    
    func loadRecipes() {
        recipes = repository.fetchRecipes()
    }
}
```

**Key benefit:** Swap implementation (in-memory for tests, real CD for prod) without changing ViewModel.

---

## 4. NSFetchedResultsController + UITableView

```swift
class RecipeListViewController: UITableViewController, NSFetchedResultsControllerDelegate {
    var frc: NSFetchedResultsController<RecipeEntity>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupFRC()
    }
    
    func setupFRC() {
        let request = NSFetchRequest<RecipeEntity>(entityName: "Recipe")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \RecipeEntity.category?.name, ascending: true),
            NSSortDescriptor(keyPath: \RecipeEntity.name, ascending: true)
        ]
        
        frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: DataController.shared.viewContext,
            sectionNameKeyPath: "category.name", // ✅ Auto-grouping by category
            cacheName: "recipes-cache"
        )
        frc?.delegate = self
        
        do {
            try frc?.performFetch()
        } catch {
            print("FRC fetch failed: \(error)")
        }
    }
    
    // Delegate methods - Handle incremental updates
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any,
                    at indexPath: IndexPath?,
                    for type: NSFetchedResultsChangeType,
                    newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            tableView.insertRows(at: [newIndexPath!], with: .automatic)
        case .delete:
            tableView.deleteRows(at: [indexPath!], with: .automatic)
        case .update:
            tableView.reloadRows(at: [indexPath!], with: .automatic)
        case .move:
            tableView.moveRow(at: indexPath!, to: newIndexPath!)
        @unknown default:
            break
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
}
```

**⚠️ Cache invalidation:** Delete cache when schema changes or fetch predicate evolves.

---

## 5. Core Data Concurrency (Critical for Stability)

### Main Rule: Never fetch/modify on wrong thread → crash
```swift
// ❌ WRONG - Will crash if called from background
let recipes = try viewContext.fetch(request)

// ✅ RIGHT - Use perform/performAndWait
viewContext.perform {
    let recipes = try? self.viewContext.fetch(request)
    // Update UI
    DispatchQueue.main.async {
        self.updateUI()
    }
}

// ✅ For sync operations (rare)
viewContext.performAndWait {
    let recipes = try? self.viewContext.fetch(request)
    // Returns immediately
}
```

### Background Operations (Save heavy data)
```swift
let bgContext = DataController.shared.container.newBackgroundContext()
bgContext.perform {
    // Fetch/modify in background
    let request = NSFetchRequest<RecipeEntity>(entityName: "Recipe")
    request.returnsObjectsAsFaults = true // ✅ Lighter weight
    
    do {
        try bgContext.save() // ✅ Save to DB
    } catch {
        bgContext.rollback() // Undo on error
    }
}
```

**Pattern for ViewModel + Combine:**
```swift
func loadRecipesAsync() -> AnyPublisher<[Recipe], Never> {
    let bgContext = DataController.shared.container.newBackgroundContext()
    
    return Future { promise in
        bgContext.perform {
            let request = NSFetchRequest<RecipeEntity>(entityName: "Recipe")
            if let results = try? bgContext.fetch(request) {
                let recipes = results.map { $0.toDomain() }
                promise(.success(recipes))
            } else {
                promise(.success([]))
            }
        }
    }.eraseToAnyPublisher()
}
```

---

## 6. Common Beginner Mistakes (AVOID THESE)

| Mistake | Impact | Fix |
|---------|--------|-----|
| No inverse relationships | FRC silently breaks, data inconsistency | Always define both sides in model |
| Fetch on main thread (slow) | UI freezes | Use background context + async |
| Forgetting NSFetchedResultsController delegate methods | Memory leaks | Implement delegate fully or use property observer |
| Storing large blobs (images) | Database bloat, slow fetches | Store file paths, load images separately |
| No error handling | Silent failures | Check save/fetch returns, log errors |
| Keeping old FRC reference | Stale data updates | Release FRC when ViewController deinits |
| Not batching operations | 10K saves = 10K disk writes | Use batch insert/delete for bulk data |

---

## 7. Core Data + Combine (Light Integration)

```swift
// Simple approach: Fetch on demand + @Published
class RecipeStore: ObservableObject {
    @Published var recipes: [Recipe] = []
    let repository: RecipeRepository
    
    func refresh() {
        recipes = repository.fetchRecipes() // Synced, simple
    }
}

// Advanced: NSManagedObjectContext changes as publisher
extension NSManagedObjectContext {
    func recipes() -> AnyPublisher<[Recipe], Never> {
        NotificationCenter.default
            .publisher(for: NSManagedObjectContext.didSave)
            .map { _ in
                let request = NSFetchRequest<RecipeEntity>(entityName: "Recipe")
                return (try? self.fetch(request))?.map { $0.toDomain() } ?? []
            }
            .eraseToAnyPublisher()
    }
}
```

**Avoid:** Don't try to make NSManagedObject @Published directly (thread unsafe). Use DTOs.

---

## 8. Migration Strategy

### For v1 → v2 schema changes:
```swift
// In model editor:
1. Select model file → Editor → Add Model Version
2. Set as current version
3. Make changes in new version

// Lightweight migration (auto-applied if compatible):
let container = NSPersistentContainer(name: "Cookbook")
let description = NSPersistentStoreDescription()
description.shouldMigrateStoreAutomatically = true // ✅
description.shouldInferMappingModelAutomatically = true

container.persistentStoreDescriptions = [description]
container.loadPersistentStores { ... }
```

**When lightweight fails:** Create `Cookbook.xcmapping` manually or write custom migration script.

---

## 9. Testing (In-Memory Store)

```swift
func createTestDataController() -> DataController {
    let controller = DataController()
    
    // Replace persistent store with in-memory
    let description = NSPersistentStoreDescription()
    description.type = NSInMemoryStoreType
    
    controller.container.persistentStoreDescriptions = [description]
    try? controller.container.persistentStoreCoordinator?.addPersistentStore(
        ofType: NSInMemoryStoreType,
        configurationName: nil,
        at: nil,
        options: nil
    )
    
    return controller
}

// Unit Test Example
func testRecipeRepository() {
    let dc = createTestDataController()
    let repo = CoreDataRecipeRepository(dataController: dc)
    
    let recipe = Recipe(name: "Pasta", category: "Pasta")
    try? repo.saveRecipe(recipe)
    
    let fetched = repo.fetchRecipes()
    XCTAssertEqual(fetched.count, 1)
}
```

---

## Architectural Recommendations

### Tier 1 (Immediate): Start Here
1. ✅ NSPersistentContainer with singleton pattern
2. ✅ Define schema with inverse relationships
3. ✅ Repository layer (hides Core Data)
4. ✅ Use background context for saves

### Tier 2 (Phase 2): Enhance
1. NSFetchedResultsController for list UI
2. Batch operations for bulk imports
3. Lightweight migration setup

### Tier 3 (Future): Only If Needed
1. CloudKit sync (NSPersistentCloudKitContainer)
2. Custom migration logic
3. Persistent history tracking for sync

---

## Unresolved Questions
- What's the expected data volume? (determines batch vs. streaming strategy)
- Image storage: embed in DB or file system? (recommend file system for >500KB images)
- Will app go offline? (affects sync strategy)
- Need undo/redo? (requires NSUndoManager integration, not covered here)

---

**Next Step:** Create xcdatamodeld file with Recipe/Category/Ingredient/Tag/Step entities following schema in Section 2. Then implement DataController + RecipeRepository following Section 3.
