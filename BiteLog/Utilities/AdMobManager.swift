import SwiftUI
import AppTrackingTransparency
import GoogleMobileAds

class AdMobManager: NSObject {
    static let shared = AdMobManager()
    
    private override init() {
        super.init()
    }
    
    func initialize() {
        // Info.plistのGADApplicationIdentifierを確認
        if let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String {
            print("AdMob初期化開始 - Info.plistから読み込み: \(appID)")
        } else {
            print("⚠️ Info.plistにGADApplicationIdentifierが見つかりません")
        }
        
        MobileAds.shared.start { status in
            print("AdMob SDK初期化完了")
            
            // アダプター毎の初期化状態を確認
            let adapterStatuses = status.adapterStatusesByClassName
            for (adapterClass, adapterStatus) in adapterStatuses {
                print("アダプター \(adapterClass): 状態=\(adapterStatus.state.rawValue), 説明=\(adapterStatus.description)")
            }
        }
    }
    
    func requestTrackingAuthorization(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
        } else {
            completion(true)
        }
    }
}

struct AdMobConfig {
    #if DEBUG
    // デバッグ用のテストID（Google提供のサンプルID）
    static let applicationID = "ca-app-pub-3940256099942544~1458002511"
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"
    static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    static let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    #else
    // 本番用のAdMob ID
    static let applicationID = "ca-app-pub-3786393697724703~6766055998"
    static let bannerAdUnitID = "ca-app-pub-3786393697724703/9739510170"
    static let interstitialAdUnitID = "ca-app-pub-3786393697724703~6766055998"
    static let rewardedAdUnitID = "ca-app-pub-3786393697724703~6766055998"
    #endif
}