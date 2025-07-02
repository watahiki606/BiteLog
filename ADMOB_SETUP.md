# AdMob広告実装 - 引き継ぎ資料

## プロジェクト概要
- **プロジェクト名**: BiteLog（食事記録iOSアプリ）
- **目標**: Google AdMobのバナー広告を実装して広告モデルに変更
- **開発環境**: iOS 18.2、Xcode 16、SwiftUI + SwiftData
- **Bundle ID**: `com.watahiki.BiteLog`

## 🚨 現在の問題状況

### **起動時クラッシュ発生中**
```
*** Terminating app due to uncaught exception 'GADInvalidInitializationException', 
reason: 'The Google Mobile Ads SDK was initialized without an application ID.'
```

**根本原因**: `GADApplicationIdentifier`がInfo.plistに正しく設定されていない

## ✅ 完了した作業

### 1. Google Mobile Ads SDK v12.6.0の追加
- Swift Package Manager経由で追加済み
- 依存関係: GoogleMobileAds v12.6.0, GoogleUserMessagingPlatform v3.0.0

### 2. AdMob実装コード
- ✅ `BiteLog/Utilities/AdMobManager.swift`: SDK初期化とATT管理
- ✅ `BiteLog/Views/BannerAdView.swift`: SwiftUIバナー広告コンポーネント  
- ✅ Adaptive Banner Ads実装（`currentOrientationAnchoredAdaptiveBanner`使用）

### 3. UI統合完了
- ✅ `ContentView.swift`: タブビュー下部に固定バナー広告配置
- ✅ `DayContentView.swift`: スクロール内バナー広告配置
- ✅ `BiteLogApp.swift`: アプリ起動時初期化処理

### 4. プロジェクト設定
- ✅ `OTHER_LDFLAGS = "-ObjC"`設定済み
- ✅ `NSUserTrackingUsageDescription`設定済み
- ⚠️ `GADApplicationIdentifier`設定に問題あり

## 🔴 緊急対応が必要な事項

### 1. **AdMobアカウント作成（最優先・ユーザー作業）**
```
TODO: ユーザーがAdMobアカウント作成する必要があります
URL: https://admob.google.com/
```

**必要な手順**:
1. Google AdMobアカウント作成
2. 「アプリを追加」でBiteLogアプリ登録
3. Bundle ID: `com.watahiki.BiteLog`を設定
4. **実際のアプリID**を取得（`ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX`形式）
5. バナー広告ユニット作成

### 2. **Info.plist設定問題の解決（技術的対応）**
```
TODO: GADApplicationIdentifierがInfo.plistに反映されない問題を解決する
現在の設定: INFOPLIST_KEY_GADApplicationIdentifier設定済みだが反映されず
```

**解決方法候補**:
- **方法A**: 手動Info.plist作成（GENERATE_INFOPLIST_FILE = NO）
- **方法B**: ビルド設定修正で確実に反映

## 📁 実装済みファイル詳細

### AdMobConfig設定
```swift
// BiteLog/Utilities/AdMobManager.swift内
#if DEBUG
static let applicationID = "ca-app-pub-3940256099942544~1458002511" // サンプルID
static let bannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"
#else
// TODO: 実際のAdMobアプリIDに更新する必要があります
static let applicationID = "YOUR_PRODUCTION_APPLICATION_ID"
static let bannerAdUnitID = "YOUR_PRODUCTION_BANNER_AD_UNIT_ID"
#endif
```

### 現在のプロジェクト設定
```
GENERATE_INFOPLIST_FILE = YES
INFOPLIST_KEY_GADApplicationIdentifier = "ca-app-pub-3940256099942544~1458002511"
INFOPLIST_KEY_NSUserTrackingUsageDescription = "このアプリは、より関連性の高い広告を表示するために、あなたのアクティビティを追跡することがあります。"
OTHER_LDFLAGS = "-ObjC"
```

## 🔧 次のエージェントへの作業指示

### **即座に対応すべき事項**

1. **Info.plist問題の解決**
   ```
   TODO: GADApplicationIdentifierが確実にInfo.plistに設定される方法を実装
   - 手動Info.plist作成を試す
   - または INFOPLIST_KEY_ 設定が反映される方法を調査
   ```

2. **ユーザーへのAdMobアカウント作成案内**
   ```
   TODO: AdMobアカウント作成の具体的手順をユーザーに説明
   - 取得すべき情報（アプリID、広告ユニットID）を明確化
   ```

### **検証方法**
1. ✅ アプリ起動時にクラッシュしないこと
2. ✅ コンソールに"AdMob SDK初期化完了"が表示されること  
3. ✅ バナー広告領域が表示されること

### **AdMobアカウント作成後の作業**
```
TODO: 実際のAdMobアプリID取得後に以下を更新
1. AdMobConfig.applicationIDを実際のIDに更新
2. バナー広告ユニットIDを実際のIDに更新
3. SKAdNetworkItems完全設定
4. 本番環境テスト
```

## ⚠️ 重要な注意点

- **サンプルID使用不可**: `ca-app-pub-3940256099942544~*`は動作しない
- **Info.plist自動生成の限界**: 手動設定が必要な可能性
- **iOS 18/Xcode 16対応**: 最新環境での特殊対応が必要

## 📚 参考リンク
- [AdMob iOS統合ガイド](https://support.google.com/admob/answer/9363762)
- [Google Mobile Ads SDK v12ドキュメント](https://developers.google.com/admob/ios)
- [iOS 18対応ガイド](https://developers.google.com/admob/ios/migration)

## 📝 コミット履歴
この文書更新時点での実装状況は、Gitコミット履歴で確認可能です。
