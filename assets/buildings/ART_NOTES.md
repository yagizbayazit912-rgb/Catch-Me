# Bina görselleri

Oyunun canlı harita katmanı artık `lib/widgets/hex_zone_layer.dart` içindeki
`KingdomBuildingPainter` ile vektör olarak çiziliyor. Böylece beş seviye aynı
izometrik kamera, sıcak parşömen renkleri ve keskin kenarlarla her yakınlaştırma
seviyesinde akıcı kalır:

1. Çadır
2. Ev
3. Apartman
4. Otel
5. Gökdelen

`cottage.png`, `manor.png`, `castle.png` ve `shop.png` eski raster denemeleridir;
asset klasöründe korunurlar ve tema değişimi için yeniden kullanılabilirler.
Canlı painter gövdesi arsa dolgusunu, bayrağı, pencere detaylarını, yükselme
animasyonunu ve toz bulutunu koddan üretir. Yeni resim eklemek için painter'a
ayrı bir `CustomPainter` seviyesi eklemek yeterlidir; mevcut 2.5D kamera oranı
korunmalıdır.
