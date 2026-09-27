# 24 Eylül: süre ve harita düzeltmesi

## Değişenler

- Sahiplenme için her sunucu kontrolünde saniye kırpılması kaldırıldı.
- Sayaç ilk sunucu yanıtına eşlenir. Süre bitişinde ayrıca doğrulama istenir.
  Sahiplik hâlâ sadece sunucudan verilir; ağ gecikirse ekranda doğrulama yazar.
- Normal kontrol aralığı 5 saniyedir. Bu üretimde istek maliyetini artırır;
  bu sürüm yerel emülatör testi içindir, ölçek/maliyet optimizasyonu değildir.
- Eski perspektif yaklaşımı geri geldi; yaklaşık 29 derece eğimli görünüm.
  Bu gerçek 3D kamera değil, harita ve katmanlarının ortak perspektifidir.
- Yapı tabanı hex merkezine bağlıdır. Taban genişliği hex genişliğinin %72'sidir;
  zoom ile aynı oranda ölçeklenir. Apartman/otel/gökdelen pencere konumları düzeltildi.
- İnşaat sırasında önceki seviye (ilk inşaatta şantiye) görünür. Süre bitince yeni
  yapı animasyonla açılır. İnşaat paneli ve harita saniyede bir yenilenir.
- Yeni seviyenin kirası inşaat bitmeden uygulanmaz.
- Fiziksel telefonda çalışan 127.0.0.2 adresi emulator varsayılanıdır.
- Functions kısa süreli erişilemezse uygulama artık logoda sonsuza kadar beklemez;
  harita açılır ve durum çubuğunda sunucu bağlantısı bekleniyor mesajı gösterilir.

## Güvenli kurulum — eski klasörü silme

1. Çalışan Flutter terminalinde `q` ile uygulamayı durdur.
2. Emülatörü kapatmadan önce yerel test kayıtlarını saklamak istiyorsan yeni
   terminalde eski proje kökünde `firebase.cmd emulators:export ./emulator-backup`
   çalıştır. Ardından emülatör terminalinde Ctrl+C yap.
3. ZIP'i ayrı bir klasöre çıkar. VS Code'da doğrudan pubspec.yaml bulunan
   `catch_me` klasörünü aç. Eski projedeki kendi Firebase/Android ayarların farklıysa
   yeni dosyalarla üzerlerine yazma; karşılaştır. ZIP yeni Firebase projesi oluşturmaz.
4. Yedek aldıysan eski klasördeki emulator-backup klasörünü yeni proje köküne kopyala.
5. Yeni proje kökünde:

```powershell
flutter pub get
flutter analyze
flutter test
cd functions
npm.cmd install
npm.cmd run build
npm.cmd test
cd ..
```

6. Yedek varsa:

```powershell
firebase.cmd emulators:start --only auth,firestore,functions --import=./emulator-backup --export-on-exit=./emulator-backup
```

Yedek yoksa `firebase.cmd emulators:start --only auth,firestore,functions` yeterlidir.
Emülatör terminalini açık tut. Gerçek Firebase'e deploy yapma.

7. Ayrı terminalde proje kökünden:

```powershell
& "D:\Androidsdk\platform-tools\adb.exe" -s R5CX92D29WH reverse tcp:9099 tcp:9099
& "D:\Androidsdk\platform-tools\adb.exe" -s R5CX92D29WH reverse tcp:8080 tcp:8080
& "D:\Androidsdk\platform-tools\adb.exe" -s R5CX92D29WH reverse tcp:5001 tcp:5001
flutter run -d R5CX92D29WH --dart-define=USE_FIREBASE_EMULATOR=true --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.2
```

## Telefonda kabul testleri

- Evde test kapalıyken sahipsiz gerçek hex'te kal. Sayaç sunucu doğrulamasından
  başlar. Yaklaşık 30 saniye + ağ yanıt süresinde arsa gelmeli; 0'da asılı kalmamalı.
- İlk çadır inşaatı 5 dakika. Önce şantiye, tamamlandığında çadır ve toz animasyonu.
  Ev 30 dakika; inşaat boyunca çadır görünmeli ve eski kira kullanılmalı.
- Bir binayı zoom in/out ile izle: tabanı merkezden ayrılmamalı, hex'e oranı değişmemeli.
- Eğimde sürükleme ve hex'e dokunma konumlarını kontrol et. Görünümü telefondan
  ekran görüntüsüyle doğrula; masaüstündeki matematik testi FPS testi değildir.
- Önceden verilen konum izni güncellemede korunabilir; yeniden diyalog açılmaması
  tek başına hata değildir. Telefon ayarlarından kesin konum ve arka plan iznini incele.

## Test kapsamı ve sınırlar

Bu ortamda 4 bağımsız sunucu zaman/seviye testi ve 20 yapı yerleşim kontrolü geçti.
Flutter analiz kontrolü, Flutter model/önizleme testleri ve Firebase paketleriyle
TypeScript derlemesi de çalıştırıldı. Zoom testi FlutterMap üzerinde gerçek kamera
zoom değişimiyle yapı boyutunun ve taban merkezinin tutarlılığını kontrol eder.
Telefon üzerinde eğim, animasyon, iki oyuncu ve arka plan testi henüz yapılmadı.

Bu güncelleme üretim güvenlik onayı değildir: GPS sahteciliği, eski GPS örneğinin
tekrar kullanılması, Android'in arka plan kısıtları ayrıca ele alınmalı. İnşaat şu an
duvar saatiyle ilerler; sadece arsada geçirilen süreyi sayan sistem değildir.
Yerel testte USB bağlantısını ve bilgisayardaki emülatörü açık tut.
