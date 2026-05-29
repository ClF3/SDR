# Raspberry Pi

Raspberry Pi software for the WebSDR service.

Contents:

- `backend/`: device communication, DSP, audio, waterfall, and web API
- `frontend/`: browser UI
- `service/`: systemd service files and deployment notes

For real AC920 hardware, use `backend/config/ac920_hardware.yaml` and follow
`DEPLOY_AC920.md`. That profile connects to `192.168.10.2`, disables hardware
PSD for Milestone 1, and lets the backend serve the built frontend directly
from `frontend/dist`.
