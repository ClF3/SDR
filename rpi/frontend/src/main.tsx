import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Play, Radio, Square, Volume2, Wifi } from "lucide-react";
import "./styles.css";

type Status = {
  connected: boolean;
  device_host?: string;
  device_status?: {
    adc?: { peak_dbfs: number; rms_dbfs: number; or_count: number; clip_count: number };
    frontend?: Record<string, unknown>;
  };
  rx?: Record<string, unknown>;
  streams?: Record<string, {
    packets: number;
    lost_packets: number;
    timestamp_gaps: number;
    adc_or_count: number;
    fifo_overflow_count: number;
  }>;
  last_error?: string | null;
};

type Spectrum = {
  center_frequency_hz: number;
  sample_rate_hz: number;
  bin_spacing_hz: number;
  bins_dbfs: number[];
};

const modes = ["AM", "USB", "LSB", "CW", "NFM", "WFM"];
const rates = [125000, 250000, 500000, 1000000];

function backendHost() {
  if (location.port === "5173") {
    return `${location.hostname}:8080`;
  }
  return location.host;
}

function apiBase() {
  return `${location.protocol}//${backendHost()}`;
}

function wsBase() {
  return `${location.protocol === "https:" ? "wss" : "ws"}://${backendHost()}`;
}

function api(path: string, body?: unknown) {
  return fetch(`${apiBase()}${path}`, {
    method: body ? "POST" : "GET",
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined
  }).then((response) => {
    if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
    return response.json();
  });
}

function SpectrumCanvas({ spectrum }: { spectrum: Spectrum | null }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const waterfallRef = useRef<ImageData | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !spectrum) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const width = canvas.width;
    const height = canvas.height;
    const traceHeight = 110;
    const bins = spectrum.bins_dbfs;

    ctx.fillStyle = "#101316";
    ctx.fillRect(0, 0, width, traceHeight);
    ctx.strokeStyle = "#6ee7b7";
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    bins.forEach((value, index) => {
      const x = (index / Math.max(bins.length - 1, 1)) * width;
      const y = traceHeight - Math.max(0, Math.min(1, (value + 110) / 90)) * traceHeight;
      if (index === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();

    const wfTop = traceHeight + 8;
    const wfHeight = height - wfTop;
    const prev = waterfallRef.current;
    if (prev) ctx.putImageData(prev, 0, wfTop + 1);
    const row = ctx.createImageData(width, 1);
    for (let x = 0; x < width; x++) {
      const bin = bins[Math.floor((x / width) * bins.length)] ?? -120;
      const level = Math.max(0, Math.min(1, (bin + 105) / 75));
      row.data[x * 4 + 0] = Math.floor(30 + level * 220);
      row.data[x * 4 + 1] = Math.floor(70 + level * 160);
      row.data[x * 4 + 2] = Math.floor(95 + (1 - level) * 80);
      row.data[x * 4 + 3] = 255;
    }
    ctx.putImageData(row, 0, wfTop);
    waterfallRef.current = ctx.getImageData(0, wfTop, width, wfHeight - 1);
  }, [spectrum]);

  return <canvas className="spectrum" width={1000} height={360} ref={canvasRef} />;
}

function App() {
  const [host, setHost] = useState("127.0.0.1");
  const [frequency, setFrequency] = useState(98500000);
  const [mode, setMode] = useState("WFM");
  const [rate, setRate] = useState(1000000);
  const [bandwidth, setBandwidth] = useState(250000);
  const [attenuator, setAttenuator] = useState(10);
  const [lna, setLna] = useState("bypass");
  const [status, setStatus] = useState<Status | null>(null);
  const [spectrum, setSpectrum] = useState<Spectrum | null>(null);
  const [log, setLog] = useState("idle");
  const audioContextRef = useRef<AudioContext | null>(null);
  const audioSocketRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    api("/api/status").then(setStatus).catch(() => undefined);
    const ws = new WebSocket(`${wsBase()}/ws/status`);
    ws.onmessage = (event) => setStatus(JSON.parse(event.data));
    return () => ws.close();
  }, []);

  useEffect(() => {
    const ws = new WebSocket(`${wsBase()}/ws/spectrum`);
    ws.onmessage = (event) => setSpectrum(JSON.parse(event.data));
    return () => ws.close();
  }, []);

  async function connect() {
    setLog("connecting");
    await api("/api/device/connect", { host });
    await api("/api/frontend", { attenuator_db: attenuator, lna, filter: "LPF_108M" });
    setLog("connected");
  }

  async function startRx() {
    await api("/api/rx", {
      stream_id: 0,
      adc_channel: 0,
      frequency_hz: frequency,
      mode,
      iq_sample_rate_hz: rate,
      bandwidth_hz: bandwidth,
      sample_format: "SC16_LE",
      enable: true
    });
    setLog("rx running");
  }

  async function stopRx() {
    await api("/api/stop", {});
    setLog("stopped");
  }

  async function startAudio() {
    const AudioCtor = window.AudioContext || (window as typeof window & { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    const context = new AudioCtor({ sampleRate: 48000 });
    await context.audioWorklet.addModule("/audio-worklet.js");
    const node = new AudioWorkletNode(context, "pcm-player", { outputChannelCount: [1] });
    node.connect(context.destination);
    const ws = new WebSocket(`${wsBase()}/ws/audio`);
    ws.binaryType = "arraybuffer";
    ws.onmessage = (event) => node.port.postMessage(event.data, [event.data]);
    audioContextRef.current = context;
    audioSocketRef.current = ws;
    setLog("audio enabled");
  }

  const stream0 = status?.streams?.["0"];
  const adc = status?.device_status?.adc;

  return (
    <main>
      <header>
        <div>
          <h1>SDR Web Console</h1>
          <p>AC920 / ACFL3432 direct-sampling receiver</p>
        </div>
        <div className={status?.connected ? "pill ok" : "pill"}>
          <Wifi size={16} /> {status?.connected ? "connected" : "offline"}
        </div>
      </header>

      <section className="toolbar">
        <label>
          AC920 host
          <input value={host} onChange={(event) => setHost(event.target.value)} />
        </label>
        <button onClick={connect}><Radio size={16} /> Connect</button>
        <button onClick={startRx}><Play size={16} /> Start RX</button>
        <button onClick={stopRx}><Square size={16} /> Stop</button>
        <button onClick={startAudio}><Volume2 size={16} /> Audio</button>
      </section>

      <section className="controls">
        <label>
          Frequency Hz
          <input type="number" value={frequency} onChange={(event) => setFrequency(Number(event.target.value))} />
        </label>
        <label>
          Mode
          <select value={mode} onChange={(event) => setMode(event.target.value)}>
            {modes.map((item) => <option key={item}>{item}</option>)}
          </select>
        </label>
        <label>
          IQ rate
          <select value={rate} onChange={(event) => setRate(Number(event.target.value))}>
            {rates.map((item) => <option key={item} value={item}>{item}</option>)}
          </select>
        </label>
        <label>
          Bandwidth Hz
          <input type="number" value={bandwidth} onChange={(event) => setBandwidth(Number(event.target.value))} />
        </label>
        <label>
          Attenuator
          <select value={attenuator} onChange={(event) => setAttenuator(Number(event.target.value))}>
            {[0, 10, 20, 30].map((item) => <option key={item} value={item}>{item} dB</option>)}
          </select>
        </label>
        <label>
          LNA
          <select value={lna} onChange={(event) => setLna(event.target.value)}>
            <option value="bypass">bypass</option>
            <option value="on">on</option>
          </select>
        </label>
      </section>

      <section className="metrics">
        <div><span>ADC peak</span><strong>{adc?.peak_dbfs?.toFixed?.(1) ?? "--"} dBFS</strong></div>
        <div><span>ADC RMS</span><strong>{adc?.rms_dbfs?.toFixed?.(1) ?? "--"} dBFS</strong></div>
        <div><span>OR</span><strong>{adc?.or_count ?? 0}</strong></div>
        <div><span>Packets</span><strong>{stream0?.packets ?? 0}</strong></div>
        <div><span>Lost</span><strong>{stream0?.lost_packets ?? 0}</strong></div>
        <div><span>FIFO</span><strong>{stream0?.fifo_overflow_count ?? 0}</strong></div>
      </section>

      <SpectrumCanvas spectrum={spectrum} />

      <footer>
        <span>{log}</span>
        <span>{status?.last_error ?? ""}</span>
      </footer>
    </main>
  );
}

createRoot(document.getElementById("root")!).render(<App />);
