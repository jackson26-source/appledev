import Foundation
import Capacitor

/**
 * SharedTextPlugin
 *
 * Reads whatever text the Share Extension (see ios-share-extension/) stashed
 * in the shared App Group container, and clears it once read so the same
 * shared item doesn't get reloaded on the next app launch.
 *
 * Install this file in your Xcode project under App/, same as
 * NativeTtsPlugin.swift.
 */
@objc(SharedText)
public class SharedTextPlugin: CAPPlugin, CAPBridgedPlugin {

    public let identifier = "SharedTextPlugin"
    public let jsName = "SharedText"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "consume", returnType: CAPPluginReturnPromise)
    ]

    // Must match the App Group ID used in ShareViewController.swift, and
    // must be added to BOTH the main app target and the share extension
    // target under Signing & Capabilities > App Groups in Xcode.
    let appGroupId = "group.com.citolex.app"

    @objc func consume(_ call: CAPPluginCall) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            call.resolve(["text": NSNull()])
            return
        }
        let text = defaults.string(forKey: "sharedText")
        defaults.removeObject(forKey: "sharedText")
        defaults.removeObject(forKey: "sharedAt")
        call.resolve(["text": text ?? NSNull()])
    }
}
