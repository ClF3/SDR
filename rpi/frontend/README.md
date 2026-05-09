# Raspberry Pi Frontend

React/Vite browser UI for frequency control, mode selection, audio, spectrum,
waterfall, and device status.

```sh
npm install
npm run dev
```

During development, Vite proxies `/api` and `/ws` to the backend on
`127.0.0.1:8080`. The current frontend also detects Vite port `5173` and talks
directly to the backend on the same hostname at port `8080`; restart Vite or
hard-refresh the browser after frontend code changes.
