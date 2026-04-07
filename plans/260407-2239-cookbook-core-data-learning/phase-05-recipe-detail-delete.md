# Phase 5: Recipe Detail & Delete

## Tổng Quan
- **Priority:** P1
- **Status:** [ ] Not Started
- **Core Data concepts:** Fetch by ID, delete với cascade rules, update single attribute, object fault/unfault

---

## Giải Thích Core Data

### Object Faulting
Core Data dùng kỹ thuật "fault" để tiết kiệm bộ nhớ — data của relationship chỉ load khi bạn truy cập:

```swift
let recipe = recipeEntity  // recipe.steps chưa load (is a "fault")
let steps = recipe.steps   // ← Lúc này mới fetch steps từ SQLite ("fire the fault")
```

Đây là lý do bạn nên convert NSManagedObject → Domain struct NGAY trong repository, trước khi truyền lên ViewModel. Tránh truy cập NSManagedObject trên wrong thread.

### Delete với Cascade
Khi xóa Recipe, Core Data tự động xóa các Steps và RecipeIngredients liên quan (delete rule = Cascade):

```swift
context.delete(recipeEntity)  // ← Core Data tự xóa Steps, RecipeIngredients
try context.save()
// Tags và Category vẫn còn (delete rule = Nullify)
```

### Update Single Attribute
Không cần tạo lại toàn bộ object — chỉ thay đổi attribute cần update:

```swift
guard let entity = findEntity(id: recipe.id) else { return }
entity.isFavorite.toggle()   // ← Chỉ thay đổi 1 field
try context.save()           // ← Core Data tự track, chỉ save change này
```

### fetchLimit
Khi chỉ cần 1 object (fetch by ID), dùng `fetchLimit = 1` để tối ưu:

```swift
request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
request.fetchLimit = 1  // ← Dừng ngay khi tìm thấy 1 kết quả
```

---

## Files Cần Tạo

### 1. ViewModel

**`Presentation/ViewModels/RecipeDetailViewModel.swift`**
```swift
import Combine
import Foundation

final class RecipeDetailViewModel {
    @Published var recipe: Recipe
    @Published var errorMessage: String?

    private let repository: RecipeRepositoryProtocol

    init(recipe: Recipe,
         repository: RecipeRepositoryProtocol = RecipeCoreDataRepository()) {
        self.recipe = recipe
        self.repository = repository
    }

    func toggleFavorite() {
        do {
            try repository.toggleFavorite(recipe)
            recipe.isFavorite.toggle()  // Update local state immediately (optimistic)
        } catch {
            errorMessage = "Không thể cập nhật: \(error.localizedDescription)"
        }
    }

    func deleteRecipe(completion: @escaping () -> Void) {
        do {
            try repository.delete(recipe)
            completion()
        } catch {
            errorMessage = "Không thể xóa: \(error.localizedDescription)"
        }
    }
}
```

### 2. ViewController

**`Presentation/Views/Screens/RecipeDetail/RecipeDetailViewController.swift`**
```swift
import UIKit
import SnapKit
import Combine

final class RecipeDetailViewController: UIViewController {
    private let viewModel: RecipeDetailViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI
    private lazy var scrollView = UIScrollView()
    private lazy var contentStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 0
        return sv
    }()
    private lazy var heroImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(hex: "#FDEAD2")
        iv.image = UIImage(systemName: "photo.on.rectangle")
        iv.tintColor = UIColor(hex: "#E8730E")
        return iv
    }()
    private lazy var nameLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont.preferredFont(forTextStyle: .title2)
        l.numberOfLines = 0
        return l
    }()
    private lazy var favoriteButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        return btn
    }()
    private lazy var editFAB: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "pencil"), for: .normal)
        btn.backgroundColor = UIColor(hex: "#E8730E")
        btn.tintColor = .white
        btn.layer.cornerRadius = 28
        btn.layer.shadowOpacity = 0.15
        btn.layer.shadowOffset = CGSize(width: 0, height: 4)
        btn.layer.shadowRadius = 12
        btn.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        return btn
    }()

    // MARK: - Init
    init(recipe: Recipe) {
        self.viewModel = RecipeDetailViewModel(recipe: recipe)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        populateData()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        // Delete button in nav bar
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(deleteTapped)
        )
        navigationItem.rightBarButtonItem?.tintColor = .systemRed

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(editFAB)

        scrollView.snp.makeConstraints { $0.edges.equalToSuperview() }
        contentStack.snp.makeConstraints {
            $0.edges.equalToSuperview()
            $0.width.equalTo(scrollView)
        }
        editFAB.snp.makeConstraints {
            $0.right.equalTo(view.safeAreaLayoutGuide).inset(16)
            $0.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
            $0.size.equalTo(CGSize(width: 56, height: 56))
        }

        // Build content sections
        contentStack.addArrangedSubview(heroImageView)
        heroImageView.snp.makeConstraints { $0.height.equalTo(250) }

        let infoView = buildInfoSection()
        contentStack.addArrangedSubview(infoView)
    }

    private func buildInfoSection() -> UIView {
        let container = UIView()
        container.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        [nameLabel, favoriteButton].forEach { container.addSubview($0) }

        nameLabel.snp.makeConstraints {
            $0.top.left.equalTo(container.layoutMarginsGuide)
            $0.right.equalTo(favoriteButton.snp.left).offset(-8)
        }
        favoriteButton.snp.makeConstraints {
            $0.centerY.equalTo(nameLabel)
            $0.right.equalTo(container.layoutMarginsGuide)
            $0.size.equalTo(CGSize(width: 44, height: 44))
        }
        container.snp.makeConstraints { $0.bottom.equalTo(nameLabel.snp.bottom).offset(16) }

        return container
    }

    private func bindViewModel() {
        viewModel.$recipe
            .receive(on: RunLoop.main)
            .sink { [weak self] recipe in
                self?.populateData()
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] msg in
                let alert = UIAlertController(title: "Lỗi", message: msg, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
            .store(in: &cancellables)
    }

    private func populateData() {
        let recipe = viewModel.recipe
        title = recipe.name
        nameLabel.text = recipe.name
        if let data = recipe.imageData {
            heroImageView.image = UIImage(data: data)
        }
        let heartSymbol = recipe.isFavorite ? "heart.fill" : "heart"
        favoriteButton.setImage(UIImage(systemName: heartSymbol), for: .normal)
        favoriteButton.tintColor = recipe.isFavorite ? .systemRed : .secondaryLabel
    }

    // MARK: - Actions
    @objc private func favoriteTapped() {
        viewModel.toggleFavorite()
    }

    @objc private func editTapped() {
        let vc = CreateEditRecipeViewController(mode: .edit(viewModel.recipe))
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func deleteTapped() {
        let alert = UIAlertController(
            title: "Xóa công thức?",
            message: "Hành động này không thể hoàn tác.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteRecipe {
                DispatchQueue.main.async {
                    self?.navigationController?.popViewController(animated: true)
                }
            }
        })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }
}
```

---

## Todo List
- [ ] Tạo `RecipeDetailViewModel.swift`
- [ ] Tạo `RecipeDetailViewController.swift`
- [ ] Hoàn thiện `buildInfoSection()` với stats row (cook time, servings)
- [ ] Thêm Ingredients section vào scroll view
- [ ] Thêm Steps section vào scroll view (numbered)
- [ ] Thêm Tags row (horizontal chips)
- [ ] Test: xóa recipe → Steps và Ingredients bị xóa theo (Cascade)
- [ ] Test: toggle favorite → cập nhật icon ngay lập tức

## Success Criteria
- Recipe detail hiển thị đầy đủ: ảnh, stats, ingredients, steps, tags
- Xóa recipe → pop về list + list tự cập nhật (FRC)
- Toggle favorite → heart icon đổi ngay, RecipeList cũng cập nhật
- Cascade delete: sau khi xóa recipe, database không còn orphan Steps/RecipeIngredients

## Tiếp Theo
→ [Phase 6: Category Management](phase-06-category-management.md)
