# Phase 8: Data Migration

## Tổng Quan
- **Priority:** P2
- **Status:** [ ] Not Started
- **Core Data concepts:** Model versioning, lightweight migration, mapping model, migration policies

---

## Giải Thích Core Data

### Tại sao cần Migration?
Khi app đã được release và có users với data thật, bạn không thể đơn giản xóa `.xcdatamodeld` và làm lại. Nếu schema thay đổi mà không migrate:

```
❌ App crash ngay khi launch với error:
"The model used to open the store is incompatible with the one used to create the store"
```

Migration = quá trình chuyển đổi data từ schema cũ sang schema mới an toàn.

### Lightweight Migration
Với những thay đổi đơn giản, Core Data tự làm được (không cần code):

| Thay đổi | Lightweight? |
|----------|-------------|
| Thêm attribute mới (optional) | ✅ |
| Xóa attribute | ✅ |
| Đổi tên attribute (cần dùng Renaming ID) | ✅ |
| Thêm entity mới | ✅ |
| Thêm relationship mới | ✅ |
| Thay đổi attribute type (String → Int) | ❌ Cần custom migration |
| Chia entity thành 2 | ❌ Cần custom migration |

### Cách Tạo Model Version

1. Trong Xcode, select `Cookbook.xcdatamodeld`
2. **Editor → Add Model Version** → đặt tên `Cookbook 2`
3. Xcode tạo `Cookbook 2.xcdatamodel` bên trong package
4. Thực hiện thay đổi TRONG version mới (không sửa version cũ!)
5. Select `Cookbook.xcdatamodeld` → Inspector → **Current Model Version** → chọn `Cookbook 2`

### Enable Lightweight Migration

```swift
// DataController.swift — cập nhật init()
container.loadPersistentStores { _, error in
    // Core Data tự detect cần migrate không
    // nếu có → tự làm lightweight migration
}
```

**Trong iOS 10+**, `NSPersistentContainer` tự động bật lightweight migration. Không cần config thêm! Chỉ cần:
1. Đặt Current Model Version đúng
2. Thay đổi phải compatible với lightweight migration

Nếu muốn explicit (để chắc chắn):
```swift
let description = NSPersistentStoreDescription()
description.shouldMigrateStoreAutomatically = true
description.shouldInferMappingModelAutomatically = true
container.persistentStoreDescriptions = [description]
container.loadPersistentStores { ... }
```

### Renaming ID — Đổi tên attribute/entity
Nếu muốn đổi tên `rating` → `starRating` mà không mất data:

1. Trong model version mới: đổi tên attribute thành `starRating`
2. Trong Inspector của `starRating` → **Renaming ID** = `rating` (tên cũ)
3. Core Data sẽ copy data từ `rating` cũ sang `starRating` mới

---

## Thực Hành: Thêm "difficulty" vào Recipe

### Bước 1: Tạo Model Version Mới

1. Select `Cookbook.xcdatamodeld` trong Xcode
2. **Editor → Add Model Version**
3. Đặt tên: `Cookbook 2`
4. Nhấn Finish

### Bước 2: Thay đổi trong Version Mới

Trong `Cookbook 2.xcdatamodel`, thêm vào entity **Recipe**:

| Attribute | Type | Optional | Default |
|-----------|------|----------|---------|
| difficulty | String | **Yes** | — |
| notes | String | **Yes** | — |

> ⚠️ Attribute mới PHẢI là Optional (hoặc có default value) để lightweight migration hoạt động.
> Nếu required mà không có default → migration fail!

### Bước 3: Set Current Version

1. Select `Cookbook.xcdatamodeld` (package)
2. File Inspector (⌘⌥1) → **Model Version** → chọn `Cookbook 2`
3. Xcode hiển thị dấu ✓ trên `Cookbook 2.xcdatamodel`

### Bước 4: Cập nhật Code

**`Data/CoreData/Models/RecipeEntity+CoreDataProperties.swift`** — Regenerate hoặc thêm thủ công:
```swift
// Thêm 2 properties mới (Xcode generate lại nếu dùng codegen)
@NSManaged public var difficulty: String?
@NSManaged public var notes: String?
```

**`Domain/Entities/Recipe.swift`** — Thêm vào struct:
```swift
struct Recipe {
    // ... existing properties ...
    var difficulty: RecipeDifficulty?
    var notes: String?
}

enum RecipeDifficulty: String, CaseIterable {
    case easy = "Dễ"
    case medium = "Trung bình"
    case hard = "Khó"
}
```

**`Data/CoreData/Models/RecipeEntity+Mapping.swift`** — Cập nhật mapping:
```swift
extension RecipeEntity {
    func toDomain() -> Recipe {
        Recipe(
            // ... existing ...
            difficulty: difficulty.flatMap { RecipeDifficulty(rawValue: $0) },
            notes: notes
        )
    }

    func populate(from recipe: Recipe, in context: NSManagedObjectContext) {
        // ... existing ...
        self.difficulty = recipe.difficulty?.rawValue
        self.notes = recipe.notes
    }
}
```

### Bước 5: Test Migration

```swift
// Trong DataController, thêm debug log
container.loadPersistentStores { storeDescription, error in
    if let error {
        fatalError("❌ Core Data load failed: \(error)")
    }
    print("✅ Store loaded: \(storeDescription.url?.lastPathComponent ?? "")")
    // Nếu migration xảy ra, Core Data log sẽ có "migration" entries
}
```

**Test flow:**
1. Run app ở version 1 → tạo vài recipes
2. Stop app
3. Switch sang version 2 (thêm difficulty)
4. Run app lại → data cũ vẫn còn, không crash

---

## Thực Hành: Custom Migration (Nâng Cao)

Khi lightweight migration không đủ (ví dụ: split `name` thành `firstName` + `lastName`):

```swift
// NSEntityMigrationPolicy subclass
class RecipeMigrationPolicy: NSEntityMigrationPolicy {
    override func createDestinationInstances(
        forSource sInstance: NSManagedObject,
        in mapping: NSEntityMapping,
        manager: NSMigrationManager
    ) throws {
        try super.createDestinationInstances(forSource: sInstance, in: mapping, manager: manager)

        // Lấy destination entity vừa tạo
        guard let dInstance = manager.destinationInstances(
            forEntityMappingName: mapping.name, sourceInstances: [sInstance]
        ).first else { return }

        // Custom transform
        let oldName = sInstance.value(forKey: "name") as? String ?? ""
        dInstance.setValue(oldName.uppercased(), forKey: "name")  // Example: uppercase names
    }
}
```

> Custom migration yêu cầu tạo `.xcmappingmodel` — advanced topic, không cần thiết cho beginner.

---

## Todo List
- [ ] Tạo `Cookbook 2.xcdatamodel` version
- [ ] Thêm `difficulty` (String, optional) và `notes` (String, optional) vào Recipe entity
- [ ] Set `Cookbook 2` làm current version
- [ ] Regenerate NSManagedObject subclasses
- [ ] Cập nhật `Recipe` domain struct với `difficulty` + `RecipeDifficulty` enum
- [ ] Cập nhật `RecipeEntity+Mapping.swift`
- [ ] Cập nhật Create/Edit form để chọn difficulty
- [ ] Test: install version 1 → tạo data → update lên version 2 → verify data còn nguyên

## Success Criteria
- App không crash khi chạy với store từ model version cũ hơn
- Data cũ được giữ nguyên sau migration
- `difficulty` = nil cho recipes cũ (expected)
- Tạo recipe mới có thể set difficulty

## Tiếp Theo
→ [Phase 9: Testing Core Data](phase-09-testing-core-data.md)
