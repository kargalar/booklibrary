# Mimari

Uygulama, özellik bazlı UI ile veri/alan katmanlarını ayıran pragmatik bir MVVM yapısı kullanır.

## Katmanlar

- `lib/data`: Firebase, dosya sistemi ve harici servis erişimi. Repository sınıfları veri erişimini tek yerde toplar.
- `lib/viewmodels`: Ekranların ihtiyaç duyduğu use-case benzeri komutları repository'lere yönlendirir.
- `lib/views`: Sadece ekran düzeni, kullanıcı etkileşimi ve navigasyon. Veri erişimi doğrudan servis yerine ViewModel/provider üzerinden yapılır.
- `lib/app`: Uygulama kurulumu, tema ve dependency injection provider'ları.
- `lib/features`: Olay tabanlı ve birden fazla durum içeren özellikler. Kimlik doğrulama BLoC'u burada bulunur.

## State yönetimi kararı

- Riverpod: repository, ViewModel, tema controller ve BLoC bağımlılıklarının yaşam döngüsü/dependency injection yönetimi.
- BLoC: kimlik doğrulamadaki loading, hata ve iptal gibi olay-durum geçişleri.
- MVVM/`ChangeNotifier`: kütüphane ekranının mevcut stream ve komut API'si. Bu ekran için BLoC eklemek, mevcut Firestore stream modeline gereksiz bir kopya state katmanı eklerdi.
- Widget içi `State`: yalnızca form, animasyon, filtre ve geçici UI durumları.

## Test edilebilirlik

Auth BLoC, Firebase implementasyonuna değil `AuthGateway` arayüzüne bağlıdır. Böylece UI ve Firebase olmadan durum geçişleri unit test ile doğrulanabilir.
