# LiDAR Ground Mapper — GitHub Pages web app

A mobile-friendly, installable browser tool for inspecting an exported 3D mesh and extracting likely ground triangles. No backend, API key, or build step is required.

## Deploy on GitHub Pages

1. Create a GitHub repository (for example `lidar-ground-mapper`).
2. Upload **all files and folders inside this project** to the repository root. Make sure `index.html` is at the root, not inside an extra nested folder.
3. Commit to the `main` branch.
4. Open **Settings → Pages** and select **GitHub Actions** as the build/deployment source.
5. Wait for the `Deploy LiDAR Ground Mapper to GitHub Pages` workflow to finish. Open the URL shown in the workflow or under Settings → Pages.
6. On iPhone, open the URL in Safari. Use Share → Add to Home Screen if you want an app-like icon.

The workflow in `.github/workflows/pages.yml` deploys the repository root to Pages.

## Supported inputs

- OBJ mesh (`v` vertices and `f` polygon faces; triangulated on import)
- ASCII PLY mesh (binary PLY is not supported in this build)

## Features

- Local-only browser processing; files are not uploaded to a server.
- 3D preview with drag-to-rotate and pinch/scroll zoom.
- Local low-surface grid + upward-facing triangle heuristic for ground candidates.
- Adjustable ground tolerance, slope limit, and grid size.
- Export ground-only OBJ, ASCII PLY, and vertex CSV.
- Sample terrain with synthetic vertical vegetation for trying the UI.
- PWA manifest and service worker for app-like installation and offline shell caching.

## Important limitation: iPhone LiDAR

A GitHub Pages website running in iPhone Safari cannot use Apple's native ARKit scene-reconstruction API or directly access the native LiDAR mesh. This app therefore processes mesh files exported from a separate compatible scanner app. It does **not** perform live LiDAR capture itself.

## Filtering limitations

The filter keeps upward-facing triangles close to the lowest triangle centroid in each X/Z grid cell. It is a heuristic, not a trained vegetation classifier. It can remove legitimate sloping ground, keep low vegetation, and cannot reconstruct terrain fully hidden from the sensor. Units in exported files are preserved; the UI assumes the input coordinate units are metres when displaying centimetre settings. If the source file uses different units, adjust/convert it before filtering.

## Quick test

Open the app and choose **Load sample terrain**. Rotate/zoom the preview, click **Extract ground**, toggle Ground, and export OBJ/PLY/CSV. This tests the browser-side workflow without needing a scan file.
