import UIKit

/// Màn hình chính — danh sách công thức nấu ăn.
///
/// Phase 1: Placeholder để app có thể build và chạy.
/// Phase 3: Sẽ implement đầy đủ với NSFetchedResultsController.
final class RecipeListViewController: UIViewController {

    // MARK: - UI

    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "Chưa có công thức nào.\nNhấn + để thêm mới."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        return label
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        // Test: DataController.shared đã được khởi tạo ở AppDelegate
        // Mở Xcode Console — nếu thấy "✅ Core Data loaded" thì Phase 1 thành công!
        print("✅ RecipeListViewController loaded")
        print("📦 ViewContext: \(DataController.shared.viewContext)")
    }

    // MARK: - Setup

    private func setupUI() {
        title = "Cookbook"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .always

        // Nút thêm recipe (sẽ implement ở Phase 4)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addTapped)
        )

        view.addSubview(emptyStateLabel)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    // MARK: - Actions

    @objc private func addTapped() {
        // TODO: Phase 4 — implement CreateEditRecipeViewController
        print("➕ Add tapped — sẽ implement ở Phase 4")
    }
}
