import ManagedSettings

final class ScreenLogShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, token: application, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, token: category, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, token: webDomain, completionHandler: completionHandler)
    }

    private func handle(
        action: ShieldAction,
        token: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            let queued = ExtensionBlockingSupport.queueFriendRequestDraft(matching: token)
            completionHandler(queued ? .defer : .none)
        @unknown default:
            completionHandler(.none)
        }
    }

    private func handle(
        action: ShieldAction,
        token: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            let queued = ExtensionBlockingSupport.queueFriendRequestDraft(matching: token)
            completionHandler(queued ? .defer : .none)
        @unknown default:
            completionHandler(.none)
        }
    }

    private func handle(
        action: ShieldAction,
        token: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            let queued = ExtensionBlockingSupport.queueFriendRequestDraft(matching: token)
            completionHandler(queued ? .defer : .none)
        @unknown default:
            completionHandler(.none)
        }
    }
}
