import SwiftUI
import GoogleMobileAds

class RewardedAdManager: NSObject, ObservableObject, FullScreenContentDelegate {
    static let shared = RewardedAdManager()
    
    @Published var isAdReady = false
    private var rewardedAd: RewardedAd?
    private var loadTime: Date?
    private var onAdDismissed: ((Bool) -> Void)?  // Bool: 報酬を獲得したか
    private var didEarnReward = false
    
    // 広告の有効期限（4時間）
    private let adExpirationTime: TimeInterval = 4 * 60 * 60
    
    // 広告表示の頻度制限（最後に表示してから30分以上経過している必要がある）
    private let minTimeBetweenAds: TimeInterval = 30 * 60
    
    // UserDefaultsのキー
    private let lastAdShowTimeKey = "rewarded_ad_last_show_time"
    
    // 最後に広告を表示した時刻をUserDefaultsから取得
    private var lastAdShowTime: Date? {
        get {
            if let timestamp = UserDefaults.standard.object(forKey: lastAdShowTimeKey) as? Double {
                return Date(timeIntervalSince1970: timestamp)
            }
            return nil
        }
        set {
            if let newValue = newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: lastAdShowTimeKey)
                print("📅 最後のリワード広告表示時刻を保存: \(newValue)")
            } else {
                UserDefaults.standard.removeObject(forKey: lastAdShowTimeKey)
            }
        }
    }
    
    private override init() {
        super.init()
        loadAd()
        
        // 初期化時に最後の広告表示時刻をログ出力
        if let lastTime = lastAdShowTime {
            let timeSince = Date().timeIntervalSince(lastTime)
            print("📊 最後のリワード広告表示からの経過時間: \(Int(timeSince / 60))分")
        } else {
            print("📊 リワード広告表示履歴なし")
        }
    }
    
    func loadAd() {
        let request = Request()
        
        RewardedAd.load(
            with: AdMobConfig.rewardedAdUnitID,
            request: request
        ) { [weak self] ad, error in
            guard let self = self else { return }
            
            if let error = error {
                print("リワード広告の読み込みに失敗: \(error.localizedDescription)")
                self.isAdReady = false
                return
            }
            
            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
            self.loadTime = Date()
            self.isAdReady = true
            print("リワード広告の読み込みに成功")
        }
    }
    
    // 広告が表示可能かチェック
    func canShowAd() -> Bool {
        print("🔍 リワード広告表示可否チェック開始")
        
        // 広告が準備できているかチェック
        guard isAdReady, rewardedAd != nil else {
            print("❌ リワード広告が準備できていません (isAdReady: \(isAdReady), rewardedAd: \(rewardedAd != nil))")
            return false
        }
        print("✅ リワード広告は準備完了")
        
        // 広告の有効期限をチェック
        if let loadTime = loadTime {
            let adAge = Date().timeIntervalSince(loadTime)
            print("📊 リワード広告のロード時刻: \(loadTime), 経過時間: \(Int(adAge / 60))分")
            if adAge > adExpirationTime {
                print("❌ リワード広告の有効期限が切れています")
                loadAd()
                return false
            }
        }
        
        // 最後に広告を表示してからの経過時間をチェック
        if let lastShowTime = lastAdShowTime {
            let timeSinceLastAd = Date().timeIntervalSince(lastShowTime)
            let minutesSinceLastAd = Int(timeSinceLastAd / 60)
            let minutesUntilNext = Int((minTimeBetweenAds - timeSinceLastAd) / 60)
            
            print("📊 最後のリワード広告表示: \(lastShowTime)")
            print("📊 経過時間: \(minutesSinceLastAd)分 / 必要時間: \(Int(minTimeBetweenAds / 60))分")
            
            if timeSinceLastAd < minTimeBetweenAds {
                print("❌ リワード広告表示の頻度制限により表示をスキップ（次回表示まであと\(minutesUntilNext)分）")
                return false
            }
            print("✅ 頻度制限クリア（\(minutesSinceLastAd)分経過）")
        } else {
            print("✅ 初回リワード広告表示")
        }
        
        print("✅ リワード広告表示可能")
        return true
    }
    
    func showAd(from viewController: UIViewController, onDismissed: @escaping (Bool) -> Void) {
        print("🎁 リワード広告表示要求")
        
        guard canShowAd(), let ad = rewardedAd else {
            print("⚠️ リワード広告が準備できていません - カメラを直接開きます")
            onDismissed(false)
            return
        }
        
        print("✅ リワード広告を表示します")
        
        // 最上位のビューコントローラーを取得
        let topViewController = getTopViewController(from: viewController)
        
        self.onAdDismissed = onDismissed
        self.didEarnReward = false
        
        // 広告表示時刻を記録（広告が実際に表示される前に記録）
        let now = Date()
        lastAdShowTime = now
        print("✅ リワード広告表示時刻を記録: \(now)")
        
        ad.present(from: topViewController) { [weak self] in
            guard let self = self else { return }
            
            let reward = ad.adReward
            print("🎁 リワード広告の報酬を獲得: \(reward.amount) \(reward.type)")
            
            // 報酬を獲得したことを記録
            self.didEarnReward = true
            
            // 報酬獲得回数をUserDefaultsに保存
            let count = UserDefaults.standard.integer(forKey: "reward_ad_count")
            UserDefaults.standard.set(count + 1, forKey: "reward_ad_count")
            print("📊 リワード広告表示回数: \(count + 1)")
        }
    }
    
    // 最上位のビューコントローラーを取得
    private func getTopViewController(from viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return getTopViewController(from: presented)
        }
        return viewController
    }
    
    // MARK: - FullScreenContentDelegate
    
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        _ = ad  // 未使用警告を回避
        print("リワード広告のインプレッションが記録されました")
    }
    
    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        _ = ad  // 未使用警告を回避
        print("リワード広告がクリックされました")
    }
    
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        _ = ad  // 未使用警告を回避
        print("リワード広告の表示に失敗: \(error.localizedDescription)")
        isAdReady = false
        loadAd()
        onAdDismissed?(false)
        onAdDismissed = nil
    }
    
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        _ = ad  // 未使用警告を回避
        print("📺 リワード広告を表示開始")
    }
    
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        _ = ad  // 未使用警告を回避
        print("📺 リワード広告が閉じられました（報酬獲得: \(didEarnReward)）")
        print("📺 カメラを開くためのコールバックを実行します")
        
        // 次の広告をロード
        isAdReady = false
        loadAd()
        
        // コールバックを実行（これでカメラが開くはず）
        onAdDismissed?(didEarnReward)
        onAdDismissed = nil
        
        print("📺 コールバック実行完了")
        
        // 現在の制限状態をログ出力
        if let lastTime = lastAdShowTime {
            let nextAvailable = lastTime.addingTimeInterval(minTimeBetweenAds)
            print("📊 次回のリワード広告表示可能時刻: \(nextAvailable)")
        }
    }
}

