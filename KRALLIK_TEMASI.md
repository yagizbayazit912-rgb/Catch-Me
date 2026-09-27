# Catch Me — açık krallık teması

Görsel önizleme ve gerçek Firebase/GPS kurulumu artık tek belgede toplandı:

**[SETUP_TAM_SURUM.md](SETUP_TAM_SURUM.md)**

Önizlemeyi çalıştır:

```sh
flutter pub get
flutter run -t lib/visual_preview.dart
```

Önizlemede açık Esri topografik harita, çimen/toprak tonlu tam altıgen dolgu,
2.5D gölge, çadır → ev → apartman → otel → gökdelen vektör yapıları, toz
bulutu, bayrak ve ele geçirme halkası bulunur. Gerçek oyun akışında aynı
katmanlar Firebase tarafından gelen sahiplik ve yükseltme verisiyle çizilir.
