import SwiftUI
import AppTrackingTransparency
@preconcurrency import GoogleMobileAds

class AdMobManager: NSObject {
    static let shared = AdMobManager()
    
    private override init() {
        super.init()
    }
    
    func initialize() {
        // Info.plistから読み取れない場合のフォールバック設定
        if Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") == nil {
            print("Warning: GADApplicationIdentifier not found in Info.plist")
            print("AdMob will attempt to initialize with test configuration")
        }
        
        MobileAds.shared.start { initializationStatus in
            print("AdMob SDK初期化完了")
            
            // アダプター毎の初期化状態を確認
            for adapter in initializationStatus.adapterStatusesByClassName {
                let adapterClass = adapter.key
                let status = adapter.value
                print("アダプター \(adapterClass): 状態=\(status.state.rawValue), 説明=\(status.description)")
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
    // TODO: 注意！これはサンプルIDで実際のアプリでは動作しません
    // AdMobアカウント作成後、実際のアプリIDに更新が必要
    static let applicationID = "ca-app-pub-3940256099942544~1458002511"
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"
    static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    #else
    // TODO: AdMobアカウント作成後、以下を実際のIDに更新してください
    // 1. https://admob.google.com/ でアカウント作成
    // 2. BiteLogアプリを登録（Bundle ID: com.watahiki.BiteLog）
    // 3. 取得したアプリIDと広告ユニットIDに更新
    static let applicationID = "YOUR_PRODUCTION_APPLICATION_ID"
    static let bannerAdUnitID = "YOUR_PRODUCTION_BANNER_AD_UNIT_ID"
    static let interstitialAdUnitID = "YOUR_PRODUCTION_INTERSTITIAL_AD_UNIT_ID"
    #endif
}