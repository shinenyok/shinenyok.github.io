# cotool

Flutter web toolbox for app icons, JSON-to-Dart models, document conversion, and LAN file transfer.

## Web Deploy

The site is deployed to GitHub Pages by `.github/workflows/deploy-pages.yml`.

## Music Proxy Trial

The music panel is loaded lazily from `web/music` using the small ♪ button at
the bottom right. Search and source requests use the authenticated Cloudflare
Worker in [`services/music-proxy`](services/music-proxy/README.md); audio plays
directly over HTTPS. See that guide for connection and compatibility details.

## Local Server

Some features need a local helper service, including LAN transfer and enhanced document conversion.

For development:

```bash
dart run tool/local_converter_server.dart
```

For users without a Dart environment, build a standalone executable:

```bash
dart compile exe tool/local_converter_server.dart -o build/cotool-local-server
```

Then run:

```bash
./build/cotool-local-server
```

The service starts on port `8787` by default and prints LAN URLs such as:

```text
http://192.168.x.x:8787/share
```

## Release Local Helper

`.github/workflows/build-local-server.yml` builds packaged local helpers for Linux, macOS, and Windows.

Run it manually from GitHub Actions for test artifacts, or create a tag to publish release assets:

```bash
git tag local-server-v1.0.1
git push origin local-server-v1.0.1
```
