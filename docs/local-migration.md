# Android yerel geçiş ve kurtarma

## Veri güvenliği

Uygulama kimliği `com.example.booklibrary`, mevcut imza ve kullanıcı/kitap kimlikleri korunur. Güncelleme `adb install -r` ile yapılır. Uygulamayı kaldırmak, `pm clear` çalıştırmak veya veri klasörlerini silmek bu geçişin bir parçası değildir.

Geçişten önce hem Firestore'un bütün koleksiyonları ve alt koleksiyonları hem Storage nesneleri dışa aktarılır. Her dosya boyut ve SHA-256 ile doğrulanır. Telefonun mevcut özel uygulama klasörleri, tercihleri, yerel kitapları ve önbelleği ayrıca TAR arşivine alınır. Bu kişisel arşivler git deposuna veya APK içine eklenmez.

Sunucu kayıtları esas alınır; telefonda bekleyen Firestore yazısı varsa o belge önceliklidir. Sunucuda artık olmayan eski önbellek kayıtları aktif kütüphaneye geri getirilmez, `cloud_archive/recovery/phone_cache.json` içinde saklanır. Eski `local_books` kuyruğu, okuma konumları ve yerel kitap dosyaları yerinde kalır.

## Araçlar

- `functions/export_local_backup.js <mutlak-yedek-klasörü>`: bulutu yalnızca okur; veritabanını ve dosyaları dışa aktarır. `FIREBASE_CLI_ROOT` yerel Firebase CLI paketini gösterir. Kimlik bilgilerini çıktıya yazmaz.
- Aynı komutta `--verify-only`: bulut belgelerinin yedekten sonra değişmediğini kontrol eder.
- Geçici, aynı imzalı köprü APK'sı telefondaki hesabı ve Firestore önbelleğini ağ yazısı yapmadan okur. Telefonun özel veri arşivini oluşturur; yalnızca ADB yönlendirmesiyle erişilen, rastgele anahtarlı yerel aktarım sunucusu kullanır. Köprü kaynak/APK kopyası geçiş yedeğinde saklanır; son APK'da bulunmaz.
- `tools/capture_phone_backup.cjs <mutlak-yedek-klasörü>`: köprünün hazırladığı telefon arşivlerini bilgisayara alır.
- `tools/prepare_local_migration.cjs <mutlak-yedek-klasörü>`: bulut, telefon görsel önbelleği ve erişilebilir harici kapaklardan içe aktarma paketi üretir. Çıkarılmış telefon yedeği `native` altında beklenir. Erişilemeyen görsel URL'leri değiştirilmez ve raporlanır.
- `tools/stage_phone_migration.cjs <mutlak-staging-klasörü>`: dosyaları doğrular ve çalışan köprü aracılığıyla telefona aktarır; manifest en son yazılır.

## Son uygulamanın açılışı

`LocalBootstrap`, önce her dosyanın boyutunu ve SHA-256 değerini kontrol ederek uygulamanın özel belge klasörüne kopyalar. Mevcut farklı dosyaların üzerine yazmaz. Ardından SQLite verilerini ve tamamlanma işaretini aynı işlemde kaydeder. İçe aktarılan tüm belgeler özgün arşivle karşılaştırılır ve SQLite `integrity_check` uygulanır. Başarı logları `LOCAL_IMPORT_VERIFIED` ve `LOCAL_LIBRARY_READY` ile başlar.

Telefon internetten ayrılarak yeniden başlatılır; kitap listesi, yerel arama, notlar ve okuma konumları denetlenir. Bulut kaynakları ancak bu kontroller ve yedek doğrulamaları tamamlandıktan sonra kaldırılır.

## Kurtarma

Bilgisayardaki `original.apk`, `phone_private_backup.tar`, `phone_migration_backup.json`, `cloud_backup.json`, Storage dosyaları ve son içe aktarma paketi korunmalıdır. Son uygulama arşiv eksikliği veya bütünlük hatasında eski verileri silmez. Yerel SQLite dosyası `booklibrary_local.db`, dosya arşivi uygulama belgelerindeki `cloud_archive` klasörüdür. İçe aktarmadan sonra aynı arşiv yeniden sunulsa bile yerel düzenlemelerin üzerine yazılmaz.

Yeni kurulumlarda boş bir yerel profil açılır. Eski telefondaki veri klasörüyle ilişki olmadan yapılan yeni kurulum, silinen uygulamanın verilerini kendiliğinden geri getiremez. Tarihsel Windows/web çıktıları bu sürümün doğrulama kapsamına dahil değildir.