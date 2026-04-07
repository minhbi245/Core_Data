# Phase 7: Background Context & Batch Operations

## Tổng Quan
- **Priority:** P2
- **Status:** [ ] Not Started
- **Core Data concepts:** newBackgroundContext(), perform{}/performAndWait{}, automaticallyMergesChangesFromParent, NSBatchInsertRequest, NSBatchDeleteRequest

---

## Giải Thích Core Data

### Vấn đề với Main Thread
`viewContext` chạy trên main thread — cùng thread với UI. Nếu làm heavy operations trên đó:

```swift
// ❌ NGUY HIỂM: parse + insert 500 recipes trên main thread
let recipes = parseJSON(data)   // Chậm
recipes.forEach { insertIntoContext($0) }  // Rất chậm
try viewContext.save()  // → UI bị đơ/freeze trong lúc này
```

### Background Context
```swift
// ✅ Đúng: heavy work trên background thread
let bgContext = DataController.shared.container.newBackgroundContext()

bgContext.perform {
    // Toàn bộ code trong block này chạy trên background thread
    let recipes = parseJSON(data)
    recipes.forEach { insertIntoContext(bgContext) }
    try? bgContext.save()
    // → viewContext tự động merge changes (nhờ automaticallyMergesChangesFromParent = true)
    // → FRC phát hiện thay đổi → cập nhật UI trên main thread
}
```

### perform{} vs performAndWait{}
```swift
// perform{} — async, không block thread gọi
bgContext.perform {
    // Chạy async — code bên ngoài tiếp tục ngay
    doHeavyWork()
}

// performAndWait{} — sync, block thread gọi cho đến khi xong
bgContext.performAndWait {
    // Code bên ngoài chờ cho đến khi block này hoàn thành
    doHeavyWork()
}
// Chỉ dùng performAndWait khi thực sự cần kết quả ngay
```

### automaticallyMergesChangesFromParent
Đây là lý do ta set trong `DataController.init()`:
```swift
container.viewContext.automaticallyMergesChangesFromParent = true
```
Khi bgContext save → changes tự merge vào viewContext → FRC tự cập nhật UI.
Không có dòng này, save từ background sẽ không được reflect lên UI.

### NSBatchInsertRequest — Insert hàng loạt
Thay vì tạo 500 NSManagedObject riêng lẻ, dùng batch:

```swift
// ❌ Chậm: 500 object insertions riêng lẻ
recipes.forEach { recipe in
    let entity = RecipeEntity(context: context)
    entity.populate(from: recipe)
}
try context.save()  // 500 write operations

// ✅ Nhanh hơn nhiều: 1 batch operation
let batchInsert = NSBatchInsertRequest(
    entity: RecipeEntity.entity(),
    objects: recipes.map { $0.toDictionary() }  // [[String: Any]]
)
batchInsert.resultType = .statusOnly
try context.execute(batchInsert)
// NSBatchInsertRequest bypass NSManagedObjectContext → trực tiếp SQLite
// → Nhanh hơn ~10-50x cho large datasets
```

⚠️ Nhược điểm của Batch: **không trigger NSFetchedResultsController delegate**.
Phải merge manually sau khi batch:
```swift
NotificationCenter.default.post(
    name: .NSManagedObjectContextDidSave,
    object: context
)
// Hoặc dùng NSPersistentHistoryTracking (advanced)
```

### NSBatchDeleteRequest — Xóa hàng loạt
```swift
// Xóa tất cả recipes trong 1 category
let fetchRequest: NSFetchRequest<NSFetchRequestResult> = RecipeEntity.fetchRequest()
fetchRequest.predicate = NSPredicate(format: "category.id == %@", categoryId as CVarArg)

let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
batchDelete.resultType = .resultTypeObjectIDs  // Lấy về IDs đã xóa

let result = try context.execute(batchDelete) as? NSBatchDeleteResult
let deletedIDs = result?.result as? [NSManagedObjectID] ?? []

// Merge deletions vào viewContext
NSManagedObjectContext.mergeChanges(
    fromRemoteContextSave: [NSDeletedObjectsKey: deletedIDs],
    into: [DataController.shared.viewContext]
)
```

---

## Files Cần Tạo

### 1. Sample Data JSON

**`Data/SeedData/sample-recipes.json`**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "Phở Bò",
    "cookTime": 180,
    "prepTime": 30,
    "servings": 4,
    "category": "Soup",
    "steps": [
      "Nướng xương và hành tây",
      "Hầm xương 3-4 tiếng",
      "Nêm gia vị: muối, nước mắm, đường phèn"
    ]
  },
  {
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "name": "Bún Bò Huế",
    "cookTime": 120,
    "prepTime": 45,
    "servings": 6,
    "category": "Soup"
  }
]
```

### 2. Background Import Service

**`Data/CoreData/Repositories/RecipeSeedDataImporter.swift`**
```swift
import CoreData

/// Service import sample recipes từ JSON trong background
final class RecipeSeedDataImporter {
    private let dataController: DataController

    init(dataController: DataController = .shared) {
        self.dataController = dataController
    }

    /// Import recipes từ JSON file — chạy trên background context
    func importSampleRecipes(completion: @escaping (Result<Int, Error>) -> Void) {
        guard let url = Bundle.main.url(forResource: "sample-recipes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            completion(.failure(ImportError.fileNotFound))
            return
        }

        // Tạo background context
        let bgContext = dataController.container.newBackgroundContext()
        bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // perform{} — không block main thread
        bgContext.perform {
            do {
                let rawRecipes = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
                var inserted = 0

                for rawRecipe in rawRecipes {
                    guard let name = rawRecipe["name"] as? String,
                          let idString = rawRecipe["id"] as? String,
                          let id = UUID(uuidString: idString) else { continue }

                    // Kiểm tra đã tồn tại chưa (tránh duplicate)
                    let checkRequest = RecipeEntity.fetchRequest()
                    checkRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                    checkRequest.fetchLimit = 1
                    guard (try? bgContext.count(for: checkRequest)) == 0 else { continue }

                    // Insert mới
                    let entity = RecipeEntity(context: bgContext)
                    entity.id = id
                    entity.name = name
                    entity.cookTime = Int16((rawRecipe["cookTime"] as? Int) ?? 0)
                    entity.prepTime = Int16((rawRecipe["prepTime"] as? Int) ?? 0)
                    entity.servings = Int16((rawRecipe["servings"] as? Int) ?? 2)
                    entity.createdAt = Date()
                    entity.isFavorite = false

                    // Category
                    if let catName = rawRecipe["category"] as? String {
                        entity.category = self.findOrCreateCategory(name: catName, in: bgContext)
                    }

                    inserted += 1
                }

                // Save trên background
                try bgContext.save()
                // → automaticallyMergesChangesFromParent tự merge về viewContext
                // → FRC cập nhật UI trên main thread

                DispatchQueue.main.async {
                    completion(.success(inserted))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Batch delete: xóa tất cả recipes trong category
    func deleteAllRecipes(inCategory categoryId: UUID,
                          completion: @escaping (Result<Int, Error>) -> Void) {
        let context = dataController.viewContext
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = RecipeEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "category.id == %@", categoryId as CVarArg)

        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        batchDelete.resultType = .resultTypeObjectIDs

        do {
            let result = try context.execute(batchDelete) as? NSBatchDeleteResult
            let deletedIDs = result?.result as? [NSManagedObjectID] ?? []

            // Batch operations bypass the context → phải merge manually
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: deletedIDs],
                into: [context]
            )
            completion(.success(deletedIDs.count))
        } catch {
            completion(.failure(error))
        }
    }

    private func findOrCreateCategory(name: String, in context: NSManagedObjectContext) -> CategoryEntity {
        let request = CategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", name)
        request.fetchLimit = 1
        if let existing = (try? context.fetch(request))?.first { return existing }

        let newCat = CategoryEntity(context: context)
        newCat.id = UUID()
        newCat.name = name
        newCat.icon = "folder"
        return newCat
    }

    enum ImportError: Error {
        case fileNotFound
    }
}
```

### 3. Demo Usage trong ViewController

```swift
// Trong RecipeListViewController — thêm debug button để test
@objc private func importSampleData() {
    let importer = RecipeSeedDataImporter()
    importer.importSampleRecipes { result in
        // Đây đã là main thread (importer dispatch về main)
        switch result {
        case .success(let count):
            print("✅ Imported \(count) recipes")
            // FRC tự cập nhật tableView — không cần reload!
        case .failure(let error):
            print("❌ Import failed: \(error)")
        }
    }
}
```

---

## Todo List
- [ ] Tạo `sample-recipes.json` với 5-10 recipes mẫu
- [ ] Tạo `RecipeSeedDataImporter.swift`
- [ ] Thêm "Import Sample Data" button trong Settings hoặc debug menu
- [ ] Test: import 100 recipes → UI không bị freeze
- [ ] Test: batch delete category → FRC cập nhật đúng
- [ ] So sánh: import 100 recipes với loop thường vs background context (đo thời gian)

## Success Criteria
- Import JSON trên background → UI vẫn mượt, không freeze
- Sau import, FRC tự cập nhật RecipeList (nhờ automaticallyMergesChangesFromParent)
- Batch delete hoạt động và merges về viewContext đúng cách
- Debug: print thời gian import để thấy sự khác biệt background vs main thread

## Tiếp Theo
→ [Phase 8: Data Migration](phase-08-data-migration.md)
