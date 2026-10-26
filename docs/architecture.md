# Mimari

Android uygulaması MVVM ve Riverpod kullanır. Veritabanı, giriş ve dosya işlemleri çalışma zamanında Firebase kullanmaz.

- `lib/data/local_database.dart`: SQLite belge deposu; sürümlü şema, atomik batch/transaction işlemleri ve değişiklik stream'leri.
- `lib/data/local_document_query.dart`: mevcut repository sorgularının yerel karşılıkları. Koleksiyonlar SQLite indeksiyle seçilir; mevcut katalog boyutunda alan filtreleri bellekte uygulanır.
- `lib/data/local_document_values.dart`: zaman damgası hassasiyetini, iç içe alanları, referansları ve ikili verileri koruyan arşiv kodlaması.
- `lib/data/local_bootstrap.dart`: dosya SHA-256 kontrolleri, tek seferlik atomik içe aktarma ve bütünlük doğrulaması. Eski kurulumda arşiv eksikse boş kütüphane oluşturmaz.
- `lib/data/local_identity.dart`: önceki kullanıcı kimliğini korur; eski okuma konumu ve dosya anahtarları değişmez.
- `lib/data/local_images.dart`: özgün görsel URL'lerini veritabanında değiştirmeden yerel kopyalara yönlendirir.
- `lib/data`: kitap, profil, ödünç kişi repository'leri ve cihazdaki PDF/EPUB/ses dosyaları.
- `lib/viewmodels`: UI komutları.
- `lib/views`: ekranlar, formlar ve geçici UI durumu.
- `lib/app`: tema, bağımlılık yönetimi ve yerel mod metinleri.

SQLite yazıları tamamlanmadan stream güncellemesi yayınlanmaz. Başarısız işlemler geri alınır. İçe aktarma işareti verilerle aynı transaction içinde yazılır; sonraki açılışlar yeni yerel düzenlemelerin üstüne eski arşivi yazmaz. Eski JSON taslak kuyruğu önceki kurulumdaki bekleyen düzenlemeleri tamamlamak için korunur.

`test/local_database_test.dart` yeniden açılışta kalıcılığı, geri almayı, eşzamanlı güncellemeleri, kimlik ve zaman damgası korunmasını ve çevrimdışı kitap işlemlerini doğrular. `MIGRATION_ARCHIVE` derleme tanımı verildiğinde gerçek arşivin tüm belgeleri de birebir karşılaştırılır. Widget testleri editör, PDF/EPUB, ses ve not akışlarını denetler.