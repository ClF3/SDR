import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Play, Radio, Square, Volume2, VolumeX, Waves, Wifi } from "lucide-react";
import {
  LocalSpectrumCanvas,
  MAX_FREQ,
  MIN_FREQ,
  WidebandWaterfallCanvas,
  clampFrequency,
  clampFrequencyRange,
  formatFrequency,
  type LocalSpectrum,
  type SpectrumMessage,
  type WidebandPsd
} from "./spectrum";
import "./styles.css";

type Status = {
  connected: boolean;
  device_host?: string;
  device_status?: {
    adc?: { peak_dbfs: number; rms_dbfs: number; or_count: number; clip_count: number };
    frontend?: Record<string, unknown>;
  };
  rx?: Record<string, unknown>;
  psd?: Record<string, unknown>;
  streams?: Record<string, {
    packets: number;
    lost_packets: number;
    timestamp_gaps: number;
    adc_or_count: number;
    fifo_overflow_count: number;
  }>;
  last_error?: string | null;
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

function App() {
  const [host, setHost] = useState("127.0.0.1");
  const [frequency, setFrequency] = useState(98500000);
  const [mode, setMode] = useState("WFM");
  const [rate, setRate] = useState(1000000);
  const [bandwidth, setBandwidth] = useState(250000);
  const [attenuator, setAttenuator] = useState(10);
  const [lna, setLna] = useState("bypass");
  const [status, setStatus] = useState<Status | null>(null);
  const [wideband, setWideband] = useState<WidebandPsd | null>(null);
  const [localSpectrum, setLocalSpectrum] = useState<LocalSpectrum | null>(null);
  const [log, setLog] = useState("idle");
  const [audioEnabled, setAudioEnabled] = useState(false);
  const [audioVolume, setAudioVolume] = useState(0.8);
  const audioContextRef = useRef<AudioContext | null>(null);
  const audioSocketRef = useRef<WebSocket | null>(null);
  const gainNodeRef = useRef<GainNode | null>(null);
  const psdRangeTimerRef = useRef<number | null>(null);

  useEffect(() => {
    api("/api/status").then(setStatus).catch(() => undefined);
    const ws = new WebSocket(`${wsBase()}/ws/status`);
    ws.onmessage = (event) => setStatus(JSON.parse(event.data));
    return () => ws.close();
  }, []);

  useEffect(() => {
    const ws = new WebSocket(`${wsBase()}/ws/spectrum`);
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data) as SpectrumMessage;
      if (message.type === "wideband_psd") setWideband(message);
      if (message.type === "local_spectrum") setLocalSpectrum(message);
    };
    return () => ws.close();
  }, []);

  useEffect(() => {
    if (gainNodeRef.current) {
      gainNodeRef.current.gain.value = audioEnabled ? audioVolume : 0;
    }
  }, [audioEnabled, audioVolume]);

  useEffect(() => {
    return () => {
      if (psdRangeTimerRef.current !== null) {
        window.clearTimeout(psdRangeTimerRef.current);
      }
      closeAudio();
    };
  }, []);

  async function connect() {
    setLog("connecting");
    await api("/api/device/connect", { host });
    await api("/api/frontend", { attenuator_db: attenuator, lna, filter: "LPF_108M" });
    setLog("connected");
  }

  async function startRx(nextFrequency = frequency) {
    const tunedFrequency = clampFrequency(nextFrequency);
    await api("/api/rx", {
      stream_id: 0,
      adc_channel: 0,
      frequency_hz: tunedFrequency,
      mode,
      iq_sample_rate_hz: rate,
      bandwidth_hz: bandwidth,
      sample_format: "SC16_LE",
      enable: true
    });
    setFrequency(tunedFrequency);
    setLog(`rx ${formatFrequency(tunedFrequency)}`);
  }

  async function setPsdRange(startFrequencyHz = MIN_FREQ, stopFrequencyHz = MAX_FREQ) {
    const [start, stop] = clampFrequencyRange(startFrequencyHz, stopFrequencyHz);
    await api("/api/psd", {
      enable: true,
      start_frequency_hz: start,
      stop_frequency_hz: stop
    });
    setLog(`psd ${formatFrequency(start)}-${formatFrequency(stop)}`);
  }

  function requestPsdRange(startFrequencyHz: number, stopFrequencyHz: number) {
    const [start, stop] = clampFrequencyRange(startFrequencyHz, stopFrequencyHz);
    if (psdRangeTimerRef.current !== null) {
      window.clearTimeout(psdRangeTimerRef.current);
    }
    psdRangeTimerRef.current = window.setTimeout(() => {
      psdRangeTimerRef.current = null;
      setPsdRange(start, stop).catch((error) => setLog(String(error)));
    }, 120);
    setLog(`zoom ${formatFrequency(start)}-${formatFrequency(stop)}`);
  }

  async function stopRx() {
    await api("/api/stop", {});
    setLog("stopped");
  }

  function closeAudio() {
    audioSocketRef.current?.close();
    audioSocketRef.current = null;
    gainNodeRef.current = null;
    const context = audioContextRef.current;
    audioContextRef.current = null;
    if (context && context.state !== "closed") {
      void context.close();
    }
  }

  async function toggleAudio() {
    if (audioEnabled) {
      closeAudio();
      setAudioEnabled(false);
      setLog("audio muted");
      return;
    }

    const AudioCtor = window.AudioContext || (window as typeof window & { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    const context = new AudioCtor({ sampleRate: 48000 });
    await context.audioWorklet.addModule("/audio-worklet.js");
    const node = new AudioWorkletNode(context, "pcm-player", { outputChannelCount: [1] });
    const gain = context.createGain();
    gain.gain.value = audioVolume;
    node.connect(gain).connect(context.destination);
    const ws = new WebSocket(`${wsBase()}/ws/audio`);
    ws.binaryType = "arraybuffer";
    ws.onmessage = (event) => node.port.postMessage(event.data, [event.data]);
    ws.onclose = () => {
      if (audioSocketRef.current === ws) {
        audioSocketRef.current = null;
        setAudioEnabled(false);
      }
    };
    await context.resume();
    audioContextRef.current = context;
    audioSocketRef.current = ws;
    gainNodeRef.current = gain;
    setAudioEnabled(true);
    setLog("audio enabled");
  }

  const stream0 = status?.streams?.["0"];
  const adc = status?.device_status?.adc;
  const psdSpan = wideband ? wideband.stop_frequency_hz - wideband.start_frequency_hz : MAX_FREQ - MIN_FREQ;

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
        <button onClick={() => startRx()}><Play size={16} /> Start RX</button>
        <button onClick={() => setPsdRange()}><Waves size={16} /> Full Band</button>
        <button onClick={stopRx}><Square size={16} /> Stop</button>
        <button onClick={toggleAudio}>
          {audioEnabled ? <VolumeX size={16} /> : <Volume2 size={16} />}
          {audioEnabled ? "Mute" : "Audio"}
        </button>
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
        <label>
          Volume
          <input
            type="range"
            min="0"
            max="1"
            step="0.01"
            value={audioVolume}
            onChange={(event) => setAudioVolume(Number(event.target.value))}
          />
        </label>
      </section>

      <section className="metrics">
        <div><span>ADC peak</span><strong>{adc?.peak_dbfs?.toFixed?.(1) ?? "--"} dBFS</strong></div>
        <div><span>ADC RMS</span><strong>{adc?.rms_dbfs?.toFixed?.(1) ?? "--"} dBFS</strong></div>
        <div><span>OR</span><strong>{adc?.or_count ?? 0}</strong></div>
        <div><span>Packets</span><strong>{stream0?.packets ?? 0}</strong></div>
        <div><span>Lost</span><strong>{stream0?.lost_packets ?? 0}</strong></div>
        <div><span>FIFO</span><strong>{stream0?.fifo_overflow_count ?? 0}</strong></div>
        <div><span>PSD frame</span><strong>{String(status?.psd?.frame_seq ?? "--")}</strong></div>
        <div><span>PSD span</span><strong>{formatFrequency(psdSpan)}</strong></div>
        <div><span>PSD bin</span><strong>{wideband ? formatFrequency(wideband.bin_spacing_hz) : "--"}</strong></div>
        <div><span>Audio</span><strong>{audioEnabled ? `${Math.round(audioVolume * 100)}%` : "off"}</strong></div>
      </section>

      <WidebandWaterfallCanvas
        psd={wideband}
        frequency={frequency}
        bandwidth={bandwidth}
        onTune={(nextFrequency) => {
          startRx(nextFrequency).catch((error) => setLog(String(error)));
        }}
        onRangeChange={requestPsdRange}
      />
      <LocalSpectrumCanvas spectrum={localSpectrum} />

      <footer>
        <span>{log}</span>
        <span>{status?.last_error ?? ""}</span>
      </footer>
    </main>
  );
}

createRoot(document.getElementById("root")!).render(<App />);
