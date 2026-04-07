# Phase 4: Create & Edit Recipe

## Tổng Quan
- **Priority:** P0
- **Status:** [ ] Not Started
- **Core Data concepts:** Insert/update NSManagedObject, manage relationships, ordered NSOrderedSet (Steps), many-to-many (Tags), transaction pattern

---

## Giải Thích Core Data

### Insert vs Update — Cùng một code path
Thay vì viết 2 function riêng, ta tìm existing entity hoặc tạo mới:
```swift
// Tìm entity theo id — nếu không có thì tạo mới
let entity = findEntity(id: recipe.id) ?? RecipeEntity(context: context)
// Populate data (cả insert lẫn update)
entity.name = recipe.name
try context.save()
```

### Quản lý To-Many Relationship
Core Data dùng `NSSet` (unordered) hoặc `NSOrderedSet` (ordered) cho to-many:

```swift
// Thêm 1 object vào relationship
recipe.addToTags(tagEntity)         // Generated method
recipe.addToSteps(stepEntity)

// Xóa 1 object khỏi relationship
recipe.removeFromTags(tagEntity)

// Xóa toàn bộ và set lại (cách an toàn khi edit)
recipe.tags = NSSet(array: newTagEntities)
recipe.steps = NSOrderedSet(array: newStepEntities)
```

### Ordered Relationship (Steps)
Vì Step cần thứ tự, ta dùng `NSOrderedSet`:
```swift
// Lấy steps theo thứ tự
let orderedSteps = recipe.steps?.array as? [StepEntity] ?? []

// Reorder: chỉ cần update orderIndex của từng step
for (index, step) in steps.enumerated() {
    step.orderIndex = Int16(index)
}
```

### Many-to-Many (Tags)
Tags được chia sẻ giữa nhiều recipes. Khi xóa recipe, tag không bị xóa (Nullify rule):
```swift
// Gán tags cho recipe
let tagEntities = selectedTags.compactMap { findOrCreateTag($0) }
recipe.tags = NSSet(array: tagEntities)

// Core Data tự quản lý junction table ẩn — bạn không cần tạo thêm entity
```

### Transaction Pattern — Rollback khi có lỗi
```swift
do {
    // Thực hiện thay đổi
    try populateAllRelationships()
    try context.save()  // Commit
} catch {
    context.rollback()  // Hoàn tác toàn bộ thay đổi
    throw error
}
```

---

## Files Cần Tạo / Sửa

### 1. Cập nhật Repository Mapping

**`Data/CoreData/Models/RecipeEntity+Mapping.swift`** — Thêm relationship mapping:
```swift
extension RecipeEntity {
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

        // Category (many-to-one)
        if let cat = recipe.category {
            let catRequest = CategoryEntity.fetchRequest()
            catRequest.predicate = NSPredicate(format: "id == %@", cat.id as CVarArg)
            self.category = (try? context.fetch(catRequest))?.first
        } else {
            self.category = nil
        }

        // Tags (many-to-many) — xóa cũ, set lại
        self.tags = nil
        let tagEntities: [TagEntity] = recipe.tags.compactMap { tag in
            let req = TagEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", tag.id as CVarArg)
            if let existing = (try? context.fetch(req))?.first { return existing }
            let newTag = TagEntity(context: context)
            newTag.id = tag.id
            newTag.name = tag.name
            newTag.colorHex = tag.colorHex
            return newTag
        }
        self.tags = NSSet(array: tagEntities)

        // Steps (one-to-many, ordered) — xóa cũ, tạo lại
        if let oldSteps = self.steps?.array as? [StepEntity] {
            oldSteps.forEach { context.delete($0) }
        }
        let stepEntities: [StepEntity] = recipe.steps.enumerated().map { index, step in
            let stepEntity = StepEntity(context: context)
            stepEntity.id = step.id
            stepEntity.orderIndex = Int16(index)
            stepEntity.instruction = step.instruction
            stepEntity.imageData = step.imageData
            stepEntity.recipe = self
            return stepEntity
        }
        self.steps = NSOrderedSet(array: stepEntities)

        // Ingredients (via RecipeIngredient junction)
        if let oldIngredients = self.recipeIngredients as? Set<RecipeIngredientEntity> {
            oldIngredients.forEach { context.delete($0) }
        }
        let riEntities: [RecipeIngredientEntity] = recipe.ingredients.map { item in
            // Tìm hoặc tạo Ingredient
            let ingReq = IngredientEntity.fetchRequest()
            ingReq.predicate = NSPredicate(format: "name ==[cd] %@", item.ingredient.name)
            let ingEntity = (try? context.fetch(ingReq))?.first ?? {
                let newIng = IngredientEntity(context: context)
                newIng.id = item.ingredient.id
                newIng.name = item.ingredient.name
                return newIng
            }()

            let ri = RecipeIngredientEntity(context: context)
            ri.id = item.id
            ri.quantity = item.quantity
            ri.unit = item.unit
            ri.ingredient = ingEntity
            ri.recipe = self
            return ri
        }
        self.recipeIngredients = NSSet(array: riEntities)
    }
}
```

### 2. ViewModel

**`Presentation/ViewModels/CreateEditRecipeViewModel.swift`**
```swift
import Combine
import Foundation

enum CreateEditMode {
    case create
    case edit(Recipe)
}

final class CreateEditRecipeViewModel {
    // Form state
    @Published var name: String = ""
    @Published var recipeDescription: String = ""
    @Published var cookTime: Int = 30
    @Published var prepTime: Int = 15
    @Published var servings: Int = 2
    @Published var rating: Float = 0
    @Published var selectedCategory: RecipeCategory?
    @Published var selectedTags: [RecipeTag] = []
    @Published var ingredients: [RecipeIngredientItem] = []
    @Published var steps: [RecipeStep] = []
    @Published var imageData: Data?

    // Validation
    @Published var isSaveEnabled: Bool = false
    @Published var errorMessage: String?

    let mode: CreateEditMode
    private let recipeRepo: RecipeRepositoryProtocol
    private let categoryRepo: CategoryRepositoryProtocol
    var cancellables = Set<AnyCancellable>()

    init(mode: CreateEditMode,
         recipeRepo: RecipeRepositoryProtocol = RecipeCoreDataRepository(),
         categoryRepo: CategoryRepositoryProtocol = CategoryCoreDataRepository()) {
        self.mode = mode
        self.recipeRepo = recipeRepo
        self.categoryRepo = categoryRepo

        if case .edit(let recipe) = mode {
            populateFromRecipe(recipe)
        }

        $name
            .map { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .assign(to: &$isSaveEnabled)
    }

    private func populateFromRecipe(_ recipe: Recipe) {
        name = recipe.name
        recipeDescription = recipe.recipeDescription
        cookTime = recipe.cookTime
        prepTime = recipe.prepTime
        servings = recipe.servings
        rating = recipe.rating
        selectedCategory = recipe.category
        selectedTags = recipe.tags
        ingredients = recipe.ingredients
        steps = recipe.steps
        imageData = recipe.imageData
    }

    func save() throws {
        let id: UUID
        if case .edit(let existing) = mode {
            id = existing.id
        } else {
            id = UUID()
        }

        let recipe = Recipe(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            recipeDescription: recipeDescription,
            cookTime: cookTime,
            prepTime: prepTime,
            servings: servings,
            rating: rating,
            isFavorite: false,
            createdAt: Date(),
            imageData: imageData,
            category: selectedCategory,
            tags: selectedTags,
            ingredients: ingredients,
            steps: steps.enumerated().map { idx, step in
                RecipeStep(id: step.id, orderIndex: idx,
                           instruction: step.instruction, imageData: step.imageData)
            }
        )
        try recipeRepo.save(recipe)
    }

    // MARK: - Helpers
    func fetchCategories() -> [RecipeCategory] { categoryRepo.fetchAll() }

    func addStep(_ instruction: String) {
        steps.append(RecipeStep(id: UUID(), orderIndex: steps.count, instruction: instruction))
    }

    func removeStep(at index: Int) {
        steps.remove(at: index)
    }

    func addIngredient(name: String, quantity: Double, unit: String) {
        let ingredient = RecipeIngredient(id: UUID(), name: name)
        ingredients.append(RecipeIngredientItem(id: UUID(), ingredient: ingredient,
                                                 quantity: quantity, unit: unit))
    }

    func removeIngredient(at index: Int) {
        ingredients.remove(at: index)
    }
}
```

### 3. ViewController (skeleton)

**`Presentation/Views/Screens/CreateEditRecipe/CreateEditRecipeViewController.swift`**
```swift
import UIKit
import SnapKit
import Combine

final class CreateEditRecipeViewController: UIViewController {
    private let viewModel: CreateEditRecipeViewModel
    private var cancellables = Set<AnyCancellable>()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.delegate = self
        tv.dataSource = self
        return tv
    }()

    init(mode: CreateEditMode) {
        self.viewModel = CreateEditRecipeViewModel(mode: mode)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        registerCells()
    }

    private func setupUI() {
        title = viewModel.mode == .create ? "Thêm Công Thức" : "Chỉnh Sửa"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(saveTapped))
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func bindViewModel() {
        viewModel.$isSaveEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.navigationItem.rightBarButtonItem?.isEnabled = enabled
            }
            .store(in: &cancellables)
    }

    private func registerCells() {
        // Register các cell types cho form sections
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BasicCell")
        tableView.register(TextFieldCell.self, forCellReuseIdentifier: TextFieldCell.reuseID)
        tableView.register(StepInputCell.self, forCellReuseIdentifier: StepInputCell.reuseID)
        tableView.register(IngredientInputCell.self, forCellReuseIdentifier: IngredientInputCell.reuseID)
    }

    @objc private func saveTapped() {
        do {
            try viewModel.save()
            navigationController?.popViewController(animated: true)
        } catch {
            showAlert(message: "Không thể lưu: \(error.localizedDescription)")
        }
    }

    @objc private func cancelTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: "Lỗi", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableView (form sections)
// Sections: [0] Ảnh, [1] Thông tin cơ bản, [2] Category,
//           [3] Tags, [4] Ingredients, [5] Steps
extension CreateEditRecipeViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 6 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1  // Ảnh
        case 1: return 5  // Name, Description, CookTime, PrepTime, Servings
        case 2: return 1  // Category
        case 3: return 1  // Tags (show chip view)
        case 4: return viewModel.ingredients.count + 1  // Ingredients + "Add" row
        case 5: return viewModel.steps.count + 1        // Steps + "Add" row
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Ảnh", "Thông tin", "Phân loại", "Tags", "Nguyên liệu", "Các bước"][safe: section]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Chi tiết implement từng cell theo từng section
        let cell = tableView.dequeueReusableCell(withIdentifier: "BasicCell", for: indexPath)
        cell.textLabel?.text = "Section \(indexPath.section), Row \(indexPath.row)"
        return cell
    }
}

// Helper extension
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

---

## Todo List
- [ ] Cập nhật `RecipeEntity+Mapping.swift` với đầy đủ relationship mapping
- [ ] Tạo `CreateEditRecipeViewModel.swift`
- [ ] Tạo `CreateEditRecipeViewController.swift` (skeleton + form sections)
- [ ] Tạo `TextFieldCell.swift` (UITableViewCell với UITextField)
- [ ] Tạo `StepInputCell.swift` (UITableViewCell cho steps)
- [ ] Tạo `IngredientInputCell.swift`
- [ ] Test: tạo recipe với category + steps + ingredients → verify lưu đúng
- [ ] Test: edit recipe → verify data đúng khi reload

## Success Criteria
- Tạo recipe mới với category, steps, ingredients → tự xuất hiện trong RecipeList
- Edit recipe → data cũ load đúng trong form
- Save → FRC cập nhật RecipeList mà không cần reload
- Step order được giữ đúng sau khi save

## Tiếp Theo
→ [Phase 5: Recipe Detail & Delete](phase-05-recipe-detail-delete.md)
