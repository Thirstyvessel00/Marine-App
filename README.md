
# WA Offshore Toolkit (RipCharts‑like)

**Purpose:** deliver a mobile app with functionality *similar* to RipCharts — SST, chlorophyll‑a, true color, altimetry/currents, wind and GPS/waypoints — focused on Western Australia. No code or content is copied; this app consumes open data via public APIs/WMS endpoints.

## Features in this build
- **Layer stack:** True‑color (Sentinel‑2 cloudless demo), GEBCO bathymetry, SST (IMOS), Chl‑a (IMOS), OSCAR currents (placeholder), plus wind arrows.
- **Time control:** slider for last 7 days; passed as `TIME=` to ncWMS layers (SST/Chl‑a).
- **Opacity sliders** for each overlay.
- **Waypoints:** long‑press to add, stored on device; delete via chips.
- **GPS locate** button (Android/iOS permissions required).

## Data sources wired
- **GEBCO** WMS: `https://wms.gebco.net/mapserv?` `GEBCO_LATEST`.
- **IMOS/AODN** ncWMS base: `https://geoserver-123.aodn.org.au/geoserver/ncwms?`
  - SST `srs_ghrsst_l3s_gm_1d_ngt_url/sea_surface_temperature`
  - Chl‑a `srs_oc_snpp_chl_gsm_url/chl_gsm`
- **OSCAR currents (NOAA ERDDAP WMS):** `https://coastwatch.pfeg.noaa.gov/erddap/wms/pmelOscar/request?` (set `Wms.oscarLayer` to a valid layer after checking GetCapabilities)
- **True color (demo):** EOX `s2cloudless-2021_3857` via `https://tiles.maps.eox.at/wms?`
- **Wind:** Open‑Meteo hourly API (no key, non‑commercial) — rendered as arrows.

## Build APK
```bash
flutter pub get
flutter run -d chrome   # quick test
flutter build apk --release
```
**Output:** `build/app/outputs/flutter-apk/app-release.apk`

## Notes
- Replace OSM demo tiles for production use. Add offline caching later (e.g., flutter_map_tile_caching).
- For altimetry/sea‑level anomaly with vectors, use Copernicus Marine (CMEMS) or IMOS OceanCurrent gridded products; add credentials and WMS URLs, then set `Wms.oscarLayer` or equivalent.
