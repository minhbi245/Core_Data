# Phase 2: Domain Layer & Repository Pattern

## Tổng Quan
- **Priority:** P0
- **Status:** [ ] Not Started
- **Core Data concepts:** NSFetchRequest, NSPredicate, NSSortDescriptor, context.save(), NSManagedObject mapping

---

## Giải Thích Core Data

### Tại sao cần Domain Layer?
Vấn đề nếu dùng NSManagedObject trực tiếp trong ViewModel:
```
❌ NSManagedObject chỉ an toàn trên thread đã tạo ra nó
❌ ViewModel bị phụ thuộc vào Core Data — khó test, khó swap database
❌ Nếu đổi sang Realm hoặc SwiftData → phải viết lại toàn bộ ViewModel
```

Giải pháp: **DTO Pattern (Data Transfer Object)**
```
NSManagedObject (Core Data) ←→ Repository ←→ Swift Struct (Domain) ←→ ViewModel
```

Domain entities là **plain Swift structs** — không biết Core Data tồn tại.

### NSFetchRequest
Câu "query" để lấy dữ liệu từ Core Data. Tương đương với `SELECT * FROM Recipe` trong SQL.

```swift
// Lấy tất cả recipes
let request = NSFetchRequest<RecipeEntity>(entityName: "Recipe")

// Hoặc dùng type-safe method (Xcode tự generate):
let request = RecipeEntity.fetchRequest()
```

### NSPredicate
Điều kiện lọc — tương đương `WHERE` trong SQL.

```swift
// WHERE isFavorite = true
request.predicate = NSPredicate(format: "isFavorite == true")

// WHERE category.name = "Pasta"
request.predicate = NSPredicate(format: "category.name == %@", "Pasta")

// WHERE name CONTAINS "chicken" (case insensitive)
request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", "chicken")

// Kết hợp: WHERE isFavorite = true AND cookTime <= 30
request.predicate = NSPredicate(format: "isFavorite == true AND cookTime <= %d", 30)
```

**Cú pháp format string:**
- `%@` — String, Date, UUID
- `%d` — Int
- `%f` — Float/Double
- `[cd]` — case insensitive + diacritic insensitive

### NSSortDescriptor
Sắp xếp kết quả — tương đương `ORDER BY` trong SQL.

```swift
// Sắp xếp theo name A-Z
request.sortDescriptors = [NSSortDescriptor(keyPath: \RecipeEntity.name, ascending: true)]

// Sắp xếp theo category trước, rồi theo name
request.sortDescriptors = [
    NSSortDescriptor(keyPath: \RecipeEntity.category?.name, ascending: true),
    NSSortDescriptor(keyPath: \RecipeEntity.name, ascending: true)
]
```

### context.save()
Ghi tất cả thay đổi từ context xuống SQLite. **Bắt buộc gọi sau khi insert/update/delete.**

```swift
// Kiểm tra có thay đổi không trước khi save (tối ưu)
if context.hasChanges {
    try context.save()
}
```

---

## Files Cần Tạo

### 1. Domain Entities (Swift Structs)

**`Domain/Entities/Recipe.swift`**
```swift
import Foundation

struct Recipe: Identifiable, Equatable {
    let id: UUID
    var name: String
    var recipeDescription: String
    var cookTime: Int        // minutes
    var prepTime: Int
    var servings: Int
    var rating: Float
    var isFavorite: Bool
    var createdAt: Date
    var imageData: Data?
    var category: RecipeCategory?
    var tags: [RecipeTag]
    var ingredients: [RecipeIngredientItem]
    var steps: [RecipeStep]

    init(
        id: UUID = UUID(),
        name: String,
        recipeDescription: String = "",
        cookTime: Int = 0,
        prepTime: Int = 0,
        servings: Int = 2,
        rating: Float = 0,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        imageData: Data? = nil,
        category: RecipeCategory? = nil,
        tags: [RecipeTag] = [],
        ingredients: [RecipeIngredientItem] = [],
        steps: [RecipeStep] = []
    ) {
        self.id = id
        self.name = name
        self.recipeDescription = recipeDescription
        self.cookTime = cookTime
        self.prepTime = prepTime
        self.servings = servings
        self.rating = rating
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.imageData = imageData
        self.category = category
        self.tags = tags
        self.ingredients = ingredients
        self.steps = steps
    }
}
```

**`Domain/Entities/RecipeCategory.swift`**
```swift
struct RecipeCategory: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var icon: String    // SF Symbol name
}
```

**`Domain/Entities/RecipeTag.swift`**
```swift
struct RecipeTag: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
}
```

**`Domain/Entities/RecipeIngredientItem.swift`**
```swift
struct RecipeIngredientItem: Identifiable, Equatable {
    let id: UUID
    var ingredient: RecipeIngredient
    var quantity: Double
    var unit: String
}

struct RecipeIngredient: Identifiable, Equatable {
    let id: UUID
    var name: String
}
```

**`Domain/Entities/RecipeStep.swift`**
```swift
struct RecipeStep: Identifiable, Equatable {
    let id: UUID
    var orderIndex: Int
    var instruction: String
    var imageData: Data?
}
```

---

### 2. Repository Protocols

**`Domain/Protocols/RecipeRepositoryProtocol.swift`**
```swift
import Foundation

protocol RecipeRepositoryProtocol {
    func fetchAll() -> [Recipe]
    func fetchFavorites() -> [Recipe]
    func fetch(by id: UUID) -> Recipe?
    func search(query: String) -> [Recipe]
    func fetchBy(category: RecipeCategory) -> [Recipe]
    func save(_ recipe: Recipe) throws
    func delete(_ recipe: Recipe) throws
    func toggleFavorite(_ recipe: Recipe) throws
}
```

**`Domain/Protocols/CategoryRepositoryProtocol.swift`**
```swift
protocol CategoryRepositoryProtocol {
    func fetchAll() -> [RecipeCategory]
    func save(_ category: RecipeCategory) throws
    func delete(_ category: RecipeCategory) throws
}
```

---

### 3. Core Data Repositories

**`Data/CoreData/Repositories/RecipeCoreDataRepository.swift`**
```swift
import CoreData

final class RecipeCoreDataRepository: RecipeRepositoryProtocol {
    private let dataController: DataController

    init(dataController: DataController = .shared) {
        self.dataController = dataController
    }

    func fetchAll() -> [Recipe] {
        let request = RecipeEntity.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \RecipeEntity.createdAt, ascending: false)
        ]
        return (try? dataController.viewContext.fetch(request))?.map { $0.toDomain() } ?? []
    }

    func fetchFavorites() -> [Recipe] {
        let request = RecipeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "isFavorite == true")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RecipeEntity.name, ascending: true)]
        return (try? dataController.viewContext.fetch(request))?.map { $0.toDomain() } ?? []
    }

    func fetch(by id: UUID) -> Recipe? {
        let request = RecipeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? dataController.viewContext.fetch(request))?.first?.toDomain()
    }

    func search(query: String) -> [Recipe] {
        let request = RecipeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", query)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RecipeEntity.name, ascending: true)]
        return (try? dataController.viewContext.fetch(request))?.map { $0.toDomain() } ?? []
    }

    func fetchBy(category: RecipeCategory) -> [Recipe] {
        let request = RecipeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "category.id == %@", category.id as CVarArg)
        return (try? dataController.viewContext.fetch(request))?.map { $0.toDomain() } ?? []
    }

    func save(_ recipe: Recipe) throws {
        let context = dataController.viewContext
        // Tìm existing entity hoặc tạo mới
        let entity = findEntity(id: recipe.id, in: context) ?? RecipeEntity(context: context)
        entity.populate(from: recipe, in: context)
        try context.save()
    }

    func delete(_ recipe: Recipe) throws {
        guard let entity = findEntity(id: recipe.id, in: dataController.viewContext) else { return }
        dataController.viewContext.delete(entity)
        try dataController.viewContext.save()
    }

    func toggleFavorite(_ recipe: Recipe) throws {
        guard let entity = findEntity(id: recipe.id, in: dataController.viewContext) else { return }
        entity.isFavorite.toggle()
        try dataController.viewContext.save()
    }

    private func findEntity(id: UUID, in context: NSManagedObjectContext) -> RecipeEntity? {
        let request = RecipeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
```

---

### 4. NSManagedObject Mapping Extensions

**`Data/CoreData/Models/RecipeEntity+Mapping.swift`**
```swift
import CoreData

extension RecipeEntity {
    /// NSManagedObject → Domain Swift struct
    func toDomain() -> Recipe {
        Recipe(
            id: id ?? UUID(),
            name: name ?? "",
            recipeDescription: recipeDescription ?? "",
            cookTime: Int(cookTime),
            prepTime: Int(prepTime),
            servings: Int(servings),
            rating: rating,
            isFavorite: isFavorite,
            createdAt: createdAt ?? Date(),
            imageData: imageData,
            category: (category as? CategoryEntity)?.toDomain(),
            tags: (tags?.allObjects as? [TagEntity])?.map { $0.toDomain() } ?? [],
            ingredients: (recipeIngredients?.allObjects as? [RecipeIngredientEntity])?
                .map { $0.toDomain() } ?? [],
            steps: (steps?.array as? [StepEntity])?.map { $0.toDomain() }
                .sorted { $0.orderIndex < $1.orderIndex } ?? []
        )
    }

    /// Domain → NSManagedObject (populate existing entity)
    func populate(from recipe: Recipe, in context: NSManagedObjectContext) {
        self.id = recipe.id
        self.name = recipe.name
        self.recipeDescription = recipe.recipeDescription
        self.cookTime = Int16(recipe.cookTime)
        self.prepTime = Int16(recipe.prepTime)
        self.servings = Int16(recipe.servings)
        self.rating = recipe.rating
        self.isFavorite = recipe.isFavorite
        self.createdAt = recipe.createdAt
        self.imageData = recipe.imageData
        // Relationships sẽ handle ở Phase 4
    }
}

extension CategoryEntity {
    func toDomain() -> RecipeCategory {
        RecipeCategory(id: id ?? UUID(), name: name ?? "", icon: icon ?? "folder")
    }
}

extension TagEntity {
    func toDomain() -> RecipeTag {
        RecipeTag(id: id ?? UUID(), name: name ?? "", colorHex: colorHex ?? "#E8730E")
    }
}

extension StepEntity {
    func toDomain() -> RecipeStep {
        RecipeStep(id: id ?? UUID(), orderIndex: Int(orderIndex),
                   instruction: instruction ?? "", imageData: imageData)
    }
}
```

---

## Todo List
- [ ] Tạo `Domain/Entities/` files (Recipe, RecipeCategory, RecipeTag, RecipeStep, RecipeIngredientItem)
- [ ] Tạo `Domain/Protocols/` (RecipeRepositoryProtocol, CategoryRepositoryProtocol)
- [ ] Tạo `Data/CoreData/Repositories/RecipeCoreDataRepository.swift`
- [ ] Tạo `Data/CoreData/Models/RecipeEntity+Mapping.swift`
- [ ] Tạo `CategoryCoreDataRepository.swift` (tương tự Recipe)
- [ ] Build project — không có compile errors

## Success Criteria
- Tất cả domain entities compile
- `RecipeCoreDataRepository().fetchAll()` trả về `[Recipe]` (empty array nếu DB trống)
- Gọi `save()` + `fetchAll()` lấy lại đúng data

## Tiếp Theo
→ [Phase 3: Recipe List & NSFetchedResultsController](phase-03-recipe-list-fetched-results-controller.md)
