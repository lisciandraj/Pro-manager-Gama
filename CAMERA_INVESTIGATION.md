# Camera investigation · 2026-09-12

The latest iPhone screenshot reaches the camera-stage NotAllowedError/SecurityError branch, before attaching a stream or loading ZXing. This distinguishes it from video playback denial but does not prove the user denied permission: browser/platform restrictions can return the same error.

Evidence:
- Compared scanner history through the September 6 security update, September 12 TMS/fulfillment and subsequent ERP updates. The getUserMedia constraints remained identical (rear-facing ideal, 1280×720 ideal, no audio). ERP changes added scan events and placement inside active dialogs; they did not replace camera access.
- Live GitHub Pages document response has HTTPS and no Permissions-Policy / Feature-Policy denying camera access. CSP originated in the September 6 security update, not the latest ERP updates; no speculative relaxation was made.
- Full index.html successfully starts a native browser MediaStream and produces live video frames in Chromium with a simulated hardware camera. This integration test leaves getUserMedia, video playback and CSP intact; only Supabase data and barcode decoding are substituted. It does not reproduce iPhone hardware or standalone WebKit behavior.
- Earlier scanner unit tests replaced getUserMedia and cannot establish real iOS camera availability.

Next discriminating evidence must come from the affected device. camera-check.html bypasses ERP scripts, scanner/decoder, CSP and the service-worker navigation cache. Explicit user buttons compare unconstrained video:true with the ERP rear-camera constraints. It reports exact error stage/name/message, secure context, standalone mode, top-level context, user activation and browser information. No images, device identifiers or diagnostic reports are uploaded.

If both isolated attempts fail, the issue also exists outside ERP code in this browser/session; test the same URL directly in Safari to isolate installed-app behavior. If only rear selection fails, adjust camera selection. If both work, compare the main scanner diagnostic and calling module; then investigate lifecycle/dialog/activation interactions. Root cause remains unconfirmed until this device result is available.
