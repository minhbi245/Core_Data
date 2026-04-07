# Phase 6: Category Management

## Tổng Quan
- **Priority:** P1
- **Status:** [ ] Not Started
- **Core Data concepts:** Aggregate fetch (COUNT), Nullify delete rule behavior, expression descriptions

---

## Giải Thích Core Data

### Aggregate Fetch — Đếm số recipes theo category
Thay vì fetch toàn bộ recipes rồi đếm trong memory, Core Data có thể tính trực tiếp trong SQLite:

```swift
// ❌ Không hiệu quả: fetch toàn bộ recipes rồi đếm
let count = recipes.filter { $0.category?.id == category.id }.count

// ✅ Dùng aggregate fetch — chỉ trả về số đếm
let request = NSFetchRequest<NSDictionary>(entityName: "Recipe")
request.resultType = .dictionaryResultType
request.predicate = NSPredicate(format: "category.id == %@", category.id as CVarArg)

let countExpression = NSExpressionDescription()
countExpression.name = "count"
countExpression.expression = NSExpression(forFunction: "count:", arguments: [
    NSExpression(forKeyPath: "id")
])
countExpression.expressionResultType = .integer64AttributeType
request.propertiesToFetch = [countExpression]

let results = try context.fetch(request) as? [[String: Int]]
let count = results?.first?["count"] ?? 0
```

Hoặc đơn giản hơn với `countRequest`:
```swift
// Cách đơn giản nhất
let request = RecipeEntity.fetchRequest()
request.predicate = NSPredicate(format: "category.id == %@", category.id as CVarArg)
let count = (try? context.count(for: request)) ?? 0
// context.count() trả về Int, không fetch objects → rất nhanh
```

### Nullify Delete Rule — Hành vi khi xóa Category
Vì Recipe → Category dùng rule **Nullify**, khi xóa category:
- Category bị xóa khỏi database ✓
- Các Recipes thuộc category đó vẫn còn ✓
- `recipe.category` = `nil` (được set tự động bởi Core Data)

```swift
// Xóa category
context.delete(categoryEntity)
try context.save()
// → Các recipes của category này vẫn tồn tại, chỉ mất category reference
```

⚠️ **Không thể dùng Deny rule** nếu muốn xóa category khi còn recipes. Nếu muốn block xóa, phải check thủ công:
```swift
let recipeCount = (try? context.count(for: request)) ?? 0
if recipeCount > 0 {
    throw CategoryError.hasRecipes(count: recipeCount)
}
```

---

## Files Cần Tạo / Sửa

### 1. Cập nhật CategoryCoreDataRepository

**`Data/CoreData/Repositories/CategoryCoreDataRepository.swift`**
```swift
import CoreData

final class CategoryCoreDataRepository: CategoryRepositoryProtocol {
    private let dataController: DataController

    init(dataController: DataController = .shared) {
        self.dataController = dataController
    }

    func fetchAll() -> [RecipeCategory] {
        let request = CategoryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CategoryEntity.name, ascending: true)]
        return (try? dataController.viewContext.fetch(request))?.map { $0.toDomain() } ?? []
    }

    /// Đếm số recipes trong category — dùng context.count() thay vì fetch objects
    func recipeCount(for category: RecipeCategory) -> Int {
        let request = RecipeEntity.fetchRequest()
        request.predicate = NSPredicate(format: "category.id == %@", category.id as CVarArg)
        return (try? dataController.viewContext.count(for: request)) ?? 0
    }

    func save(_ category: RecipeCategory) throws {
        let context = dataController.viewContext
        let entity = findEntity(id: category.id, in: context) ?? CategoryEntity(context: context)
        entity.id = category.id
        entity.name = category.name
        entity.icon = category.icon
        try context.save()
    }

    func delete(_ category: RecipeCategory) throws {
        guard let entity = findEntity(id: category.id, in: dataController.viewContext) else { return }
        dataController.viewContext.delete(entity)
        try dataController.viewContext.save()
        // Core Data tự set recipe.category = nil cho tất cả recipes liên quan
    }

    private func findEntity(id: UUID, in context: NSManagedObjectContext) -> CategoryEntity? {
        let request = CategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
```

### 2. ViewModel

**`Presentation/ViewModels/CategoryListViewModel.swift`**
```swift
import Combine
import Foundation

final class CategoryListViewModel {
    @Published var categories: [(category: RecipeCategory, recipeCount: Int)] = []
    @Published var errorMessage: String?

    private let categoryRepo: CategoryRepositoryProtocol
    private let recipeRepo: CategoryCoreDataRepository

    init(categoryRepo: CategoryRepositoryProtocol = CategoryCoreDataRepository()) {
        self.categoryRepo = categoryRepo
        self.recipeRepo = CategoryCoreDataRepository()
    }

    func loadCategories() {
        let cats = categoryRepo.fetchAll()
        categories = cats.map { cat in
            let count = recipeRepo.recipeCount(for: cat)
            return (category: cat, recipeCount: count)
        }
    }

    func addCategory(name: String, icon: String) {
        let newCat = RecipeCategory(id: UUID(), name: name, icon: icon)
        do {
            try categoryRepo.save(newCat)
            loadCategories()
        } catch {
            errorMessage = "Không thể thêm: \(error.localizedDescription)"
        }
    }

    func deleteCategory(_ category: RecipeCategory) {
        do {
            try categoryRepo.delete(category)
            loadCategories()
        } catch {
            errorMessage = "Không thể xóa: \(error.localizedDescription)"
        }
    }
}
```

### 3. ViewController

**`Presentation/Views/Screens/Categories/CategoryListViewController.swift`**
```swift
import UIKit
import SnapKit
import Combine

final class CategoryListViewController: UIViewController {
    private let viewModel = CategoryListViewModel()
    private var cancellables = Set<AnyCancellable>()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "CategoryCell")
        tv.delegate = self
        tv.dataSource = self
        return tv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        viewModel.loadCategories()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadCategories()  // Refresh sau khi quay lại (recipe count có thể thay đổi)
    }

    private func setupUI() {
        title = "Phân Loại"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addCategoryTapped)
        )
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func bindViewModel() {
        viewModel.$categories
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &cancellables)
    }

    @objc private func addCategoryTapped() {
        showCategoryAlert(title: "Thêm Phân Loại", existingName: nil, existingIcon: nil) {
            [weak self] name, icon in
            self?.viewModel.addCategory(name: name, icon: icon)
        }
    }

    private func showCategoryAlert(title: String, existingName: String?,
                                    existingIcon: String?,
                                    completion: @escaping (String, String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Tên phân loại (ví dụ: Pasta)"
            tf.text = existingName
        }
        alert.addTextField { tf in
            tf.placeholder = "SF Symbol (ví dụ: fork.knife)"
            tf.text = existingIcon ?? "folder"
        }
        alert.addAction(UIAlertAction(title: "Lưu", style: .default) { _ in
            let name = alert.textFields?[0].text ?? ""
            let icon = alert.textFields?[1].text ?? "folder"
            guard !name.isEmpty else { return }
            completion(name, icon)
        })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }
}

extension CategoryListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.categories.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell", for: indexPath)
        let item = viewModel.categories[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.image = UIImage(systemName: item.category.icon)
        config.imageProperties.tintColor = UIColor(hex: "#E8730E")
        config.text = item.category.name
        // Hiển thị số recipe ở bên phải
        config.secondaryText = "\(item.recipeCount) công thức"
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // Swipe to delete
    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let item = viewModel.categories[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: "Xóa") {
            [weak self] _, _, done in
            self?.confirmDelete(item.category, recipeCount: item.recipeCount)
            done(true)
        }
        let editAction = UIContextualAction(style: .normal, title: "Sửa") {
            [weak self] _, _, done in
            self?.showCategoryAlert(title: "Sửa Phân Loại",
                                     existingName: item.category.name,
                                     existingIcon: item.category.icon) { name, icon in
                var updated = item.category
                updated.name = name
                updated.icon = icon
                try? self?.viewModel.categoryRepo.save(updated)
                self?.viewModel.loadCategories()
            }
            done(true)
        }
        editAction.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [deleteAction, editAction])
    }

    private func confirmDelete(_ category: RecipeCategory, recipeCount: Int) {
        let message = recipeCount > 0
            ? "Category này có \(recipeCount) công thức. Sau khi xóa, các công thức sẽ mất phân loại."
            : "Xóa phân loại \"\(category.name)\"?"
        let alert = UIAlertController(title: "Xóa?", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteCategory(category)
        })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }
}
```

---

## Todo List
- [ ] Hoàn thiện `CategoryCoreDataRepository.swift` với `recipeCount(for:)`
- [ ] Tạo `CategoryListViewModel.swift`
- [ ] Tạo `CategoryListViewController.swift`
- [ ] Thêm tab bar hoặc navigation entry point cho Category screen
- [ ] Seed vài categories để test
- [ ] Test: xóa category → recipes vẫn còn, chỉ mất `category` reference
- [ ] Test: recipe count hiển thị đúng sau khi thêm/xóa recipes

## Success Criteria
- Danh sách categories hiển thị đúng recipe count
- Xóa category → recipes không bị xóa (Nullify rule)
- Thêm/sửa category → cập nhật ngay trong list
- Cảnh báo khi xóa category có recipes

## Tiếp Theo
→ [Phase 7: Background Context & Batch Operations](phase-07-background-context-batch-operations.md)
