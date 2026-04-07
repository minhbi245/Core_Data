# Phase 1: Project Setup & Core Data Stack

## Tổng Quan
- **Priority:** P0 — Phải làm trước tiên
- **Status:** [ ] Not Started
- **Core Data concepts:** NSPersistentContainer, NSManagedObjectContext, .xcdatamodeld, Entities, Attributes, Relationships, Inverse Relationships, Delete Rules

---

## Giải Thích Core Data (Dành cho người mới)

### Core Data là gì?
Core Data là framework của Apple để **lưu trữ dữ liệu cấu trúc** trên thiết bị. Nó không phải là database trực tiếp — nó là một lớp trừu tượng quản lý objects và tự động ánh xạ chúng xuống SQLite (hoặc in-memory).

Hãy nghĩ như sau:
```
App Code ←→ Core Data (quản lý objects) ←→ SQLite file (lưu trên disk)
```

### NSPersistentContainer
Là "bộ não" khởi tạo toàn bộ Core Data stack. Bạn chỉ cần tạo nó một lần.

```swift
// NSPersistentContainer tự động:
// 1. Tìm file .xcdatamodeld trong bundle
// 2. Tạo SQLite file trong Documents directory
// 3. Khởi tạo NSManagedObjectContext để bạn làm việc
let container = NSPersistentContainer(name: "Cookbook") // "Cookbook" = tên file .xcdatamodeld
```

### NSManagedObjectContext (Context)
Giống như **bản nháp** — bạn thêm/sửa/xóa objects trên context, rồi gọi `save()` để ghi xuống database thật.

```
Context (bản nháp)  →  save()  →  SQLite (bản chính)
```

Có 2 loại context:
- `viewContext` — chạy trên main thread, dùng cho UI
- `newBackgroundContext()` — chạy trên background thread, dùng cho heavy operations

### .xcdatamodeld (Data Model)
File này định nghĩa **schema** — giống như bản vẽ cho database của bạn. Bạn tạo Entities (bảng), Attributes (cột), Relationships (quan hệ) bằng giao diện đồ họa trong Xcode.

### Entities, Attributes, Relationships
- **Entity** = một "bảng" (ví dụ: Recipe, Category)
- **Attribute** = một "cột" (ví dụ: name: String, cookTime: Int16)
- **Relationship** = liên kết giữa 2 entities (ví dụ: Recipe → Category)

### Inverse Relationships (Quan hệ ngược)
**BẮT BUỘC phải set cho mọi relationship!** Core Data cần biết cả 2 chiều để duy trì data integrity.

```
Recipe.category  ←→  Category.recipes
(Recipe biết Category của nó)  ←→  (Category biết tất cả Recipes của nó)
```

Nếu quên inverse → NSFetchedResultsController sẽ hoạt động sai, data inconsistency.

### Delete Rules
Khi xóa một object, xử lý objects liên quan thế nào:
- **Cascade** — xóa luôn (xóa Recipe → xóa tất cả Steps của nó)
- **Nullify** — set relationship về nil (xóa Category → Recipe.category = nil, recipe vẫn còn)
- **Deny** — không cho xóa nếu còn objects liên quan
- **No Action** — không làm gì (không khuyến nghị)

---

## Bước 1: Tạo Xcode Project (Làm thủ công)

1. Mở Xcode → **Create New Project**
2. Chọn **iOS → App**
3. Product Name: `CookbookApp`
4. Interface: **Storyboard** (ta sẽ tự xóa Storyboard)
5. Language: **Swift**
6. ⚠️ **KHÔNG check** "Use Core Data" — ta sẽ setup thủ công để hiểu rõ hơn
7. Save vào thư mục: `/Users/leonguyen/Developer/Archive/Repos/personal/Core_Data/`

### Xóa Storyboard (dùng code-based UI)
1. Xóa `Main.storyboard`
2. Xóa key `UIMainStoryboardFile` trong `Info.plist`
3. Trong `SceneDelegate.swift`, thêm:
```swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
           options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = (scene as? UIWindowScene) else { return }
    window = UIWindow(windowScene: windowScene)
    let navController = UINavigationController(rootViewController: RecipeListViewController())
    window?.rootViewController = navController
    window?.makeKeyAndVisible()
}
```

---

## Bước 2: Add SPM Dependencies

1. Xcode → **File → Add Package Dependencies**
2. Thêm SnapKit: `https://github.com/SnapKit/SnapKit.git` → Up to Next Major: `5.0.0`
3. Thêm Kingfisher: `https://github.com/onevcat/Kingfisher.git` → Up to Next Major: `7.0.0`

---

## Bước 3: Tạo Folder Structure

Tạo các Groups trong Xcode (chuột phải → New Group):
```
CookbookApp/
├── App/
├── Data/
│   ├── CoreData/
│   │   ├── Models/
│   │   └── Repositories/
│   └── (giữ trống, sẽ thêm sau)
├── Domain/
│   ├── Entities/
│   ├── Protocols/
│   └── UseCases/
├── Presentation/
│   ├── ViewModels/
│   └── Views/
│       ├── Screens/
│       └── Components/
└── Utilities/
    └── Extensions/
```

---

## Bước 4: Tạo Core Data Model (.xcdatamodeld)

1. **File → New → File → Core Data → Data Model**
2. Đặt tên: `Cookbook.xcdatamodeld`
3. Save vào group `Data/CoreData/Models/`

### Tạo 6 Entities trong Model Editor:

#### Entity: Recipe
| Attribute | Type | Optional | Default |
|-----------|------|----------|---------|
| id | UUID | No | — |
| name | String | No | — |
| recipeDescription | String | Yes | — |
| cookTime | Integer 16 | No | 0 |
| prepTime | Integer 16 | No | 0 |
| servings | Integer 16 | No | 1 |
| rating | Float | No | 0 |
| isFavorite | Boolean | No | false |
| createdAt | Date | No | — |
| imageData | Binary Data | Yes | — |

**Bật "Allows External Storage"** cho `imageData` (tự động lưu file system khi > 1MB)

#### Entity: Category
| Attribute | Type | Optional |
|-----------|------|----------|
| id | UUID | No |
| name | String | No |
| icon | String | No |

#### Entity: Ingredient
| Attribute | Type | Optional |
|-----------|------|----------|
| id | UUID | No |
| name | String | No |

#### Entity: RecipeIngredient (Junction table)
| Attribute | Type | Optional |
|-----------|------|----------|
| id | UUID | No |
| quantity | Double | No |
| unit | String | No |

#### Entity: Step
| Attribute | Type | Optional |
|-----------|------|----------|
| id | UUID | No |
| orderIndex | Integer 16 | No |
| instruction | String | No |
| imageData | Binary Data | Yes |

#### Entity: Tag
| Attribute | Type | Optional |
|-----------|------|----------|
| id | UUID | No |
| name | String | No |
| colorHex | String | No |

### Tạo Relationships:

| From | Relationship | To | Type | Inverse | Delete Rule |
|------|-------------|-----|------|---------|-------------|
| Recipe | category | Category | To One | recipes | Nullify |
| Category | recipes | Recipe | To Many | category | Nullify |
| Recipe | steps | Step | To Many (Ordered) | recipe | Cascade |
| Step | recipe | Recipe | To One | steps | Nullify |
| Recipe | recipeIngredients | RecipeIngredient | To Many | recipe | Cascade |
| RecipeIngredient | recipe | Recipe | To One | recipeIngredients | Nullify |
| RecipeIngredient | ingredient | Ingredient | To One | recipeIngredients | Nullify |
| Ingredient | recipeIngredients | RecipeIngredient | To Many | ingredient | Cascade |
| Recipe | tags | Tag | To Many | recipes | Nullify |
| Tag | recipes | Recipe | To Many | tags | Nullify |

⚠️ **Với Recipe → steps**: Check "Ordered" trong Relationship inspector để dùng NSOrderedSet

### Generate NSManagedObject Subclasses:
1. Select tất cả entities → **Editor → Create NSManagedObject Subclass**
2. Chọn target `CookbookApp`
3. Save vào `Data/CoreData/Models/`

> Xcode tạo 2 file cho mỗi entity: `Recipe+CoreDataClass.swift` và `Recipe+CoreDataProperties.swift`

---

## Bước 5: Tạo DataController

Tạo file `Data/CoreData/DataController.swift`:

```swift
import CoreData

/// Singleton quản lý toàn bộ Core Data stack
/// - Khởi tạo NSPersistentContainer
/// - Cung cấp viewContext (main thread) và background context
final class DataController {
    static let shared = DataController()

    let container: NSPersistentContainer

    /// Context chạy trên main thread — dùng cho UI reads
    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    private init() {
        container = NSPersistentContainer(name: "Cookbook")

        // Tự động merge changes từ background context về viewContext
        container.viewContext.automaticallyMergesChangesFromParent = true

        // Policy khi có conflict: object trong memory thắng
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        container.loadPersistentStores { _, error in
            if let error {
                // Chỉ fatalError trong development — production cần handle gracefully
                fatalError("❌ Core Data load failed: \(error)")
            }
        }
    }

    /// Tạo background context mới để thực hiện heavy operations
    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }

    /// Save viewContext nếu có thay đổi
    func saveContext() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            print("❌ Save failed: \(error)")
        }
    }
}
```

---

## Todo List
- [ ] Tạo Xcode project thủ công trong Xcode
- [ ] Xóa Storyboard, setup code-based root ViewController
- [ ] Add SPM: SnapKit + Kingfisher
- [ ] Tạo folder structure (Groups trong Xcode)
- [ ] Tạo `Cookbook.xcdatamodeld` với 6 entities
- [ ] Tạo tất cả attributes và relationships theo bảng trên
- [ ] Generate NSManagedObject subclasses
- [ ] Tạo `DataController.swift`
- [ ] Build project — không có errors là thành công

## Success Criteria
- Project build thành công (⌘B)
- DataController.shared khởi tạo không crash
- Xcode Data Model editor hiển thị đủ 6 entities và tất cả relationships có inverse

## Tiếp Theo
→ [Phase 2: Domain Layer & Repository Pattern](phase-02-domain-layer-repository-pattern.md)
