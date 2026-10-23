import Foundation

enum DashboardURL {
    static func blacksmithWorkflows(owner: String) -> URL? {
        guard let owner = pathSegment(owner) else { return nil }
        return URL(string: "https://app.blacksmith.sh/\(owner)/runs/workflows")
    }

    static func gitHubActions(owner: String, repository: String) -> URL? {
        guard let owner = pathSegment(owner) else { return nil }
        let trimmedRepository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRepository.isEmpty else {
            return URL(string: "https://github.com/orgs/\(owner)/actions")
        }
        guard let repository = pathSegment(trimmedRepository) else { return nil }
        return URL(string: "https://github.com/\(owner)/\(repository)/actions")
    }

    private static func pathSegment(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}
