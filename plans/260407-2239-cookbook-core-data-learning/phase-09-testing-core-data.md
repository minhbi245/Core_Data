# Phase 9: Testing Core Data

## Tổng Quan
- **Priority:** P2
- **Status:** [ ] Not Started
- **Core Data concepts:** NSInMemoryStoreType, test isolation, mock repositories, protocol-based testing

---

## Giải Thích Core Data

### Tại sao phải dùng In-Memory Store khi test?
Nếu test dùng store thật (SQLite file):
```
❌ Tests chạy chậm (I/O operations)
❌ Tests ảnh hưởng nhau (data từ test trước còn trong DB)
❌ Tests không độc lập → flaky tests
❌ CI/CD phức tạp
```

Với `NSInMemoryStoreType`:
```
✅ Data chỉ tồn tại trong RAM — xóa sạch sau mỗi test
✅ Cực nhanh (không có I/O)
✅ Mỗi test có fresh database riêng
✅ Hoạt động trên simulator + CI
```

### Cách tạo In-Memory DataController
```swift
// Tạo DataController với in-memory store thay vì SQLite
func makeInMemoryDataController() -> DataController {
    let controller = DataController(inMemory: true)
    return controller
}
```

Cần sửa `DataController` để support cả 2 modes:
```swift
init(inMemory: Bool = false) {
    container = NSPersistentContainer(name: "Cookbook")
    if inMemory {
        // Lưu vào /dev/null = không lưu xuống disk
        container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
    }
    container.loadPersistentStores { ... }
}
```

### Protocol-Based Testing — Không cần Core Data
Vì ViewModel chỉ phụ thuộc vào protocol (không phụ thuộc vào `CoreDataRecipeRepository` cụ thể), ta có thể tạo mock implementation:

```swift
// Mock hoàn toàn không dùng Core Data
class MockRecipeRepository: RecipeRepositoryProtocol {
    var recipes: [Recipe] = []
    var saveError: Error?

    func fetchAll() -> [Recipe] { recipes }
    func save(_ recipe: Recipe) throws {
        if let error = saveError { throw error }
        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[idx] = recipe
        } else {
            recipes.append(recipe)
        }
    }
    func delete(_ recipe: Recipe) throws {
        recipes.removeAll { $0.id == recipe.id }
    }
    // ... implement other protocol methods
}
```

---

## Files Cần Tạo

### 1. Cập nhật DataController để support In-Memory

**`Data/CoreData/DataController.swift`** — Thêm `inMemory` parameter:
```swift
final class DataController {
    static let shared = DataController()

    let container: NSPersistentContainer
    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Cookbook")

        if inMemory {
            // /dev/null = không ghi xuống disk
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        container.loadPersistentStores { _, error in
            if let error { fatalError("❌ Core Data load failed: \(error)") }
        }
    }

    func saveContext() {
        guard viewContext.hasChanges else { return }
        try? viewContext.save()
    }
}
```

### 2. Mock Repository

**`CookbookAppTests/Mocks/MockRecipeRepository.swift`**
```swift
@testable import CookbookApp
import Foundation

final class MockRecipeRepository: RecipeRepositoryProtocol {
    // State tracking
    var recipes: [Recipe] = []
    var saveCallCount = 0
    var deleteCallCount = 0
    var saveError: Error?

    func fetchAll() -> [Recipe] { recipes }

    func fetchFavorites() -> [Recipe] { recipes.filter { $0.isFavorite } }

    func fetch(by id: UUID) -> Recipe? { recipes.first { $0.id == id } }

    func search(query: String) -> [Recipe] {
        recipes.filter { $0.name.lowercased().contains(query.lowercased()) }
    }

    func fetchBy(category: RecipeCategory) -> [Recipe] {
        recipes.filter { $0.category?.id == category.id }
    }

    func save(_ recipe: Recipe) throws {
        saveCallCount += 1
        if let error = saveError { throw error }
        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[idx] = recipe
        } else {
            recipes.append(recipe)
        }
    }

    func delete(_ recipe: Recipe) throws {
        deleteCallCount += 1
        recipes.removeAll { $0.id == recipe.id }
    }

    func toggleFavorite(_ recipe: Recipe) throws {
        guard let idx = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[idx].isFavorite.toggle()
    }
}
```

### 3. Repository Tests (Core Data integration)

**`CookbookAppTests/Repositories/RecipeCoreDataRepositoryTests.swift`**
```swift
import XCTest
import CoreData
@testable import CookbookApp

final class RecipeCoreDataRepositoryTests: XCTestCase {
    var sut: RecipeCoreDataRepository!
    var dataController: DataController!

    override func setUp() {
        super.setUp()
        // Mỗi test dùng fresh in-memory database
        dataController = DataController(inMemory: true)
        sut = RecipeCoreDataRepository(dataController: dataController)
    }

    override func tearDown() {
        sut = nil
        dataController = nil
        super.tearDown()
    }

    // MARK: - fetchAll

    func test_fetchAll_emptyDatabase_returnsEmptyArray() {
        XCTAssertEqual(sut.fetchAll(), [])
    }

    func test_fetchAll_afterSave_returnsRecipe() throws {
        let recipe = Recipe(id: UUID(), name: "Phở Bò")
        try sut.save(recipe)

        let fetched = sut.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Phở Bò")
    }

    func test_fetchAll_multipleRecipes_returnsAll() throws {
        try sut.save(Recipe(id: UUID(), name: "Phở"))
        try sut.save(Recipe(id: UUID(), name: "Bún Bò"))
        try sut.save(Recipe(id: UUID(), name: "Bánh Mì"))

        XCTAssertEqual(sut.fetchAll().count, 3)
    }

    // MARK: - save (insert vs update)

    func test_save_newRecipe_insertsIntoDatabase() throws {
        let id = UUID()
        let recipe = Recipe(id: id, name: "Cơm Tấm")
        try sut.save(recipe)

        XCTAssertNotNil(sut.fetch(by: id))
    }

    func test_save_existingRecipe_updatesInPlace() throws {
        let id = UUID()
        var recipe = Recipe(id: id, name: "Cơm Tấm")
        try sut.save(recipe)

        recipe.name = "Cơm Tấm Sườn"
        try sut.save(recipe)

        let fetched = sut.fetchAll()
        XCTAssertEqual(fetched.count, 1)  // Không tạo thêm record mới
        XCTAssertEqual(fetched.first?.name, "Cơm Tấm Sườn")
    }

    // MARK: - delete

    func test_delete_existingRecipe_removesFromDatabase() throws {
        let recipe = Recipe(id: UUID(), name: "Hủ Tiếu")
        try sut.save(recipe)
        try sut.delete(recipe)

        XCTAssertEqual(sut.fetchAll().count, 0)
    }

    func test_delete_nonExistentRecipe_doesNotThrow() {
        let recipe = Recipe(id: UUID(), name: "Không Tồn Tại")
        XCTAssertNoThrow(try sut.delete(recipe))
    }

    // MARK: - search

    func test_search_matchingQuery_returnsFilteredResults() throws {
        try sut.save(Recipe(id: UUID(), name: "Phở Bò"))
        try sut.save(Recipe(id: UUID(), name: "Phở Gà"))
        try sut.save(Recipe(id: UUID(), name: "Bún Bò"))

        let results = sut.search(query: "Phở")
        XCTAssertEqual(results.count, 2)
    }

    func test_search_noMatch_returnsEmpty() throws {
        try sut.save(Recipe(id: UUID(), name: "Phở Bò"))

        XCTAssertEqual(sut.search(query: "Pizza").count, 0)
    }

    func test_search_caseInsensitive() throws {
        try sut.save(Recipe(id: UUID(), name: "Phở Bò"))

        XCTAssertEqual(sut.search(query: "phở").count, 1)
        XCTAssertEqual(sut.search(query: "PHỞ").count, 1)
    }

    // MARK: - toggleFavorite

    func test_toggleFavorite_setsTrue() throws {
        let recipe = Recipe(id: UUID(), name: "Test", isFavorite: false)
        try sut.save(recipe)
        try sut.toggleFavorite(recipe)

        XCTAssertEqual(sut.fetchFavorites().count, 1)
    }

    func test_toggleFavorite_togglesBack() throws {
        let recipe = Recipe(id: UUID(), name: "Test", isFavorite: false)
        try sut.save(recipe)
        try sut.toggleFavorite(recipe)
        try sut.toggleFavorite(recipe)

        XCTAssertEqual(sut.fetchFavorites().count, 0)
    }
}
```

### 4. ViewModel Tests (Mock repository — không cần Core Data)

**`CookbookAppTests/ViewModels/RecipeDetailViewModelTests.swift`**
```swift
import XCTest
import Combine
@testable import CookbookApp

final class RecipeDetailViewModelTests: XCTestCase {
    var sut: RecipeDetailViewModel!
    var mockRepo: MockRecipeRepository!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockRepo = MockRecipeRepository()
        cancellables = []
    }

    override func tearDown() {
        sut = nil
        mockRepo = nil
        cancellables = nil
        super.tearDown()
    }

    func test_toggleFavorite_updatesRecipeState() {
        let recipe = Recipe(id: UUID(), name: "Test", isFavorite: false)
        mockRepo.recipes = [recipe]
        sut = RecipeDetailViewModel(recipe: recipe, repository: mockRepo)

        sut.toggleFavorite()

        XCTAssertTrue(sut.recipe.isFavorite)
    }

    func test_toggleFavorite_whenSaveFails_setsErrorMessage() {
        let recipe = Recipe(id: UUID(), name: "Test", isFavorite: false)
        mockRepo.recipes = [recipe]
        mockRepo.saveError = NSError(domain: "test", code: 0)
        sut = RecipeDetailViewModel(recipe: recipe, repository: mockRepo)

        sut.toggleFavorite()

        XCTAssertNotNil(sut.errorMessage)
    }

    func test_deleteRecipe_callsRepositoryDelete() throws {
        let recipe = Recipe(id: UUID(), name: "Test")
        mockRepo.recipes = [recipe]
        sut = RecipeDetailViewModel(recipe: recipe, repository: mockRepo)

        var completionCalled = false
        sut.deleteRecipe { completionCalled = true }

        XCTAssertTrue(completionCalled)
        XCTAssertEqual(mockRepo.deleteCallCount, 1)
        XCTAssertTrue(mockRepo.recipes.isEmpty)
    }
}
```

---

## Todo List
- [ ] Cập nhật `DataController.init(inMemory:)` parameter
- [ ] Tạo `CookbookAppTests` target trong Xcode (nếu chưa có)
- [ ] Tạo `MockRecipeRepository.swift`
- [ ] Tạo `RecipeCoreDataRepositoryTests.swift`
- [ ] Tạo `RecipeDetailViewModelTests.swift`
- [ ] Run tests: ⌘U → tất cả phải pass
- [ ] Thêm tests cho `CategoryCoreDataRepository` (tương tự)

## Success Criteria
- Tất cả unit tests pass (⌘U)
- Repository tests verify CRUD hoạt động đúng
- ViewModel tests verify logic không phụ thuộc Core Data
- Mỗi test độc lập — run theo bất kỳ thứ tự nào vẫn pass
- Test coverage: Repository layer ≥ 80%

## Tiếp Theo
Bạn đã hoàn thành toàn bộ Core Data learning path! Các bước nâng cao tiếp theo:
- **CloudKit Sync:** Đổi sang `NSPersistentCloudKitContainer`
- **SwiftData:** Framework mới của Apple (iOS 17+) thay thế Core Data
- **NSPersistentHistoryTracking:** Cho app extensions + CloudKit
