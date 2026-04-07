---
title: Core Data Cookbook iOS App — Project Structure & Tech Stack Research
date: 2026-04-07
context: MVVM + Clean Architecture, UIKit + SnapKit + Combine, Core Data persistence
---

# Báo Cáo Nghiên Cứu: Cấu Trúc Dự Án & Tech Stack cho Ứng Dụng Cookbook iOS

## 1. Cấu Trúc Folder Tối Ưu (MVVM + Clean Architecture)

```
CookbookApp/
├── App/
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   └── Resources/
│       ├── Colors.xcassets
│       ├── Images.xcassets
│       └── Localizable.strings
│
├── Data/
│   ├── CoreData/
│   │   ├── Models/
│   │   │   └── CoreDataModels.xcdatamodeld
│   │   ├── Repositories/
│   │   │   ├── RecipeRepository.swift
│   │   │   ├── CategoryRepository.swift
│   │   │   ├── IngredientRepository.swift
│   │   │   └── TagRepository.swift
│   │   └── CoreDataStack.swift
│   └── Local/
│       └── UserDefaults/ (nếu cần cache)
│
├── Domain/
│   ├── Entities/
│   │   ├── Recipe.swift
│   │   ├── Category.swift
│   │   ├── Ingredient.swift
│   │   ├── RecipeIngredient.swift
│   │   ├── Tag.swift
│   │   └── Step.swift
│   ├── UseCases/
│   │   ├── FetchRecipesUseCase.swift
│   │   ├── CreateRecipeUseCase.swift
│   │   ├── UpdateRecipeUseCase.swift
│   │   ├── DeleteRecipeUseCase.swift
│   │   └── FilterRecipesUseCase.swift
│   └── Protocols/
│       ├── RecipeRepository.swift (protocol)
│       └── ImageRepository.swift (protocol)
│
├── Presentation/
│   ├── Navigation/
│   │   └── AppCoordinator.swift
│   ├── ViewModels/
│   │   ├── RecipeListViewModel.swift
│   │   ├── RecipeDetailViewModel.swift
│   │   ├── CreateRecipeViewModel.swift
│   │   └── CategoryFilterViewModel.swift
│   └── Views/
│       ├── Screens/
│       │   ├── RecipeList/
│       │   │   ├── RecipeListViewController.swift
│       │   │   ├── RecipeListCell.swift
│       │   │   └── RecipeListCell.swift
│       │   ├── RecipeDetail/
│       │   │   ├── RecipeDetailViewController.swift
│       │   │   ├── StepCollectionViewCell.swift
│       │   │   └── IngredientTableViewCell.swift
│       │   └── CreateRecipe/
│       │       ├── CreateRecipeViewController.swift
│       │       └── StepInputView.swift
│       └── Components/
│           ├── RecipeCard.swift
│           ├── StepRow.swift
│           ├── IngredientRow.swift
│           └── RatingView.swift
│
└── Utilities/
    ├── Extensions/
    │   ├── UIView+Extensions.swift
    │   ├── String+Extensions.swift
    │   └── Date+Extensions.swift
    ├── Constants/
    │   └── AppConstants.swift
    └── Helpers/
        └── ImageCacheManager.swift
```

**Lý do cấu trúc này:**
- `Data/` tách biệt Core Data implementation (có thể swap sang Realm sau)
- `Domain/` không phụ thuộc UIKit → dễ test, reuse
- `Presentation/` chứa UI logic riêng biệt → ViewController chỉ là view
- Protocol-based repositories → dependency injection dễ

---

## 2. Core Data Entity Diagram & Delete Rules

```
┌─────────────┐
│   Recipe    │ (Name, cookTime, servings, rating, isFavorite, createdAt, image)
└──────┬──────┘
       │
       ├─→ [many-to-one] Category (Name, icon)
       │   Delete Rule: Nullify (recipe vẫn tồn tại nếu xóa category)
       │
       ├─→ [one-to-many, ordered] Step (orderIndex, instruction, image)
       │   Delete Rule: Cascade (xóa recipe → xóa steps)
       │
       ├─→ [one-to-many] RecipeIngredient (quantity, unit) ← JUNCTION
       │   Delete Rule: Cascade (xóa recipe → xóa mappings)
       │   │
       │   └─→ [many-to-one] Ingredient (name, unit)
       │       Delete Rule: Nullify (ingredient vẫn tồn tại)
       │
       └─→ [many-to-many via junction] Tag (name, color)
           RecipeTag junction entity
           Delete Rule: Cascade (xóa recipe → xóa mappings)
           Delete Rule: Nullify (Tag vẫn tồn tại)
```

**Core Data Model Code (Pseudo-NSManagedObject):**

```swift
// Recipe
@NSManaged var id: UUID
@NSManaged var name: String
@NSManaged var cookTime: Int16  // minutes
@NSManaged var servings: Int16
@NSManaged var rating: Float
@NSManaged var isFavorite: Bool
@NSManaged var createdAt: Date
@NSManaged var imageData: Data?

// Relationships
@NSManaged var category: Category?
@NSManaged var steps: NSOrderedSet?  // Ordered for display
@NSManaged var recipeIngredients: NSSet?
@NSManaged var tags: NSSet?

// Category
@NSManaged var name: String
@NSManaged var icon: String
@NSManaged var recipes: NSSet?

// Step (ordered)
@NSManaged var orderIndex: Int16
@NSManaged var instruction: String
@NSManaged var imageData: Data?
@NSManaged var recipe: Recipe?

// Ingredient
@NSManaged var name: String
@NSManaged var unit: String  // "g", "ml", "tbsp"
@NSManaged var recipeIngredients: NSSet?

// RecipeIngredient (Junction)
@NSManaged var quantity: Double
@NSManaged var recipe: Recipe?
@NSManaged var ingredient: Ingredient?

// Tag
@NSManaged var name: String
@NSManaged var color: String  // hex
@NSManaged var recipes: NSSet?
```

---

## 3. Dependency Management: SPM vs CocoaPods

| Tiêu chí | SPM | CocoaPods |
|----------|-----|----------|
| **Setup** | Xcode integrated | Require Podfile, pod install |
| **SnapKit** | ✅ Support | ✅ Support |
| **iOS 15+** | ✅ Native | ✅ Support |
| **Kingfisher** | ✅ Support | ✅ Support |
| **Combine** | ✅ Native | N/A (Apple) |
| **Maintenance** | Apple maintained | Community |
| **Overhead** | Minimal | pod_deintegrate + git |
| **Learning curve** | Lower (Xcode UI) | Medium (terminal) |

**Khuyến nghị: SPM**
- Integrated với Xcode → không cần terminal
- Lightweigh cho project nhỏ
- iOS 15+ full support
- Avoid CocoaPods complexity cho learning project

**SPM Setup:**
```swift
// File → Add Packages
// https://github.com/SnapKit/SnapKit.git, .upToNextMajor(from: "5.0.0")
```

---

## 4. Navigation Pattern: Coordinator vs Simple

| Yếu tố | Coordinator | Simple |
|--------|------------|--------|
| **Scope của app** | 5+ screens complex flow | 3-4 screens (Cookbook OK) |
| **Learning value** | Architecture skill | Implementation speed |
| **Coordinator overhead** | ~200 LOC | None |
| **Testability** | High (protocol-based) | Medium |
| **Coupling** | Low (VCs don't know each other) | Medium (VC → VC) |

**Khuyến nghị: Simple Navigation**

Lý do:
1. Cookbook app: RecipeList → RecipeDetail → CreateRecipe (3 screens)
2. Bạn học Combine, nên tập trung ViewModel reactive binding, không architecture complexity
3. Có thể upgrade sang Coordinator sau khi features tăng

**Simple Implementation:**
```swift
// In ViewController
navigationController?.pushViewController(detailVC, animated: true)
// Dismiss với: navigationController?.popViewController(animated: true)
```

---

## 5. Tech Stack Tối Thiểu

| Thành phần | Library | Version | Dùng cho |
|-----------|---------|---------|----------|
| **Persistence** | Core Data | iOS built-in | Recipe, Categories, Ingredients |
| **Layout** | SnapKit | 5.0+ | UIKit constraints |
| **Images** | Kingfisher | 7.0+ | Remote image cache |
| **Reactive** | Combine | iOS 13+ (built-in) | ViewModel binding |
| **Navigation** | UIKit | built-in | Screen flow |
| **JSON** | Codable | built-in | API mock data |

**KHÔNG cần:**
- Alamofire (no API calls)
- RxSwift (have Combine)
- Redux/MobX (MVVM enough)
- SwiftUI (learning UIKit first)

---

## 6. File Naming Convention

**Khuyến nghị: PascalCase (Swift standard)**

```
✅ RecipeListViewController.swift
✅ RecipeDetailViewModel.swift
✅ CreateRecipeUseCase.swift
❌ recipe-list-view-controller.swift (kebab-case)
```

**Lý do:**
- Swift convention (Apple SDK, official docs)
- Xcode file templates use PascalCase
- IDE autocomplete expects PascalCase
- Team consistency with Swift ecosystem

**Folder naming:** kebab-case (optional, but clear)
```
✅ Presentation/Views/Screens/recipe-list/
✅ Presentation/Views/Screens/recipe-detail/
```

---

## 7. Combine + MVVM Binding Pattern (Quick Example)

```swift
class RecipeListViewModel {
    @Published var recipes: [Recipe] = []
    @Published var isLoading = false
    
    private let fetchRecipesUseCase: FetchRecipesUseCase
    private var cancellables = Set<AnyCancellable>()
    
    func fetchRecipes() {
        isLoading = true
        fetchRecipesUseCase.execute()
            .sink { [weak self] recipes in
                self?.recipes = recipes
                self?.isLoading = false
            }
            .store(in: &cancellables)
    }
}

// In ViewController
override func viewDidLoad() {
    super.viewDidLoad()
    
    viewModel.$recipes
        .receive(on: DispatchQueue.main)
        .sink { [weak self] recipes in
            self?.tableView.reloadData()
        }
        .store(in: &cancellables)
}
```

---

## 8. Kiến Nghị Tóm Tắt

| Hạng mục | Quyết định | Lý do |
|---------|-----------|-------|
| **Folder Structure** | Data/Domain/Presentation | Separation of concerns, testable |
| **Core Data** | Entities + Repositories + UseCases | Clean architecture, easy to swap DB |
| **Dependency** | SPM + SnapKit + Kingfisher | Minimal, integrated, learning focused |
| **Navigation** | Simple push/pop | App scope nhỏ, tập trung vào Combine learning |
| **Naming** | PascalCase files, kebab-case folders | Swift standard |
| **No Junction Entity for Tags** | Use @NSManaged direct many-to-many | Apple supports via inverse relationships |

---

## Unresolved Questions

1. **Image Storage:** Lưu image trong Core Data (BLOB - `Data` type) hay file system + path string?
   - Core Data: simpler, slower for large images
   - File system: faster, manage cache/deletion manually
   - **Recommend:** File system + Kingfisher for recipe images, Core Data for thumbnails only

2. **Sync với Cloud:** iCloud sync (CloudKit) hay local-only?
   - Scope này: local-only (learn Core Data first)
   - CloudKit sync thêm 100+ LOC complexity

3. **Testing:** Unit test Core Data repositories hay skip for learning?
   - **Recommend:** Mock repository protocol, không test Core Data directly
   - Focus on ViewModel + UseCase tests

---

**Report Date:** 2026-04-07  
**Status:** Ready for implementation
