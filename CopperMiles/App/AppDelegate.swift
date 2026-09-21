import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

extension Notification.Name {
  /// Posted when the traveller taps a departure reminder.
  static let copperMilesOpenTrip = Notification.Name("copperMilesOpenTrip")
}

final class Splice {

    private var wide: [AnyHashable: Any] = [:]
    private var deep: [AnyHashable: Any] = [:]
    private var pending: DispatchWorkItem?
    private let ready: ([AnyHashable: Any]) -> Void

    init(ready: @escaping ([AnyHashable: Any]) -> Void) {
        self.ready = ready
    }

    func broad(_ payload: [AnyHashable: Any]) {
        wide = payload
        pending?.cancel()
        pending = nil
        if deep.isEmpty == false {
            weave()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.weave() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    func thin(_ payload: [AnyHashable: Any]) {
        deep = payload
        pending?.cancel()
        pending = nil
        if wide.isEmpty == false { weave() }
    }

    private func weave() {
        pending?.cancel()
        pending = nil
        var out = wide
        for (key, value) in deep {
            let tag = "\(key)".starts(with: "deep") ? "\(key)" : "deep_\(key)"
            if out[tag] == nil { out[tag] = value }
        }
        ready(out)
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {

    private lazy var splice = Splice { payload in
        NotificationCenter.default.post(name: .sighted, object: nil, userInfo: ["conversionData": payload])
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()

        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = Atlas.relayKey
        sdk.appleAppID = Atlas.appCode
        sdk.delegate = self
        sdk.deepLinkDelegate = self
        sdk.isDebug = false

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            sift(cold)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(afoot), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    @objc private func afoot() {
        guard #available(iOS 14, *) else { return AppsFlyerLib.shared().start() }
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                AppsFlyerLib.shared().start()
                UserDefaults.standard.set(status.rawValue, forKey: Marker.att)
            }
        }
    }

    private func sift(_ payload: [AnyHashable: Any]) {
        var found: String?
        if let direct = payload["url"] as? String, direct.isEmpty == false {
            found = direct
        } else if let data = payload["data"] as? [AnyHashable: Any], let url = data["url"] as? String, url.isEmpty == false {
            found = url
        } else if let aps = payload["aps"] as? [AnyHashable: Any],
                  let data = aps["data"] as? [AnyHashable: Any],
                  let url = data["url"] as? String, url.isEmpty == false {
            found = url
        } else if let custom = payload["custom"] as? [AnyHashable: Any], let url = custom["url"] as? String, url.isEmpty == false {
            found = url
        }
        guard let link = found else { return }

        UserDefaults.standard.set(link, forKey: Marker.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .flared, object: nil, userInfo: ["temp_url": link])
        }
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: Marker.fcm)
            UserDefaults.standard.set(token, forKey: Marker.push)
            UserDefaults(suiteName: Atlas.suite)?.set(token, forKey: Marker.sharedFcm)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        sift(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        sift(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        sift(userInfo)
        completionHandler(.newData)
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        splice.broad(conversionInfo)
    }

    func onConversionDataFail(_ error: Error) {
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        guard UserDefaults.standard.bool(forKey: Marker.primed) == false else { return }
        NotificationCenter.default.post(name: .traced, object: nil, userInfo: ["deeplinksData": deepLink.clickEvent])
        splice.thin(deepLink.clickEvent)
    }
}
