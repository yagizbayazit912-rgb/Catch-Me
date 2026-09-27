# Catch Me — çalışan demo kurulumu ve oyun kuralları

Bu paket iki ayrı çalıştırma yoluna sahip:

- `lib/visual_preview.dart`: Firebase ve GPS istemeyen görsel oyun alanı. Açık
  renkli harita, 2.5D altıgen dolgusu, çadır → ev → apartman → otel → gökdelen
  yapıları, toz bulutu ve ele geçirme animasyonunu hızlıca denemek için.
- `lib/main.dart`: gerçek cihazda GPS, anonim Firebase oturumu, Firestore
  bölge akışı, Callable Cloud Functions, arka plan konumu ve bildirimler.

Blaze'e geçmeden önce ücretsiz Emulator Suite ile de test edebilirsin. Uygulama
build-time `USE_FIREBASE_EMULATOR` anahtarıyla production Firebase yerine yerel
Auth, Firestore ve Functions portlarına bağlanır. USB ile bağlı gerçek telefon
için `adb reverse` kullan; Android Studio emülatörü için host olarak `10.0.2.2`
ver.

## Görsel ve oyun akışı

Sahipsiz altıgene giren oyuncu, doğruluğu en fazla 90 metre olan GPS kalibrasyonu
ile sunucuya yaklaşık 10 saniyede bir heartbeat gönderir. Sunucu aynı altıgende
30 doğrulanmış saniye gördüğünde mülkiyeti transaction içinde verir. Bu anda
altıgenin tamamı çimen tonlu, gölgeli ve altı piksel yükseltilmiş bir 2.5D
katmanla dolar. Seviye 0 arsa olarak kalır; ilk yapı olan çadır, yükseltme
başlatılınca görünür.

| Seviye | Yapı | Başlangıç maliyeti | İnşaat | Giriş kirası |
| --- | --- | ---: | ---: | ---: |
| 0 | Arsa | — | — | 0 sn |
| 1 | Çadır | 5 dk | 5 dk | 1 dk |
| 2 | Ev | 30 dk | 30 dk | 5 dk |
| 3 | Apartman | 2 sa | 2 sa | 20 dk |
| 4 | Otel | 8 sa | 8 sa | 1 sa |
| 5 | Gökdelen | 24 sa | 24 sa | 3 sa |

Para yerine `timeBalanceSec` kullanılır. Oyuncu doğrulanmış bölgede kaldığı
süreyi günlük en fazla iki saat olacak şekilde zaman bakiyesine alır. Kira aynı
birimle ödenir ve 15 dakikalık ziyaret soğuma süresi vardır. İnşaat başlarken
maliyet düşer, seviye görseli hemen gelir, `upgradeReadyAt` dolana kadar sonraki
inşaat kilitli kalır.

Sahibi 72 saat hiç görünmezse arsa kuşatılabilir. Kuşatma süresi yapı seviyesine
göre 10 dakika, 10 dakika, 30 dakika, 2 saat, 6 saat ve 24 saattir. Kuşatan
oyuncu süreyi kesintisiz heartbeat'lerle doldurur. Tamamlanınca arsa yeni
oyuncuya seviye 0 olarak geçer; eski bina geri dönüştürülür ve iki oyuncunun
arsa sayısı transaction içinde güncellenir. Bu süreler `lib/models/zone.dart`
ve `functions/src/index.ts` içinde birlikte tutulur.

## 1. Bilgisayar kurulumu

Gerekenler:

- Flutter stable (bu proje Dart `^3.10.1` ister), Android Studio ve gerçek bir
  Android cihaz veya Xcode yüklü macOS ile gerçek iPhone.
- Node.js 20 ve Firebase CLI.
- Harita döşemelerini indirecek internet bağlantısı.

Komut satırında proje klasöründe çalıştır:

```sh
flutter pub get
cd functions
npm install
npm run build
cd ..
```

## 2. Firebase projesi

1. Firebase Console'da yeni bir proje oluştur.
2. **Authentication → Sign-in providers → Anonymous** seçeneğini aç.
3. Android uygulamasını `com.example.catch_me` paket adıyla ekle ve kendi
   `google-services.json` dosyanı `android/app/google-services.json` ile değiştir.
4. iOS uygulamasını ekle, `GoogleService-Info.plist` dosyasını Xcode'da
   `ios/Runner/GoogleService-Info.plist` olarak projeye ekle. Firebase CLI yerine
   FlutterFire kullanmak istersen `flutterfire configure` ile `lib/firebase_options.dart`
   üretip `main.dart` içindeki `Firebase.initializeApp()` çağrısını generated
   `DefaultFirebaseOptions.currentPlatform` ile çalıştırabilirsin.
5. CLI oturumu ve proje eşlemesini yap:

```sh
firebase login
firebase use --add
```

Listeden oluşturduğun projeyi seç. Ardından backend ve kuralları yayınla:

```sh
cd functions
npm install
npm run build
cd ..
firebase deploy --only functions,firestore:rules
```

`firebase.json`, `functions/` ve `firestore.rules` dosyaları bu pakette hazır.
İstemci Firestore'a para, sahiplik veya kira yazamaz; bu değişiklikler yalnızca
`recordPresence` ve `startUpgrade` Callable Functions transaction'larından geçer.

## 3. Telefon izinleri

Android manifestinde hassas/arka plan konumu, foreground service, wake lock ve
bildirim izinleri ekli. İlk açılışta:

1. Hassas konuma izin ver.
2. Android ayarlarında Catch Me için **Her zaman izin ver** seç.
3. Android 13+ bildirim iznini ver.
4. Pil tasarrufunda uygulamayı kısıtlamadan çıkar. Uygulamayı sistem ayarından
   **Zorla durdur** yaparsan hiçbir Flutter uygulaması arka planda GPS alamaz.

iOS'ta `Info.plist` içinde When-In-Use, Always ve `UIBackgroundModes/location`
hazır. Xcode'da **Signing & Capabilities → Background Modes → Location updates**
seç. İlk konum izninden sonra sistemin **Always** seçeneğini ver. iOS bildirim
kanalı `AppDelegate.swift` içinde aynı `catch_me/notify` MethodChannel üzerinden
çalışır; arka planda gerçek cihazla dene.

## 4. Çalıştırma

### Ücretsiz yerel Firebase testi

Proje kökünde bir terminalde:

```sh
firebase emulators:start --only auth,firestore,functions
```

USB ile bağlı fiziksel Android cihazda ikinci terminalde:

```sh
adb reverse tcp:9099 tcp:9099
adb reverse tcp:8080 tcp:8080
adb reverse tcp:5001 tcp:5001
flutter run -d <cihaz-id> \
  --dart-define=USE_FIREBASE_EMULATOR=true \
  --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.2
```

Android Studio emülatörü kullanıyorsan `adb reverse` yerine şu host'u ver:

```sh
flutter run -d <cihaz-id> \
  --dart-define=USE_FIREBASE_EMULATOR=true \
  --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

Bu modda GPS telefondan gelir, fakat kullanıcı/arsa/kira verileri bilgisayardaki
emülatöre yazılır; production Firebase'e ve billing hesabına erişilmez.

Görsel önizleme (hesap ve GPS yok):

```sh
flutter run -t lib/visual_preview.dart
```

Gerçek oyun:

```sh
flutter run
```

Telefon üzerinde animasyon ve harita akıcılığını ölçmek için:

```sh
flutter run --profile -t lib/visual_preview.dart
```

## 5. İki cihaz testi

1. Aynı Firebase projesine bağlı iki fiziksel telefona debug/release build'i
   kur. Anonim giriş her cihazda farklı kullanıcı oluşturur.
2. A cihazında sahipsiz bir altıgende GPS doğruluğu 90 metrenin altındayken
   30 saniye kal. Harita altıgeninin tamamı dolar ve `users/{uid}.zonesOwned`
   artar.
3. A, kendi bölgesinin alt bilgi kartından sıradaki yapıyı başlatır. Zaman
   bakiyesi hemen düşer; yapı görseli gelir; süre dolmadan yeni seviye butonu
   kilitli kalır.
4. B aynı altıgene girdiğinde, seviyeye göre zaman kirası B'nin bakiyesinden
   A'ya aktarılır. Aynı B–arsa çifti 15 dakika içinde ikinci kez ücret ödemez.
5. A cihazını en az 72 saat gerçek konum heartbeat'i göndermeyecek şekilde
   bırakıp B ile kuşatma süresini test et. Demo hızlandırması yalnızca
   `PresenceService.debugOccupy` içindir ve Firestore'a yazmaz.
6. Android bildiriminde aktif heartbeat/ele geçirme ilerlemesini, iOS'ta
   bildirim merkezindeki Catch Me kaydını kontrol et.

İlk iki cihaz testinde aynı fiziksel konumu paylaşmak yerine açık alanda GPS
doğruluğunu gözlemle. Emülatör konumu veya sahte GPS üretimi sunucu tarafından
doğrulanmadığı için gerçek anti-cheat testi sayılmaz.

## 6. Yayına çıkmadan önce

- Esri World Topographic raster döşemesi prototip için kullanılıyor; trafik ve
  lisans şartlarını kontrol edip üretimde uygun bir tile/vector sağlayıcısına
  geç. Atıf `MapScreen` altında görünür.
- Firebase App Check, rate limit/abuse izleme, hesap silme ve KVKK/GDPR izin
  ekranlarını ekle. Konum geçmişini gereksiz tutma.
- Anonim hesapları e-posta/Apple/Google hesabına bağlayacak account-link akışı
  ekle; aksi halde uygulama verisi cihaz silinince kaybolur.
- Kuşatma, kira ve inşaat sürelerini canlı oyuncu telemetrisiyle dengele.
  Süre sabitleri hem Flutter UI'sında hem Cloud Functions'ta aynı kalmalıdır.
- Gerçek cihazda pil tüketimi, arka plan heartbeat aralıkları ve harita tile
  kotasını ölç. Mobil işletim sistemleri güncellemeleri geciktirebilir; 30
  saniyelik sahiplik kararı bu yüzden sunucu doğrulamalı heartbeat ile verilir,
  telefonun yerel sayacıyla kesinleşmez.
