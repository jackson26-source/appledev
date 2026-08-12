import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

/**
 * ShareViewController
 *
 * This is the code behind the "Read in Citolex" option that appears in the
 * iOS Share Sheet from Safari, Notes, Mail, etc. It grabs whatever text or
 * URL was shared, hands it off to the main Citolex app via a shared
 * App Group container, then asks iOS to open the main app.
 *
 * This file belongs to a SEPARATE Xcode target (a "Share Extension"), not
 * the main App target. See SETUP.md for how to create that target in
 * Xcode — it can't be scripted from the command line, it has to be added
 * through Xcode's "+ Capability" / "New Target" UI.
 */
class ShareViewController: SLComposeServiceViewController {

    // Must match the App Group ID you create in SETUP.md, and must match
    // exactly on both the main app target and this extension target.
    let appGroupId = "group.com.citolex.app"

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            complete()
            return
        }

        var foundText: String? = self.contentText

        let group = DispatchGroup()

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                        if let text = data as? String, foundText == nil || foundText!.isEmpty {
                            foundText = text
                        }
                        group.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
                        if let url = data as? URL {
                            foundText = (foundText?.isEmpty == false ? foundText! + "\n" : "") + url.absoluteString
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            if let text = foundText, let defaults = UserDefaults(suiteName: self.appGroupId) {
                defaults.set(text, forKey: "sharedText")
                defaults.set(Date(), forKey: "sharedAt")
            }
            self.openMainApp()
        }
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    /// Share extensions can't call UIApplication.shared.open directly, so we
    /// walk the responder chain to find something that can — this is the
    /// standard workaround Apple's own sample code uses.
    private func openMainApp() {
        guard let url = URL(string: "citolex://shared") else {
            complete()
            return
        }
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.perform(#selector(UIApplication.open(_:options:completionHandler:)), with: url, with: nil)
                break
            }
            responder = responder?.next
        }
        complete()
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
