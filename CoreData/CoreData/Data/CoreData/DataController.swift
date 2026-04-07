import CoreData

/// Singleton quản lý toàn bộ Core Data stack.
///
/// ## Giải thích:
/// - `NSPersistentContainer` là "bộ não" khởi tạo Core Data.
///   Nó tìm file `Cookbook.xcdatamodeld` trong bundle, tạo SQLite file,
///   và cung cấp `NSManagedObjectContext` để ta làm việc.
///
/// - `viewContext` chạy trên **main thread** — dùng cho đọc data và cập nhật UI.
///
/// - `automaticallyMergesChangesFromParent = true`: khi background context save,
///   changes tự merge về viewContext → FRC tự cập nhật UI.
final class DataController {

    // MARK: - Singleton

    static let shared = DataController()

    // MARK: - Core Data Stack

    let container: NSPersistentContainer

    /// Context chạy trên main thread, dùng cho UI và read operations.
    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Init

    /// - Parameter inMemory: `true` để dùng in-memory store (cho unit tests).
    init(inMemory: Bool = false) {
        // "Cookbook" = tên file Cookbook.xcdatamodeld
        container = NSPersistentContainer(name: "Cookbook")

        if inMemory {
            // /dev/null = không ghi xuống disk — dùng cho tests
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // Tự động merge changes từ background context về viewContext
        container.viewContext.automaticallyMergesChangesFromParent = true

        // Khi có conflict: version trong memory thắng (safe default)
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        container.loadPersistentStores { storeDescription, error in
            if let error {
                // fatalError() chỉ dùng trong development.
                // Production app cần handle gracefully (alert user, etc.)
                fatalError("❌ Core Data load failed: \(error.localizedDescription)")
            }
            print("✅ Core Data loaded: \(storeDescription.url?.lastPathComponent ?? "unknown")")
        }
    }

    // MARK: - Save

    /// Lưu viewContext xuống SQLite nếu có thay đổi.
    func saveContext() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            print("❌ Core Data save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Background Context

    /// Tạo background context mới cho heavy operations (import, batch processing).
    /// Chạy trên background thread — KHÔNG dùng context này trên main thread.
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
}
