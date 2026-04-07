import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Setup root ViewController bằng code — không dùng Storyboard
        window = UIWindow(windowScene: windowScene)

        let rootVC = RecipeListViewController()
        let navController = UINavigationController(rootViewController: rootVC)

        // Large title style cho root screens
        navController.navigationBar.prefersLargeTitles = true

        window?.rootViewController = navController
        window?.makeKeyAndVisible()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Lưu Core Data khi app vào background
        DataController.shared.saveContext()
    }
}
