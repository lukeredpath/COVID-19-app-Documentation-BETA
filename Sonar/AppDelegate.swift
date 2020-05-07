//
//  AppDelegate.swift
//  Sonar
//
//  Created by NHSX on 09/03/2020.
//  Copyright © 2020 NHSX. All rights reserved.
//

import UIKit
import CoreData
import Firebase
import FirebaseInstanceID
import Logging
import AdSupport

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?

    let notificationCenter = NotificationCenter.default
    let userNotificationCenter = UNUserNotificationCenter.current()
    let authorizationManager = AuthorizationManager()
    
    let trustValidator = PublicKeyValidator(trustedKeyHashes: ["hETpgVvaLC0bvcGG3t0cuqiHvr4XyP2MTwCiqhgRWwU="])
    
    let storageChecker = StorageChecker(service: "uk.nhs.nhsx.sonars.storage_marker")
    
    lazy var monitor: AppMonitoring = AppCenterMonitor.shared
    
    lazy var urlSession: Session = URLSession(trustValidator: trustValidator)

    lazy var dispatcher: RemoteNotificationDispatching = RemoteNotificationDispatcher(
        notificationCenter: notificationCenter,
        userNotificationCenter: userNotificationCenter)

    lazy var remoteNotificationManager: RemoteNotificationManager = ConcreteRemoteNotificationManager(
        firebase: FirebaseApp.self,
        messagingFactory: { Messaging.messaging() },
        userNotificationCenter: userNotificationCenter,
        notificationAcknowledger: notificationAcknowledger,
        dispatcher: dispatcher)
    
    lazy var registrationService: RegistrationService = ConcreteRegistrationService(
        session: urlSession,
        persistence: persistence,
        reminderScheduler: ConcreteRegistrationReminderScheduler(userNotificationCenter: userNotificationCenter),
        remoteNotificationDispatcher: dispatcher,
        notificationCenter: notificationCenter,
        monitor: monitor,
        timeoutQueue: DispatchQueue.main)

    lazy var persistence: Persisting = Persistence(
        secureRegistrationStorage: SecureRegistrationStorage(),
        broadcastKeyStorage: SecureBroadcastRotationKeyStorage(),
        monitor: monitor,
        storageChecker: storageChecker
    )

    lazy var bluetoothNursery: BluetoothNursery = ConcreteBluetoothNursery(persistence: persistence, userNotificationCenter: userNotificationCenter, notificationCenter: notificationCenter, monitor: monitor)
    
    lazy var onboardingCoordinator: OnboardingCoordinating = OnboardingCoordinator(
        persistence: persistence,
        authorizationManager: authorizationManager,
        bluetoothNursery: bluetoothNursery
    )
    
    lazy var contactEventsUploader: ContactEventsUploading = ContactEventsUploader(
        persisting: persistence,
        contactEventRepository: bluetoothNursery.contactEventRepository,
        trustValidator: trustValidator,
        makeSession: makeBackgroundSession
    )

    lazy var makeBackgroundSession: (String, URLSessionDelegate) -> Session = { id, delegate in
        let config = URLSessionConfiguration.background(withIdentifier: id)
        config.secure()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    lazy var linkingIdManager: LinkingIdManaging = LinkingIdManager(
        notificationCenter: notificationCenter,
        persisting: persistence,
        session: urlSession
    )

    lazy var statusProvider: StatusProviding = StatusProvider(
        persisting: persistence
    )

    lazy var statusNotificationHandler: StatusNotificationHandler = StatusNotificationHandler(
        persisting: persistence,
        userNotificationCenter: userNotificationCenter,
        notificationCenter: notificationCenter
    )

    lazy var notificationAcknowledger: NotificationAcknowledger = NotificationAcknowledger(
        persisting: persistence,
        session: urlSession
    )

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        if let window = UITestResponder.makeWindowForTesting() {
            self.window = window
            return true
        }
        #endif

        LoggingManager.bootstrap()
        logger.info("Launched", metadata: Logger.Metadata(launchOptions: launchOptions))

        application.registerForRemoteNotifications()

        // DISABLE FIREBASE!
        //remoteNotificationManager.configure()
        
        dispatcher.registerHandler(forType: .status) { userInfo, completion in
            self.statusNotificationHandler.handle(userInfo: userInfo, completion: completion)
        }

        Appearance.setup()
        
        writeBuildInfo()

        let rootVC = RootViewController()
        rootVC.inject(
            persistence: persistence,
            authorizationManager: authorizationManager,
            remoteNotificationManager: remoteNotificationManager,
            notificationCenter: notificationCenter,
            registrationService: registrationService,
            bluetoothNursery: bluetoothNursery,
            onboardingCoordinator: onboardingCoordinator,
            monitor: monitor,
            session: urlSession,
            contactEventsUploader: contactEventsUploader,
            linkingIdManager: linkingIdManager,
            statusProvider: statusProvider,
            uiQueue: DispatchQueue.main
        )
        
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = rootVC
        window?.makeKeyAndVisible()
        
        // Create a fake SecKey for Registration
        let keyBase64 = "MIIEpAIBAAKCAQEA5B7lqLrwVCFNUiCmwMr5Q48iuArOolxb7DAuclGnoZVX0SaJ8mrvCOtd6qY/VeBw227txWEPH7840qX/yGxxqTngdNCuDATqYrrbxFOGV30GZmg6NpZYKShTlsftkhiCsoXW0A7m5MCZUkH2/sNBC8oRHCNDXRlsU5bq/yPaAMt6xlBsUgLt/++INcuw+rx1Rm7LJv0FeukQmlekUOL/DMJXcLXCa05StTbvHPiAHOLej07pThCZoX3XHFpOTQ6379EsjvSZHtNhr67qrtRb8or2rX7wt5NWzXHbhUDlyzEcIBB/7G8ygqWhyZTEIMFiRMWSa3KGYZE3nZe5weC7SQIDAQABAoIBAQCjjxehA+++kmYK5YhKIP3Zl64QAQeo18m8rcsPgkZLj3V4a0Zq/orGfWNIE8zDePnSC1YFuBKM86D9P7IGdOKFsA6kEt9HlNqs0UczG6Pt5KGLGV3rt54cXGKacFyA7HwBHf8oDBc2mnUTymIaxcpEdqwP3aS2Ar1trX5uUrlC6UcZyspBZVYvMlU+uAKL1ZtFxjsv0EzuQQW1HX7b2WPUAoxp/yBC/EBRM9K8WbG9i7NB4FTFHAdTMt/EZLGUESizFgrai6lp3s96Apz5GvncRUI+UVP/7zbUaFYdRMW5lrcR8+PL9NACkL2rnQuLoyLKWZWPPlD3WEE9EzY4bH6FAoGBAPu8hL8goEbWMFDZuox04Ouy6EpXR8BDTq8ut6hmad6wpFgZD15Xu7pYEbbsPntdYODKDDAIJCBsiBgf2emL50BpiQkzMPhxyMsN5Pzry9Ys+AzPkJcQ7g+/Wbto9lCC+JmgxtGQ7JIibo1QH7BTsuK9+k72HnZne6oIfaYKbBZfAoGBAOf7/D2Q7NiNcEgxpZRn06+mnkHMb8PfCKfJf/BFf5WKXSkDBZ3XhWSPnZyQnE3gW3lzJjzUwHS+YDk8A0Xl2piAHa/d5O/8eoijB8wa6UGVDBIXqUnfM3Udfry78rM71FOpbzV3H48G7u4CUJMGwOpEqF0TfgtQr4uf8OurdH9XAoGAbdNhVsE1K7Jmgd97s6uKNUpobYaGlyrGOUd4eM+1gKIwEP9d5RsBm9qwX83RtKCYk3mSt6HVoQ+4kE3VFD8lNMTWNF1REBMUNwJo1K9KzrXvwicMPdv1AInK7ChuzdFWBDBQjT1c+KRs9tnt+U+Ky8F2Ytydjaq4GQZ7SuVhIqECgYBMsS+IovrJ9KhkFZWp5FFFRo4XLqDcXkWcQq87HZ66L03xGwCmV/PPdPMkKWKjFELpebnwbl1Zuv5QrZhfaUfFFsW5uF/RPuS7ezo+rb7jYYTmDlB3DYUTeLbHalMoEeV16xPK1yDlxeMDaFx+3sK0MBKBAsqurvP58txQ7RPMbQKBgQCzRcURopG0DF4VF4+xQJS8FpTcnQsQnO/2MJR35npA2iUb+ffs+0lgEdeWs4W46kvaF1iVEPbr6She+aKROzE9Bs25ZCgGLv97oUxDQo0IPvURX7ucN+xOUU1hw9oQDVdGKl1JZh93fn+bjtMTe+26asGLmM0r9YQX1P8qaw3KOg=="
        let keyData = Data(base64Encoded: keyBase64)!
        let key = SecKeyCreateWithData(keyData as NSData, [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ] as NSDictionary, nil)!
        
        // Create a fake registration, you'll need to ensure ad support is enabled in Settings or advertisingIdentifier will be zeroed
        let registration = Registration(id: ASIdentifierManager.shared().advertisingIdentifier, secretKey: "fake-secret".data(using: .utf8)!, broadcastRotationKey: key)
        
        // Check registration as well as bluetoothPermissionRequested, because the user may have registered
        // on an old version of the app that didn't record bluetoothPermissionRequested.
        
        // Skip persisted registration check, use fake registration
        if persistence.bluetoothPermissionRequested { //} || persistence.registration != nil {
            bluetoothNursery.startBluetooth(registration: registration)
        }

        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        logger.info("Received notification", metadata: Logger.Metadata(dictionary: userInfo))
        
        remoteNotificationManager.handleNotification(userInfo: userInfo, completionHandler: { result in
             completionHandler(result)
        })
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        logger.info("Terminating")

        scheduleLocalNotification()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        logger.info("Will Resign Active")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        logger.info("Did Become Active")

        try? contactEventsUploader.ensureUploading()
        linkingIdManager.fetchLinkingId { _ in }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        logger.info("Did Enter Background")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.info("Will Enter Foreground")
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622941-application
        // https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background

        // This is called even if the app is in the background or suspended and a background
        // URLSession task finishes. We're supposed to reconstruct the background session and
        // attach a delegate to it when this gets called, but we already do that as part of
        // the app launch, so can skip that here. However, we do need to attach the completion
        // handler to the delegate so that we can notify the system when we're done processing
        // the task events.

        contactEventsUploader.sessionDelegate.completionHandler = completionHandler
    }

    // MARK: - Private
    
    private func scheduleLocalNotification() {
        let scheduler = HumbleLocalNotificationScheduler(userNotificationCenter: userNotificationCenter)

        scheduler.scheduleLocalNotification(
            title: nil,
            body: "To keep yourself secure, please relaunch the app.",
            interval: 10,
            identifier: "willTerminate.relaunch.please",
            repeats: false
        )
    }
    
    private func writeBuildInfo() {
        persistence.lastInstalledBuildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        persistence.lastInstalledVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

// MARK: - Logging
private let logger = Logger(label: "Application")
