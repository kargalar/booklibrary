<div align="center">
  <img src="assets/logo/logo.png" width="96" alt="Book Library app icon" />

# Book Library

**A thoughtful home for the books you own and the ones you are reading.**

Organize your collection, keep notes and favorite quotes, and continue reading across devices.

[![Android](https://img.shields.io/badge/Android-APK-3DDC84?logo=android&logoColor=white)](https://github.com/kargalar/booklibrary/releases/latest) [![Windows](https://img.shields.io/badge/Windows-x64-0078D4?logo=windows&logoColor=white)](https://github.com/kargalar/booklibrary/releases/latest) [![Release](https://img.shields.io/github/v/release/kargalar/booklibrary?color=E0A458)](https://github.com/kargalar/booklibrary/releases/latest) [![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

[Download the latest release ↓](https://github.com/kargalar/booklibrary/releases/latest) · [Build from source](#build-from-source) · [Report an issue](https://github.com/kargalar/booklibrary/issues)

</div>

![A sample book page with reading notes, quotes, and ratings](docs/screenshots/book-library-details.png)

## Keep your reading life in one place

Track the books you own, the ones you are reading, and the titles you want to find next. Add notes, save passages, rate books, and keep your reading progress close at hand.

![The note editor with a fictional sample entry](docs/screenshots/book-library-note-editor.png)

## Features

- Organize books with reading status, ratings, notes, quotes, and tags.
- Search and compare book details from supported catalog providers.
- Read PDF and EPUB books and listen to audiobooks in the app.
- Track reading progress, loans, purchases, and library statistics.
- Sync your library across Android and Windows with Firebase.
- Share libraries and reading activity with friends.

## Download

Get the latest Android APK or Windows x64 package from [GitHub Releases](https://github.com/kargalar/booklibrary/releases/latest). The Windows download is a ZIP containing the application executable and its required runtime files.

## Build from source

Install [Flutter](https://docs.flutter.dev/get-started/install), the Android SDK, and Visual Studio with the Desktop development with C++ workload for Windows builds. Configure a Firebase project for Authentication, Cloud Firestore, and Cloud Storage, then generate the platform options with the FlutterFire CLI. Set `GOOGLE_BOOKS_API_KEY` to a key restricted to the Google Books API when you want ISBN lookups from Google Books. Keep OAuth credentials, service account files, and provider API tokens in local ignored configuration or Firebase Secret Manager.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build windows --release
```

The `functions` directory contains the optional Hardcover metadata lookup service. It requires Node.js 20 and a `HARDCOVER_API_TOKEN` secret configured in Firebase Functions.

## License

Book Library is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
