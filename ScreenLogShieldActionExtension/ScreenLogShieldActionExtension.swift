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
            let logged = ExtensionBlockingSupport.logExtraTimeRequest(seconds: 15 * 60, matching: token)
            completionHandler(logged ? .close : .defer)
        case .secondaryButtonPressed:
            completionHandler(.defer)
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
            let logged = ExtensionBlockingSupport.logExtraTimeRequest(seconds: 15 * 60, matching: token)
            completionHandler(logged ? .close : .defer)
        case .secondaryButtonPressed:
            completionHandler(.defer)
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
            let logged = ExtensionBlockingSupport.logExtraTimeRequest(seconds: 15 * 60, matching: token)
            completionHandler(logged ? .close : .defer)
        case .secondaryButtonPressed:
            completionHandler(.defer)
        @unknown default:
            completionHandler(.none)
        }
    }
}
