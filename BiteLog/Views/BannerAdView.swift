import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String
    let adSize: AdSize
    let onAdSizeChanged: ((CGFloat) -> Void)?
    
    // TODO: 現在テスト用広告ユニットIDを使用中
    // AdMobアカウント作成後、AdMobConfig.bannerAdUnitIDを実際のIDに更新が必要
    init(adUnitID: String = AdMobConfig.bannerAdUnitID, adSize: AdSize = AdSizeBanner, onAdSizeChanged: ((CGFloat) -> Void)? = nil) {
        self.adUnitID = adUnitID
        self.adSize = adSize
        self.onAdSizeChanged = onAdSizeChanged
    }
    
    func makeUIView(context: Context) -> BannerView {
        let bannerView = BannerView(adSize: adSize)
        bannerView.adUnitID = adUnitID
        
        // iOS 15以降対応のrootViewController取得方法
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            bannerView.rootViewController = rootViewController
        }
        
        bannerView.delegate = context.coordinator
        
        let request = Request()
        bannerView.load(request)
        
        return bannerView
    }
    
    func updateUIView(_ uiView: BannerView, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onAdSizeChanged: onAdSizeChanged)
    }
    
    class Coordinator: NSObject, BannerViewDelegate {
        private let onAdSizeChanged: ((CGFloat) -> Void)?
        
        init(onAdSizeChanged: ((CGFloat) -> Void)?) {
            self.onAdSizeChanged = onAdSizeChanged
        }
        
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("バナー広告の読み込みに成功しました")
            
            // 広告のサイズが変更された場合、コールバックを呼び出す
            let adHeight = bannerView.adSize.size.height
            onAdSizeChanged?(adHeight)
        }
        
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("バナー広告の読み込みに失敗しました: \(error.localizedDescription)")
            
            // エラー時にはデフォルトの高さを使用
            onAdSizeChanged?(50)
        }
        
        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            print("バナー広告のインプレッションが記録されました")
        }
        
        func bannerViewDidRecordClick(_ bannerView: BannerView) {
            print("バナー広告がクリックされました")
        }
    }
}

struct AdaptiveBannerView: View {
    @State private var adHeight: CGFloat = 50
    
    var body: some View {
        GeometryReader { geometry in
            BannerAdView(
                adSize: currentOrientationAnchoredAdaptiveBanner(width: geometry.size.width),
                onAdSizeChanged: { newHeight in
                    adHeight = newHeight
                }
            )
        }
        .frame(height: adHeight)
    }
}