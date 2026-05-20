import Foundation

struct AppGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var appNames: [String]
    var placement: ScreenPlacement

    init(id: UUID = UUID(), name: String, appNames: [String] = [], placement: ScreenPlacement = .default) {
        self.id = id
        self.name = name
        self.appNames = appNames
        self.placement = placement
    }
}
