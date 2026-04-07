# Phase 3: Recipe List & NSFetchedResultsController

## Tổng Quan
- **Priority:** P0
- **Status:** [ ] Not Started
- **Core Data concepts:** NSFetchedResultsController, sectionNameKeyPath, delegate methods, FRC cache, UISearchController + NSPredicate

---

## Giải Thích Core Data

### NSFetchedResultsController (FRC) là gì?
FRC là controller đặc biệt **theo dõi Core Data và tự động cập nhật UI** khi data thay đổi.

Không có FRC, bạn phải:
```swift
// Mỗi lần data thay đổi, reload toàn bộ table
tableView.reloadData() // ❌ Xấu, mất animation, chậm
```

Với FRC:
```swift
// FRC tự detect: insert/delete/update/move
// Gọi đúng method: insertRows, deleteRows, reloadRows
// → Animation đẹp, hiệu quả, ít code ❤️
```

### FRC Hoạt Động Thế Nào?
```
Core Data SQLite
      ↕ (observe changes)
NSFetchedResultsController
      ↕ (delegate callbacks)
NSFetchedResultsControllerDelegate (ViewController của bạn)
      ↕ (update UI)
UITableView
```

### sectionNameKeyPath
FRC có thể **tự động nhóm kết quả thành sections** dựa trên một attribute.

```swift
// Nhóm recipes theo category.name
// → Mỗi category = 1 section trong UITableView
frc = NSFetchedResultsController(
    fetchRequest: request,
    managedObjectContext: context,
    sectionNameKeyPath: "category.name",  // ← Tạo sections!
    cacheName: "recipes-cache"
)
```

**Quan trọng:** Sort descriptor đầu tiên PHẢI match với sectionNameKeyPath!
```swift
// ✅ Đúng: sort theo category.name trước
request.sortDescriptors = [
    NSSortDescriptor(keyPath: \RecipeEntity.category?.name, ascending: true),
    NSSortDescriptor(keyPath: \RecipeEntity.name, ascending: true)
]
```

### FRC Cache
FRC có thể cache kết quả để khởi động nhanh hơn.
```swift
cacheName: "recipes-cache"  // Tên cache file
```
⚠️ Phải xóa cache khi thay đổi fetch request hoặc schema:
```swift
NSFetchedResultsController<RecipeEntity>.deleteCache(withName: "recipes-cache")
```

### Delegate Methods
```swift
// 1. Sắp bắt đầu thay đổi
func controllerWillChangeContent(_ controller:) {
    tableView.beginUpdates()
}

// 2. Từng object thay đổi
func controller(_ controller:, didChange anObject:, at indexPath:,
                for type: NSFetchedResultsChangeType, newIndexPath:) {
    switch type {
    case .insert:  tableView.insertRows(at: [newIndexPath!], with: .automatic)
    case .delete:  tableView.deleteRows(at: [indexPath!], with: .automatic)
    case .update:  tableView.reloadRows(at: [indexPath!], with: .automatic)
    case .move:    tableView.moveRow(at: indexPath!, to: newIndexPath!)
    }
}

// 3. Sections thay đổi (khi category mới xuất hiện/mất)
func controller(_ controller:, didChange sectionInfo:,
                atSectionIndex sectionIndex: Int, for type:) {
    switch type {
    case .insert:  tableView.insertSections([sectionIndex], with: .automatic)
    case .delete:  tableView.deleteSections([sectionIndex], with: .automatic)
    }
}

// 4. Hoàn thành thay đổi
func controllerDidChangeContent(_ controller:) {
    tableView.endUpdates()
}
```

---

## Files Cần Tạo

### 1. ViewModel

**`Presentation/ViewModels/RecipeListViewModel.swift`**
```swift
import Combine
import Foundation

final class RecipeListViewModel {
    // Output — ViewController subscribe vào đây
    @Published var searchText: String = ""

    private let repository: RecipeRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    init(repository: RecipeRepositoryProtocol = RecipeCoreDataRepository()) {
        self.repository = repository
    }

    /// Predicate cho FRC dựa trên search text và filter
    func buildPredicate(searchText: String, filter: RecipeFilter) -> NSPredicate? {
        var predicates: [NSPredicate] = []

        if !searchText.isEmpty {
            predicates.append(NSPredicate(format: "name CONTAINS[cd] %@", searchText))
        }

        switch filter {
        case .favorites:
            predicates.append(NSPredicate(format: "isFavorite == true"))
        case .category(let cat):
            predicates.append(NSPredicate(format: "category.id == %@", cat.id as CVarArg))
        case .all:
            break
        }

        return predicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}

enum RecipeFilter: Equatable {
    case all
    case favorites
    case category(RecipeCategory)
}
```

### 2. ViewController

**`Presentation/Views/Screens/RecipeList/RecipeListViewController.swift`**
```swift
import UIKit
import CoreData
import SnapKit
import Combine

final class RecipeListViewController: UIViewController {
    // MARK: - Properties
    private let viewModel = RecipeListViewModel()
    private var frc: NSFetchedResultsController<RecipeEntity>?
    private var cancellables = Set<AnyCancellable>()
    private var currentFilter: RecipeFilter = .all

    // MARK: - UI
    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.register(RecipeListCell.self, forCellReuseIdentifier: RecipeListCell.reuseID)
        tv.delegate = self
        tv.dataSource = self
        return tv
    }()

    private lazy var searchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = "Tìm công thức..."
        return sc
    }()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupFRC()
        bindViewModel()
    }

    // MARK: - Setup
    private func setupUI() {
        title = "Cookbook"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.searchController = searchController
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addRecipeTapped)
        )

        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func setupFRC() {
        let request = RecipeEntity.fetchRequest()
        request.sortDescriptors = [
            // ⚠️ Sort theo sectionNameKeyPath TRƯỚC
            NSSortDescriptor(keyPath: \RecipeEntity.category?.name, ascending: true),
            NSSortDescriptor(keyPath: \RecipeEntity.name, ascending: true)
        ]

        frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: DataController.shared.viewContext,
            sectionNameKeyPath: "category.name",  // Nhóm theo category
            cacheName: "recipes-cache"
        )
        frc?.delegate = self

        performFetch()
    }

    private func performFetch() {
        do {
            try frc?.performFetch()
            tableView.reloadData()
        } catch {
            print("❌ FRC fetch failed: \(error)")
        }
    }

    private func updateFRCPredicate() {
        // Xóa cache khi thay đổi predicate!
        NSFetchedResultsController<RecipeEntity>.deleteCache(withName: "recipes-cache")
        frc?.fetchRequest.predicate = viewModel.buildPredicate(
            searchText: viewModel.searchText,
            filter: currentFilter
        )
        performFetch()
    }

    private func bindViewModel() {
        viewModel.$searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateFRCPredicate() }
            .store(in: &cancellables)
    }

    @objc private func addRecipeTapped() {
        let vc = CreateEditRecipeViewController(mode: .create)
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - UITableView DataSource
extension RecipeListViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return frc?.sections?.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return frc?.sections?[section].numberOfObjects ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RecipeListCell.reuseID,
                                                  for: indexPath) as! RecipeListCell
        if let entity = frc?.object(at: indexPath) {
            cell.configure(with: entity.toDomain())
        }
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return frc?.sections?[section].name ?? "Chưa phân loại"
    }
}

// MARK: - UITableView Delegate
extension RecipeListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 88 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let entity = frc?.object(at: indexPath) else { return }
        let vc = RecipeDetailViewController(recipe: entity.toDomain())
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: - NSFetchedResultsControllerDelegate
extension RecipeListViewController: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any, at indexPath: IndexPath?,
                    for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:  tableView.insertRows(at: [newIndexPath!], with: .automatic)
        case .delete:  tableView.deleteRows(at: [indexPath!], with: .automatic)
        case .update:  tableView.reloadRows(at: [indexPath!], with: .automatic)
        case .move:    tableView.moveRow(at: indexPath!, to: newIndexPath!)
        @unknown default: break
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange sectionInfo: NSFetchedResultsSectionInfo,
                    atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .insert: tableView.insertSections([sectionIndex], with: .automatic)
        case .delete: tableView.deleteSections([sectionIndex], with: .automatic)
        default: break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
}

// MARK: - UISearchResultsUpdating
extension RecipeListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchText = searchController.searchBar.text ?? ""
    }
}
```

### 3. Recipe Cell

**`Presentation/Views/Screens/RecipeList/RecipeListCell.swift`**
```swift
import UIKit
import SnapKit

final class RecipeListCell: UITableViewCell {
    static let reuseID = "RecipeListCell"

    private let thumbnailView = UIImageView()
    private let nameLabel = UILabel()
    private let categoryLabel = UILabel()
    private let cookTimeLabel = UILabel()
    private let favoriteIcon = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 8
        thumbnailView.backgroundColor = UIColor(hex: "#FDEAD2")
        thumbnailView.image = UIImage(systemName: "photo.on.rectangle")
        thumbnailView.tintColor = UIColor(hex: "#E8730E")

        nameLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        nameLabel.numberOfLines = 2

        categoryLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        categoryLabel.textColor = .secondaryLabel

        cookTimeLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        cookTimeLabel.textColor = .secondaryLabel

        favoriteIcon.image = UIImage(systemName: "heart.fill")
        favoriteIcon.tintColor = .systemRed
        favoriteIcon.isHidden = true

        [thumbnailView, nameLabel, categoryLabel, cookTimeLabel, favoriteIcon].forEach {
            contentView.addSubview($0)
        }

        thumbnailView.snp.makeConstraints {
            $0.left.equalToSuperview().inset(16)
            $0.centerY.equalToSuperview()
            $0.size.equalTo(CGSize(width: 60, height: 60))
        }
        nameLabel.snp.makeConstraints {
            $0.top.equalTo(thumbnailView)
            $0.left.equalTo(thumbnailView.snp.right).offset(12)
            $0.right.equalToSuperview().inset(40)
        }
        categoryLabel.snp.makeConstraints {
            $0.top.equalTo(nameLabel.snp.bottom).offset(4)
            $0.left.equalTo(nameLabel)
        }
        cookTimeLabel.snp.makeConstraints {
            $0.top.equalTo(categoryLabel.snp.bottom).offset(2)
            $0.left.equalTo(nameLabel)
        }
        favoriteIcon.snp.makeConstraints {
            $0.right.equalToSuperview().inset(16)
            $0.centerY.equalToSuperview()
            $0.size.equalTo(CGSize(width: 20, height: 18))
        }
    }

    func configure(with recipe: Recipe) {
        nameLabel.text = recipe.name
        categoryLabel.text = recipe.category?.name ?? "Chưa phân loại"
        cookTimeLabel.text = recipe.cookTime > 0 ? "⏱ \(recipe.cookTime) phút" : ""
        favoriteIcon.isHidden = !recipe.isFavorite
        if let data = recipe.imageData {
            thumbnailView.image = UIImage(data: data)
        }
    }
}
```

---

## Todo List
- [ ] Tạo `RecipeListViewModel.swift` + `RecipeFilter` enum
- [ ] Tạo `RecipeListViewController.swift` với FRC setup
- [ ] Tạo `RecipeListCell.swift`
- [ ] Tạo placeholder `RecipeDetailViewController.swift` (chỉ init, implement ở Phase 5)
- [ ] Tạo placeholder `CreateEditRecipeViewController.swift` (implement ở Phase 4)
- [ ] Thêm seed data (vài recipes) để test UI sections

## Success Criteria
- App launch hiển thị danh sách recipes grouped theo category
- Thêm recipe mới → tự xuất hiện trong list (không cần reload)
- Search lọc realtime khi gõ vào search bar
- Sections xuất hiện/ẩn đi khi category có/không có recipes

## Tiếp Theo
→ [Phase 4: Create & Edit Recipe](phase-04-create-edit-recipe.md)
