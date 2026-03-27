# تطبيق التفريغ — Flutter App

تطبيق Android كامل يتواصل مع خادم Railway الخاص بك.

---

## 🚀 خطوات البناء

### 1. تثبيت Flutter
```bash
# تحميل Flutter SDK
https://docs.flutter.dev/get-started/install/windows
# أو على Mac/Linux
brew install flutter   # Mac
```

### 2. تثبيت dependencies
```bash
cd tafrigh_flutter
flutter pub get
```

### 3. بناء APK
```bash
# APK عادي (للتجربة)
flutter build apk --release

# APK منقسم حسب المعالج (أصغر حجماً)
flutter build apk --split-per-abi --release
```

الملف يُنشأ في:
```
build/app/outputs/flutter-apk/app-release.apk
```

---

## 📱 تثبيت على الجهاز مباشرة
```bash
flutter run --release
```

---

## ⚙️ الإعدادات الأولى في التطبيق

عند أول تشغيل:
1. أدخل **رابط Railway**: `https://your-app.railway.app`
2. أدخل **مفتاح Gemini API**
3. أدخل اسم المستخدم وكلمة المرور

---

## 📦 الحزم المستخدمة

| الحزمة | الاستخدام |
|--------|-----------|
| `record` | تسجيل الصوت (AAC/m4a) |
| `just_audio` | تشغيل الصوت |
| `geolocator` | تحديد الموقع GPS |
| `file_picker` | اختيار ملفات Excel |
| `http` | التواصل مع API |
| `flutter_secure_storage` | حفظ tokens بأمان |
| `shared_preferences` | حفظ الإعدادات |
| `provider` | إدارة الحالة |
| `url_launcher` | فتح روابط Google Maps |
| `permission_handler` | طلب الصلاحيات |

---

## 🔐 الصلاحيات المطلوبة (Android)

- `RECORD_AUDIO` — التسجيل الصوتي
- `ACCESS_FINE_LOCATION` — تحديد GPS الدقيق
- `INTERNET` — التواصل مع الخادم
- `READ/WRITE_EXTERNAL_STORAGE` — حفظ ملفات Excel

---

## 🏗️ هيكل المشروع

```
lib/
├── main.dart                    # نقطة الدخول
├── config.dart                  # إعدادات التطبيق
├── models/models.dart           # نماذج البيانات
├── services/
│   ├── auth_service.dart        # JWT Auth
│   └── api_service.dart         # جميع API calls
├── screens/
│   ├── login_screen.dart        # شاشة تسجيل الدخول
│   ├── home_screen.dart         # الشاشة الرئيسية
│   ├── tafrigh_screen.dart      # 🏙 التفريغ
│   ├── field_check_screen.dart  # 🔍 التشيك الميداني
│   ├── faroz_screen.dart        # ✅ الفرز
│   ├── settings_screen.dart     # ⚙ الإعدادات
│   └── admin_screen.dart        # 🛡️ Admin
└── widgets/common_widgets.dart  # مكونات مشتركة
```

---

## 🌐 البناء عبر Codemagic (بدون تثبيت Flutter)

1. ارفع المشروع على GitHub
2. سجّل في [codemagic.io](https://codemagic.io)
3. اربط الـ repo واختر Flutter
4. اضغط Build — ستحصل على APK في بضع دقائق

---

## ⚡ بناء APK عبر GitHub Actions

أضف ملف `.github/workflows/build.yml`:

```yaml
name: Build APK
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v3
        with:
          name: apk
          path: build/app/outputs/flutter-apk/app-release.apk
```

---

## 📝 ملاحظات

- الصوت يُسجَّل بصيغة AAC (m4a) وهي مدعومة من Gemini API
- الجلسة تُحفظ تلقائياً — لا تحتاج تسجيل دخول في كل مرة
- بيانات الجدول تُحفظ محلياً على الجهاز
