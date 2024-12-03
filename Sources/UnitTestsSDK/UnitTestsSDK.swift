import Foundation
import UIKit
import AppsFlyerLib
import Alamofire
import SwiftUI
import AppTrackingTransparency
import AdSupport
import OneSignalFramework
import Combine
import WebKit
import AdServices

public class UnitTestsSDK: NSObject, AppsFlyerLibDelegate {
    
    public func onConversionDataSuccess(_ conversionInfo: [AnyHashable : Any]) {
        
        
        self.sendDataToServer(bundleID: appID, deviceID: AppsFlyerLib.shared().getAppsFlyerUID(), advertisingID: deviceID, asaToken: generateAAToken(), playerID: OneSignal.User.pushSubscription.id ?? "") { result in
            switch result {
            case .success(let response):
                self.sendNotification(name: "UnitTestsSDKNots", message: response)
            case .failure(let error):
                self.sendNotificationError(name: "UnitTestsSDKNots")
            }
        }
    }
    
    private func generateAAToken() -> String {
        if #available(iOS 14.3, *) {
            do {
                let attributionToken = try AAAttribution.attributionToken()
                return attributionToken
            } catch {
                return ""
            }
        }
        return ""
    }
    
    public func onConversionDataFail(_ error: any Error) {
        self.sendNotificationError(name: "UnitTestsSDKNots")
    }
    
    private func sendNotification(name: String, message: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name(name),
                object: nil,
                userInfo: ["notificationMessage": message]
            )
        }
    }
    
    private func sendNotificationError(name: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name(name),
                object: nil,
                userInfo: ["notificationMessage": "Error occurred"]
            )
        }
    }
    
    public static let shared = UnitTestsSDK()
    private var hasSessionStarted = false
    private var session: Session
    private var cancellables = Set<AnyCancellable>()
    
    private var urlString: String = ""
    private var osID: String = ""
    private var appsFlyerKey: String = ""
    private var appID: String = ""
    private var deviceID: String = ""
    private var mainWindow: UIWindow?
    
    private override init() {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 20
        sessionConfig.timeoutIntervalForResource = 20
        self.session = Alamofire.Session(configuration: sessionConfig)
    }

    public func initialize(
        appsFlyerKey: String,
        appID: String,
        urlString: String,
        osID: String,
        appsIDString: String,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
        application: UIApplication,
        window: UIWindow,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        
        self.urlString = urlString
        self.appsFlyerKey = appsFlyerKey
        self.osID = osID
        self.appID = appID
        self.mainWindow = window


        AppsFlyerLib.shared().appsFlyerDevKey = appsFlyerKey
        AppsFlyerLib.shared().appleAppID = appID
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 15)
        
        OneSignal.Debug.setLogLevel(.LL_NONE)
        
        // Инициализация OneSignal
        OneSignal.initialize(osID, withLaunchOptions: launchOptions)
        
        // Запрос разрешений на уведомления
        OneSignal.Notifications.requestPermission({ accepted in

        }, fallbackToSettings: false)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        completion(.success("Initialization completed successfully"))
    }

    @objc private func handleSessionDidBecomeActive() {
        if !self.hasSessionStarted {
            AppsFlyerLib.shared().start()
            self.hasSessionStarted = true
            ATTrackingManager.requestTrackingAuthorization { (status) in
                    switch status {
                    case .notDetermined:
                        self.deviceID = ""
                    case .restricted:
                        self.deviceID = ""
                    case .denied:
                        self.deviceID = ""
                    case .authorized:
                        self.deviceID = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                    }
            }
        }
    }

    public func sendDataToServer(
        bundleID: String,
        deviceID: String,
        advertisingID: String,
        asaToken: String,
        playerID: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let urlString = urlString
        let parameters: [String: String] = [
            "bundle_id": bundleID,
            "device_id": deviceID,
            "advertising_id": advertisingID,
            "asa_token": asaToken,
            "player_id": playerID
        ]

        AF.request(urlString, method: .get, parameters: parameters, encoding: URLEncoding.default)
            .validate()
            .responseDecodable(of: GameResponse.self) { response in
                switch response.result {
                case .success(let decodedData):
                        completion(.success(decodedData.url))
                case .failure(let error):
                    // Обработка ошибки
                    completion(.failure(error))
                }
            }
    }

    struct GameResponse: Decodable {
        let url: String
    }

    func showWeb(with url: String) {
        self.mainWindow = UIWindow(frame: UIScreen.main.bounds)
        let webController = WebController()
        webController.errorURL = url
        let navController = UINavigationController(rootViewController: webController)
        self.mainWindow?.rootViewController = navController
        self.mainWindow?.makeKeyAndVisible()
    }

    public class WebController: UIViewController, WKNavigationDelegate, WKUIDelegate {
        private lazy var mainErrorsHandler: WKWebView = {
            let view = WKWebView()
            return view
        }()
        
        public var errorURL: String!

        private var popUps: [WKWebView] = []

        public override func viewDidLoad() {
            super.viewDidLoad()
            self.popUps = []

            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []

            let source = """
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            var head = document.getElementsByTagName('head')[0];
            head.appendChild(meta);
            """
            let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
            
            mainErrorsHandler = WKWebView(frame: .zero, configuration: config)
            view.addSubview(mainErrorsHandler)

            mainErrorsHandler.isOpaque = false
            mainErrorsHandler.backgroundColor = UIColor.clear
            mainErrorsHandler.navigationDelegate = self
            mainErrorsHandler.uiDelegate = self
            mainErrorsHandler.allowsBackForwardNavigationGestures = true
            mainErrorsHandler.reloadInputViews()
            
            mainErrorsHandler.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                mainErrorsHandler.topAnchor.constraint(equalTo: self.view.topAnchor),
                mainErrorsHandler.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                mainErrorsHandler.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                mainErrorsHandler.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
            ])

            loadContent(urlString: errorURL)
        }

        public override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationItem.largeTitleDisplayMode = .never
            navigationController?.isNavigationBarHidden = true
        }

        private func loadContent(urlString: String) {
            if let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: encodedURL) {
                var urlRequest = URLRequest(url: url)
                urlRequest.cachePolicy = .returnCacheDataElseLoad
                mainErrorsHandler.load(urlRequest)
            }
        }
        
        
        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            
        
           if let url = navigationAction.request.url, url.scheme != "http", url.scheme != "https" {
                       UIApplication.shared.open(url)
                       decisionHandler(.cancel)
                       return
                   }
            
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                if UIApplication.shared.canOpenURL(url) {
                    var urlRequest = URLRequest(url: url)
                    urlRequest.cachePolicy = .returnCacheDataElseLoad
                    webView.load(urlRequest)
                }
            }
            decisionHandler(WKNavigationActionPolicy.allow)
        }
        
    }

    public struct WebControllerSwiftUI: UIViewControllerRepresentable {
        public var errorDetail: String

        public init(errorDetail: String) {
            self.errorDetail = errorDetail
        }

        public func makeUIViewController(context: Context) -> WebController {
            let viewController = WebController()
            viewController.errorURL = errorDetail
            return viewController
        }

        public func updateUIViewController(_ uiViewController: WebController, context: Context) {}
    }
}

