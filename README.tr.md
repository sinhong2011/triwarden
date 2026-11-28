<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Triwarden uygulama simgesi">
</p>

<h1 align="center">Triwarden</h1>

<p align="center">
  <a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a> ve Bitwarden için yerel bir Mac parola yöneticisi.<br>
  macOS 26 için Swift ve SwiftUI ile geliştirildi.
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.zh-HK.md">粵語</a> ·
  <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.de.md">Deutsch</a> ·
  Türkçe
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/releases/latest/download/Triwarden.dmg"><img src="https://img.shields.io/badge/Download-for%20macOS-000000?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="macOS için en son Triwarden DMG dosyasını indirin"></a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml"><img src="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="Lisans: GPL-3.0"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <img src="promo/public/shots/vault-dark.png" width="820" alt="Koyu temada kasa: kenar çubuğu, öğe listesi ve parolası, canlı tek kullanımlık kodu ve ayrıntılarıyla bir oturum açma öğesi">
</p>

> **Durum:** erken sürümler (0.x). Gerçek Vaultwarden ve Bitwarden hesaplarıyla çalışır ve her ikisine karşı test edilmiştir,
> ancak 1.0 sürümüne kadar her zamanki istemcinizi elinizin altında tutun. Ekran görüntüleri gerçek bir hesabı değil, yerleşik demo kasayı gösterir.

## Kurulum

macOS 26 (Tahoe) veya üzerini gerektirir.

```bash
brew install --cask sinhong2011/tap/triwarden
```

Veya [en son sürümden](https://github.com/sinhong2011/triwarden/releases/latest) imzalı, noter onaylı DMG dosyasını indirin.
Triwarden, **Ayarlar › Hakkında** bölümünden imzalı güncellemeleri denetleyebilir. Otomatik denetimler ve kurulum isteğe bağlıdır.
Homebrew kullanıcıları `brew upgrade --cask triwarden` ile güncelleyebilir.

## Buradan başlayın

1. Triwarden'ı açın ve Vaultwarden sunucunuzu, Bitwarden US'i veya Bitwarden EU'yu seçin. Mevcut hesabınızla oturum açın.
2. Parolaları, geçiş anahtarlarını (passkey) ve doğrulama kodlarını doldurmak için **Sistem Ayarları › Genel › Otomatik Doldurma ve Parolalar** bölümünden Triwarden'ı etkinleştirin.
3. Kasa listesini filtrelemek için **⌘F** tuşlarını kullanın veya Triwarden'da ya da başka herhangi bir uygulamada komut paletini açmak için **⇧⌘Space** tuşlarına basın.
   Otomatik yazma, **Triwarden Auto-Type** için Erişilebilirlik izni gerektirir; bunu **Ayarlar › Kısayollar** bölümünden yapılandırın.
   Tarayıcı uzantısı isteğe bağlıdır; tümleştirme denetimleri Ayarlar'dadır.

**Çevrimdışı:** Bu Mac'te kayıtlı şifreli kasayı açabilir ve okuyabilirsiniz. Öğe oluşturma, düzenleme, içe aktarma ve silme
işlemleri hesabın sunucusuna bağlantı gerektirir; değişiklikler daha sonra gönderilmek üzere kuyruğa alınmaz.

**Resmî derlemeler ve ödeme:** Kişisel kullanım, tüm özellikler kullanılabilir ve süre sınırı olmadan ücretli bir anahtar olmaksızın devam edebilir.
Yaklaşık 30 gün sonra, kayıtlı olmayan bir resmî derleme başlatma sırasında haftada en fazla bir kez satın alma hatırlatıcısı gösterebilir.
Tek seferlik ücretli bir anahtar hatırlatıcıyı kaldırır ve bir kişiyi tüm Mac'lerinde kapsar. Resmî bir derlemeyi iş hesaplarıyla kullanmak
kişi başına bir ücretli anahtar gerektirir. Bkz. [ücretli lisans koşulları](docs/LICENSE-TERMS.md). Kaynak derlemeleri aşağıda açıklanan GPL haklarını korur.

## Özellikler

**Kasanız, yerel olarak**
- Klasörler, favoriler, özel alanlar, Arşiv ve Çöp Kutusu ile oturum açma bilgileri, güvenli notlar, kartlar, kimlikler, SSH anahtarları, banka hesapları, sürücü belgeleri ve pasaportlar;
  parola geçmişi, klonlama ve hassas öğelerde "ana parolayı sor" seçeneği. Öğe düzenleyicide ekleri ekleyin, yeniden adlandırın, değiştirin, indirin ve kaldırın.
- Sunucular arasında aynı anda birden fazla hesap: kendi barındırdığınız Vaultwarden veya Bitwarden ve Bitwarden bulutu (US ve EU).
  Parola, iki adımlı doğrulama ve tek oturum açma (SSO) ile giriş desteklenir.
- Paylaşılan kasalar (Bitwarden kuruluşları) ve paylaşılan klasörleri (koleksiyonlar): bir Kasalar bölümü (Kasam ve
  her paylaşılan kasa; birkaçını birlikte görmek için ⌘-tıklama), kendi klasörleriniz gibi iç içe paylaşılan klasörler, öğeleri paylaşılan bir kasaya taşıma, paylaşılan klasörleri değiştirme, yöneticiler için olay günlükleri; WebSocket üzerinden canlı
  senkronizasyon.
- Tek seferde taşımak, arşivlemek, çöpe atmak veya geri yüklemek için birden fazla öğe seçin (⌘-tıklama, ⇧-tıklama, ⌘A).
- Öğe geçmişi: ne zaman oluşturulduğu ve son düzenlendiği, parolasının ne zaman değiştiği ve önceki parolaları.
- Şifreli önbellekten çevrimdışı çalışır; düzenlemeler doğrudan sunucuya gider.
- Gelecekteki öğe türleri, şifreli verileri korunarak görünür ve salt okunur kalır. Bunları güvenli bir şekilde işleyemeyen yazma ve dışa aktarma işlemleri
  bir açıklamayla durur.

**Hızlı erişim**
- Başlatmalar arasında açık kalan filtrelerle tüm kasalarda tek arama (⌘F): tür, klasör, kasa, favoriler,
  tek kullanımlık kod, geçiş anahtarı ve Watchtower sorunu. Bunları filtre menüsünden seçin veya yazın — `type:card`, `has:otp`,
  `#Work` — siz yazarken önerilerle; ⌫ sonuncusunu kaldırır. Bkz. [Arama](docs/search.md).
- Tüm kısayollar tek sayfada: Yardım › Klavye Kısayolları (⌃⇧/).
- Herhangi bir öğeyi bulmak veya herhangi bir komutu çalıştırmak için her yerden erişilebilen bir komut paleti (herhangi bir uygulamada, Triwarden dâhil ⇧⌘Space veya seçeceğiniz bir kısayol).
  Bir tarayıcı veya uygulama üzerinde çağrıldığında o sayfanın (veya uygulamanın) oturum açma bilgilerini en üste koyar ve ↵ tuşu kullanıcı adı ile parolayı
  KeePass otomatik yazma gibi yazar (⌃↵ kullanıcı adı, ⌥↵ parola, ⇧ ayrıca gönderir). Menü çubuğu paneli de
  sayfanın oturum açma bilgilerini gösterir.
- Ayarlar › Kısayollar'da belirlediğiniz genel kısayollar: palet, içinde bulunduğunuz sayfayı veya uygulamayı doldurma (⌥⌘\\ tek oturum açma bilgisini
  yazar), pencereyi gösterme, yeni parola kopyalama, kilitleme. Menü kısayolları herhangi bir uygulamada olduğu gibi Sistem Ayarları'nda değişir.
- İhtiyacınız olan öğe, tek kullanımlık kodlar ve oluşturucu içeren bir menü çubuğu paneli.
- Adını ve web sitesini önceden doldurmak için etkin tarayıcı sekmesinden bir oturum açma öğesi oluşturun.
- Dar pencerelerde kenar çubuğu, liste ve öğe arasında iki parmakla kaydırma.

**Derin macOS tümleştirmesi**
- Safari, Chrome ve uygulamalarda parolalar, **geçiş anahtarları (passkey)** ve tek kullanımlık kodlar için Sistem Otomatik Doldurma; eşdeğer alan adları
  (bir google.com oturum açma bilgisi youtube.com'da doldurulur).
- Touch ID veya PIN ile kilit açma, her hesap için tek dokunuş; hesap başına kilit zaman aşımı ve isterseniz
  kilitlemek yerine oturumu kapatma.
- Kopyalanan gizli bilgiler, pencerenin alt bilgisindeki geri sayımla panodan kendiliğinden temizlenir.
- Kasanızın SSH anahtarlarıyla desteklenen bir SSH aracısı (git commit'lerini de imzalayın).
- Uygulamada onayla oturum açma bilgilerini dolduran ve kaydeden bir tarayıcı uzantısı: Safari, Chrome, Edge, Brave, Arc ve
  Firefox, ayrıca Vivaldi, Opera, Helium, Zen, LibreWolf ve diğer çoğu Chromium veya Firefox tabanlı tarayıcı
  (bunları Ayarlar'dan bağlayın). Kayıt formlarında güçlü bir parola ve e-postanızı veya özel bir
  `you+tag@` adresini önerir, ardından sayfada "Bu oturum açma bilgisi kaydedilsin mi?" diye sorar.
  Geçiş anahtarıyla oturum açma macOS Sistem Otomatik Doldurma'yı kullanır; henüz tarayıcı uzantısı tarafından işlenmemektedir.
- App Intents ve Kısayollar; bir `tw` komut satırı aracı; ve Triwarden'ı ekran görüntülerinden, kayıtlardan ve ekran paylaşımından gizleme seçeneği.

**Güvenlik araçları**
- Watchtower: zayıf, yeniden kullanılmış, ihlale uğramış ve güvenli olmayan (http://) parolalar ile iki adımlı oturum açma sunup
  kurmadığınız siteler (ihlaller için k-anonimlik; hiçbir şey açık metin olarak dışarı çıkmaz). Liste her öğenin sorununu işaretler ve
  "Sitede Değiştir" sitenin kendi parola değiştirme sayfasını açar. Yeniden kullanılmış parolalar rehberli bir temizliğe dönüşür:
  tutulacak oturum açma bilgisini seçin, ardından geri kalanını değiştirin veya kaldırın.
- Hesap güvenliği: parmak izi ifadesi, iki adımlı oturum açma (kimlik doğrulayıcı uygulaması, e-posta, kurtarma kodu), ana
  parolayı veya KDF'yi değiştirme, cihazlar, her yerden oturum kapatma ve diğer cihazlarınızdan oturum açmaları onaylama.
- Acil durum erişimi: seçeceğiniz bir bekleme süresinden sonra kasanızı görüntüleyebilecek veya devralabilecek güvenilir kişiler.
- Geçmişiyle birlikte parolalar, parolalı ifadeler (EFF kelime listesi) ve kullanıcı adları için bir oluşturucu.
- Send: metin veya dosyaları şifreli bir bağlantıyla paylaşın; daha sonra düzenleyin ve aynı bağlantıyı koruyun.
- Özel sertifika yetkilileri ve Cloudflare Access belirteçleri gibi ek istek üstbilgileri için kendi barındırdığınız sunucu desteği.
- Bitwarden, 1Password, LastPass, KeePass, Proton Pass, Dashlane, Apple Parolalar, Chrome ve Firefox'tan içe aktarma;
  parola korumalı JSON dâhil Bitwarden biçimlerinde veya KeePassXC, KeePassium ve Strongbox'ta açılan parola korumalı bir KeePass (.kdbx)
  veritabanı olarak dışa aktarma.

<p align="center">
  <img src="docs/images/search.jpg" width="820" alt="Filtre çipleriyle Kasam ve Northwind paylaşılan kasası üzerinde aynı anda tek arama ve kenar çubuğunda iç içe Northwind paylaşılan klasörleri">
  <br><sub>Aynı anda birkaç kasa üzerinde tek arama, çip olarak filtreler, kendi klasörleriniz gibi iç içe paylaşılan klasörler</sub>
</p>

<table>
  <tr>
    <td><img src="docs/images/palette.jpg" alt="Komut paleti"></td>
    <td><img src="docs/images/palette-site.jpg" alt="Safari üzerinde palet, yazmak için sayfanın oturum açma bilgisini en üste koyuyor"></td>
  </tr>
  <tr>
    <td align="center"><sub>Komut paleti</sub></td>
    <td align="center"><sub>Bir tarayıcı üzerinde: sayfanın oturum açma bilgileri en üstte, ↵ bunları yazar</sub></td>
  </tr>
  <tr>
    <td><img src="docs/images/codes.jpg" alt="Geri sayım halkalı tek kullanımlık kodlar"></td>
    <td><img src="docs/images/generator.jpg" alt="Oluşturucu"></td>
  </tr>
  <tr>
    <td align="center"><sub>Tek kullanımlık kodlar</sub></td>
    <td align="center"><sub>Oluşturucu</sub></td>
  </tr>
  <tr>
    <td><img src="docs/images/watchtower.jpg" alt="Puanı, ihlale uğramış ve yeniden kullanılmış parolalarıyla Watchtower"></td>
    <td><img src="docs/images/appearance.jpg" alt="Çapraz bölünmüş açık ve koyu modda aynı kasa"></td>
  </tr>
  <tr>
    <td align="center"><sub>Watchtower</sub></td>
    <td align="center"><sub>Açık ve koyu mod</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/menubar.jpg" width="240" alt="Menü çubuğu paneli: sayfanın oturum açma bilgisi en üstte, canlı kodlarla favoriler, hızlı işlemler ve oluşturucu"></td>
    <td><img src="docs/images/signin.jpg" alt="Kendi barındırdığınız Vaultwarden'da oturum açma"></td>
  </tr>
  <tr>
    <td align="center"><sub>Menü çubuğu</sub></td>
    <td align="center"><sub>Vaultwarden veya Bitwarden'da oturum açın</sub></td>
  </tr>
</table>

İsteğe bağlı tam kasa kapısı animasyonu **Ayarlar › Genel** bölümünden etkinleştirilir. Ana parolayı merkezine yazarsınız; her karakter pimlerin
rünlerinden birini yakar ve halkaları döndürür (silindir on iki burç işaretini taşır). Üç halkanın her birinde bir
çentik vardır. Kilit açıldığında, çentikler tek bir anahtar deliğinde hizalanana ve ışık buradan merkeze akana kadar dıştan içe doğru dönerler;
ancak o zaman kapı parçalarına ayrılır ve ekran bir kasanın iç kapısı gibi aralanır:

<p align="center"><img src="docs/images/door-sequence.jpg" width="820" alt="Kasa kapısı: yazma, halkaların dönmesi, çentiklerin tek bir anahtar deliğinde hizalanması, kilidin açılması, parçalarına ayrılması"></p>
<p align="center"><img src="docs/images/gate.jpg" width="820" alt="Açık ve koyu temada kilit ekranı"></p>

## Kaynaktan derleme

Gereksinimler: macOS 26, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node.js ve pnpm.

```bash
brew install xcodegen node pnpm
```

```bash
git clone https://github.com/sinhong2011/triwarden.git
cd triwarden
make run        # projeyi oluştur, derle ve uygulamayı aç
```

| Komut | Ne yapar |
| --- | --- |
| `make` | Tüm komutları listeler |
| `make test` | Kripto, API, içe/dışa aktarma ve SSH aracısı için birim testleri (`Packages/VaultCore`) |
| `make test-dev` | Yapılandırılmış uzak Docker ana bilgisayarındaki tek kullanımlık Vaultwarden ortamlarına karşı tümleştirme testleri |
| `make selftest` | Bu uzak geliştirme ortamına (`DevServer/`) karşı uçtan uca uygulama öz-testi |
| `make selftest-compatibility` | Gelecekteki öğe türleri, önbellek yeniden açma ve mutasyon koruması için çevrimdışı sentetik kontroller |
| `make selftest-secrets` | Yalıtılmış test verileri kullanarak imzalı uygulama Keychain ve yerel API anahtarı profili kontrolleri |
| `make uitest` | Demo kasa üzerinde tıklamalı kullanıcı arayüzü testleri (önce çalışan kopyaları kapatın) |
| `make snapshots` | Her ekranın açık ve koyu görüntülerini `build/snapshots` içine oluşturur (yalnızca belirli ekranlar için `ONLY=login,send`) |

Çekirdek mantık `Packages/VaultCore` Swift paketinde bulunur: `TriCrypto` (KDF'ler, EncString, anahtarlar, TOTP,
oluşturucular, geçiş anahtarları), `VaultwardenAPI` (oturum açma, 2FA, SSO, senkronizasyon, düzenlemeler, ekler, Send, içe/dışa aktarma),
`SSHAgent` (SSH onayları ve tarayıcı yerel mesajlaşması) ve `SecretsAgent` (onaylı yerel araç başlatmaları).
Uygulama `App/` içinde, Otomatik Doldurma uzantısı `AutoFill/` içinde, tarayıcı uzantıları `BrowserExtension/` içindedir.

## Komut satırı

Kasa aramaları için **Ayarlar > Geliştirici > tw komutunu yanıtla** seçeneğini açın.
O sayfada **Terminal Yardımcısı Kurulumu…** (veya **Triwarden › Terminal Yardımcısını Kur…**) öğesini açın ve **Kopyala ve Terminal'i Aç**'ı seçin.
Komutu yapıştırın, Mac parolanızı girin; sayfa `tw` kurulduğunda bunu algılar. **Komutu göster** tam olarak neyin çalıştırılacağını gösterir.

`tw status`, `tw get github | pbcopy`, `tw code github`, `tw list mail`, `tw generate --length 32`, `tw lock`.
Kasadan okuma işlemi uygulamada Touch ID ister.

Yerel API anahtarı araçları isteğe bağlı geliştirici özellikleridir. Yeni kullanıcılar bu sayfalar gizli olarak başlar.
**Ayarlar > Geliştirici > Gizli Bilgileri Göster** seçeneğini etkinleştirin, ardından **Gizli Bilgiler**'i açın.
**Bir .env dosyasından içe aktar**, **Kasada zaten bulunan bir anahtarı kullan** veya **Adım adım bana rehberlik et** ile başlayın.
Kılavuz; anahtar depolama, araç kurulumu, yardımcı kurulumu, ilk onay ve tekrarlı kullanımı kapsar.
Sağlayıcı hesabı veya API ücreti gerektirmeyen sahte anahtar alıştırması da içerir.

Kayıtlı aracı başlatmak için kopyalanan başlatma komutunu veya `tw-` takma adını kullanın. "Bir kez" varsayılan onay olarak kalır.
Bir aracın geçici erişimi varken, ekranın üst kısmındaki bir durum çubuğu kalan süreyi gösterebilir ve erişimi sonlandırmanıza olanak tanıyabilir.
Terminal'de kayıtlı bir araç seçmek için `tw run` ve tam başlatma komutlarını görmek için `tw tools list` kullanın.
Her API anahtarı öğesi kendisini hangi araçların kullandığını gösterir; **Erişim › İzinler** ve **Erişim › Geçmiş** etkin izinleri ve önceki kararları gösterir.
Program seçilen anahtarları alır ve bunları saklayabilir veya iletebilir.
[Başlarken](docs/local-api-keys-getting-started.md) ile başlayın.
Komutlar için [Terminal kılavuzuna](docs/local-secrets-dx.md) ve güvenlik sınırları için [Yerel API kimlik bilgileri](docs/local-secrets.md) belgesine bakın.

## Güvenlik

Ana parolanız ve şifresi çözülmüş kasa anahtarlarınız asla Mac'ten çıkmaz; sunucu yalnızca şifreli kasa verilerini görür.
Touch ID, kasa anahtarının yerel şifreli bir kopyasını bir Secure Enclave anahtarıyla korurken, yenileme belirteçleri ve özel
sunucu üstbilgileri Keychain'de saklanır. Ayrıntılar, tehdit modeli ve bir güvenlik açığının özel olarak nasıl bildirileceği için [SECURITY.md](SECURITY.md) dosyasına bakın.

## Erişilebilirlik ve diller

Uygulama VoiceOver etiketleri, klavye kısayolları, Kontrastı Artır ve Hareketi Azalt desteği sunar.
Doğrulama sınırları ve kalan eksiklikler [ACCESSIBILITY.md](ACCESSIBILITY.md) dosyasında belgelenmiştir. Uygulama English, Deutsch, 繁體中文, 粵語, 简体中文, 日本語, 한국어, Français, Español ve ไทย dillerini konuşur.

## Destek

Satın alma veya ürün soruları için [support@triwarden.cc](mailto:support@triwarden.cc) adresine e-posta gönderin. Hatalar için
bir [GitHub issue](https://github.com/sinhong2011/triwarden/issues) açın; güvenlik bildirimleri için [SECURITY.md](SECURITY.md) dosyasına bakın.

## Katkıda bulunma

Sorun bildirimleri (issue) ve pull request'ler memnuniyetle karşılanır. Commit'ler, değişiklik günlüğünü ve sürümleri yönlendiren [Conventional Commits](https://www.conventionalcommits.org)
(`feat:`, `fix:`, …) standardını izler; bkz. [docs/RELEASING.md](docs/RELEASING.md).
[Yol haritası](docs/ROADMAP.md) ve [açık sorunlar](https://github.com/sinhong2011/triwarden/issues) sırada ne olduğunu gösterir.

## Lisans

Triwarden, [GNU Genel Kamu Lisansı v3.0](LICENSE) altında özgür bir yazılımdır: kullanabilir, inceleyebilir, paylaşabilir ve
değiştirebilirsiniz; değiştirilmiş bir sürümü dağıtan herkes tam kaynak kodunu aynı lisans altında yayımlamak zorundadır.
Üçüncü taraf bileşenler ve lisansları [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) dosyasında listelenmiştir; uygulama
bunları Ayarlar › Hakkında › Teşekkürler bölümünde gösterir.

**Ad ve simge.** Lisans kodu kapsar, adı değil. "Triwarden" ve uygulama simgesi izin olmadan
değiştirilmiş sürümler veya başka ürünler için kullanılamaz: çatallar (fork) kendi adlarını ve simgelerini kullanmalı ve
resmî uygulama olduklarını ima etmemelidir.

Triwarden'ın Bitwarden, Inc. veya Vaultwarden projesiyle bağlantısı yoktur. Bitwarden, Bitwarden, Inc.'in ticari markasıdır.
