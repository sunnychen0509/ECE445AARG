import Foundation

class GlobalFlowManager: ObservableObject {
    static let shared = GlobalFlowManager()
    
    @Published var isBusy = false
    
    private init() {}
}
