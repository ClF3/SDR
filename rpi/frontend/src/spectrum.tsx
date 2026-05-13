import React, { useEffect, useRef, useState } from "react";

export const MIN_FREQ = 500000;
export const MAX_FREQ = 108000000;
export const MIN_ZOOM_SPAN_HZ = 100000;

export type LocalSpectrum = {
  type: "local_spectrum";
  center_frequency_hz: number;
  sample_rate_hz: number;
  bin_spacing_hz: number;
  bins_dbfs: number[];
  flags?: number;
};

export type WidebandPsd = {
  type: "wideband_psd";
  psd_id: number;
  frame_seq: number;
  start_frequency_hz: number;
  stop_frequency_hz: number;
  bin_spacing_hz: number;
  bins_dbfs: number[];
  flags?: number;
  dropped_frame_count?: number;
  missing_segment_count?: number;
};

export type SpectrumMessage = LocalSpectrum | WidebandPsd;

export function clampFrequency(value: number) {
  return Math.max(MIN_FREQ, Math.min(MAX_FREQ, Math.round(value)));
}

export function clampFrequencyRange(start: number, stop: number) {
  const span = Math.max(MIN_ZOOM_SPAN_HZ, Math.min(MAX_FREQ - MIN_FREQ, stop - start));
  let nextStart = Math.round(start);
  let nextStop = Math.round(nextStart + span);
  if (nextStart < MIN_FREQ) {
    nextStart = MIN_FREQ;
    nextStop = Math.round(nextStart + span);
  }
  if (nextStop > MAX_FREQ) {
    nextStop = MAX_FREQ;
    nextStart = Math.round(nextStop - span);
  }
  return [nextStart, nextStop] as const;
}

export function formatFrequency(value: number) {
  if (value >= 1000000) return `${(value / 1000000).toFixed(3)} MHz`;
  return `${(value / 1000).toFixed(1)} kHz`;
}

export function LocalSpectrumCanvas({ spectrum }: { spectrum: LocalSpectrum | null }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !spectrum) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const width = canvas.width;
    const height = canvas.height;
    const bins = spectrum.bins_dbfs;

    ctx.fillStyle = "#101316";
    ctx.fillRect(0, 0, width, height);
    ctx.strokeStyle = "#6ee7b7";
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    bins.forEach((value, index) => {
      const x = (index / Math.max(bins.length - 1, 1)) * width;
      const y = height - Math.max(0, Math.min(1, (value + 110) / 90)) * height;
      if (index === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();

    ctx.fillStyle = "#9aa5ad";
    ctx.font = "24px system-ui";
    ctx.fillText(`Local ${formatFrequency(spectrum.center_frequency_hz)}`, 18, 34);
  }, [spectrum]);

  return <canvas className="spectrum local" width={1000} height={180} ref={canvasRef} />;
}

type WidebandProps = {
  psd: WidebandPsd | null;
  frequency: number;
  bandwidth: number;
  onTune: (frequency: number) => void;
  onRangeChange: (startFrequencyHz: number, stopFrequencyHz: number) => void;
};

export function WidebandWaterfallCanvas({
  psd,
  frequency,
  bandwidth,
  onTune,
  onRangeChange
}: WidebandProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const waterfallRef = useRef<ImageData | null>(null);
  const baseImageRef = useRef<ImageData | null>(null);
  const lastFrameSeqRef = useRef<number | null>(null);
  const lastRangeRef = useRef<string | null>(null);
  const [cursor, setCursor] = useState<number | null>(frequency);
  const [dragging, setDragging] = useState(false);

  useEffect(() => {
    setCursor(frequency);
  }, [frequency]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !psd) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const width = canvas.width;
    const height = canvas.height;
    const traceHeight = 96;
    const rulerHeight = 32;
    const wfTop = traceHeight + rulerHeight;
    const bins = psd.bins_dbfs;
    const rangeKey = `${psd.start_frequency_hz}:${psd.stop_frequency_hz}`;
    if (lastRangeRef.current !== rangeKey) {
      ctx.fillStyle = "#101316";
      ctx.fillRect(0, 0, width, height);
      waterfallRef.current = null;
      baseImageRef.current = null;
      lastFrameSeqRef.current = null;
      lastRangeRef.current = rangeKey;
    }

    if (lastFrameSeqRef.current !== psd.frame_seq) {
      ctx.fillStyle = "#101316";
      ctx.fillRect(0, 0, width, traceHeight + rulerHeight);
      drawTrace(ctx, bins, width, traceHeight);
      drawRuler(ctx, psd.start_frequency_hz, psd.stop_frequency_hz, width, traceHeight);

      const prev = waterfallRef.current;
      if (prev) ctx.putImageData(prev, 0, wfTop + 1);
      ctx.putImageData(rowFromBins(ctx, bins, width), 0, wfTop);
      waterfallRef.current = ctx.getImageData(0, wfTop, width, height - wfTop - 1);
      baseImageRef.current = ctx.getImageData(0, 0, width, height);
      lastFrameSeqRef.current = psd.frame_seq;
    } else if (baseImageRef.current) {
      ctx.putImageData(baseImageRef.current, 0, 0);
    }
    drawOverlay(ctx, psd, cursor ?? frequency, frequency, bandwidth, width, height);
  }, [psd, frequency, bandwidth, cursor]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      event.stopPropagation();
      applyWheelZoom(event.clientX, event.deltaX, event.deltaY, event.shiftKey);
    };
    canvas.addEventListener("wheel", onWheel, { passive: false });
    return () => canvas.removeEventListener("wheel", onWheel);
  }, [psd, onRangeChange]);

  function eventFrequency(event: React.PointerEvent<HTMLCanvasElement>) {
    const canvas = canvasRef.current;
    if (!canvas || !psd) return frequency;
    const rect = canvas.getBoundingClientRect();
    const x = Math.max(0, Math.min(rect.width, event.clientX - rect.left));
    const fraction = x / Math.max(rect.width, 1);
    return clampFrequency(psd.start_frequency_hz + fraction * (psd.stop_frequency_hz - psd.start_frequency_hz));
  }

  function applyWheelZoom(clientX: number, deltaX: number, deltaY: number, shiftKey: boolean) {
    if (!psd) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const x = Math.max(0, Math.min(rect.width, clientX - rect.left));
    const fraction = x / Math.max(rect.width, 1);
    const start = psd.start_frequency_hz;
    const stop = psd.stop_frequency_hz;
    const span = stop - start;
    let nextStart = start;
    let nextStop = stop;

    if (shiftKey || Math.abs(deltaX) > Math.abs(deltaY)) {
      const shiftPixels = deltaX || deltaY;
      const shiftHz = (shiftPixels / Math.max(rect.width, 1)) * span;
      nextStart = start + shiftHz;
      nextStop = stop + shiftHz;
    } else {
      const zoomFactor = deltaY < 0 ? 0.72 : 1.38;
      const nextSpan = span * zoomFactor;
      const center = start + fraction * span;
      nextStart = center - fraction * nextSpan;
      nextStop = nextStart + nextSpan;
    }

    const [clampedStart, clampedStop] = clampFrequencyRange(nextStart, nextStop);
    if (Math.abs(clampedStart - start) > 1 || Math.abs(clampedStop - stop) > 1) {
      onRangeChange(clampedStart, clampedStop);
    }
  }

  function pointerDown(event: React.PointerEvent<HTMLCanvasElement>) {
    if (!psd) return;
    event.preventDefault();
    event.stopPropagation();
    const next = eventFrequency(event);
    setDragging(true);
    setCursor(next);
    event.currentTarget.setPointerCapture(event.pointerId);
  }

  function pointerMove(event: React.PointerEvent<HTMLCanvasElement>) {
    if (!dragging || !psd) return;
    event.preventDefault();
    event.stopPropagation();
    setCursor(eventFrequency(event));
  }

  function pointerUp(event: React.PointerEvent<HTMLCanvasElement>) {
    if (!psd) return;
    event.preventDefault();
    event.stopPropagation();
    const next = eventFrequency(event);
    setDragging(false);
    setCursor(next);
    onTune(next);
    event.currentTarget.releasePointerCapture(event.pointerId);
  }

  return (
    <canvas
      className="spectrum wideband"
      width={1200}
      height={420}
      ref={canvasRef}
      onPointerDown={pointerDown}
      onPointerMove={pointerMove}
      onPointerUp={pointerUp}
      onPointerCancel={() => setDragging(false)}
      onContextMenu={(event) => event.preventDefault()}
    />
  );
}

function drawTrace(ctx: CanvasRenderingContext2D, bins: number[], width: number, height: number) {
  ctx.strokeStyle = "#8dd8ff";
  ctx.lineWidth = 1.25;
  ctx.beginPath();
  bins.forEach((value, index) => {
    const x = (index / Math.max(bins.length - 1, 1)) * width;
    const y = height - Math.max(0, Math.min(1, (value + 110) / 90)) * height;
    if (index === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.stroke();
}

function drawRuler(
  ctx: CanvasRenderingContext2D,
  start: number,
  stop: number,
  width: number,
  top: number
) {
  ctx.strokeStyle = "#303842";
  ctx.fillStyle = "#9aa5ad";
  ctx.font = "14px system-ui";
  for (let i = 0; i <= 8; i++) {
    const x = (i / 8) * width;
    const freq = start + (i / 8) * (stop - start);
    ctx.beginPath();
    ctx.moveTo(x, top);
    ctx.lineTo(x, top + 10);
    ctx.stroke();
    ctx.fillText(formatFrequency(freq), Math.min(width - 76, x + 6), top + 22);
  }
}

function rowFromBins(ctx: CanvasRenderingContext2D, bins: number[], width: number) {
  const row = ctx.createImageData(width, 1);
  for (let x = 0; x < width; x++) {
    const bin = bins[Math.floor((x / width) * bins.length)] ?? -120;
    const level = Math.max(0, Math.min(1, (bin + 105) / 75));
    row.data[x * 4 + 0] = Math.floor(20 + level * 230);
    row.data[x * 4 + 1] = Math.floor(58 + level * 170);
    row.data[x * 4 + 2] = Math.floor(105 + (1 - level) * 90);
    row.data[x * 4 + 3] = 255;
  }
  return row;
}

function drawOverlay(
  ctx: CanvasRenderingContext2D,
  psd: WidebandPsd,
  cursor: number,
  tuned: number,
  bandwidth: number,
  width: number,
  height: number
) {
  const span = psd.stop_frequency_hz - psd.start_frequency_hz;
  if (span <= 0) return;
  const clampedCursor = Math.max(psd.start_frequency_hz, Math.min(psd.stop_frequency_hz, cursor));
  const tunedX = ((tuned - psd.start_frequency_hz) / span) * width;
  const cursorX = ((clampedCursor - psd.start_frequency_hz) / span) * width;
  const bwPx = Math.max(2, (bandwidth / span) * width);

  if (tuned >= psd.start_frequency_hz && tuned <= psd.stop_frequency_hz) {
    ctx.fillStyle = "rgba(110, 231, 183, 0.14)";
    ctx.fillRect(tunedX - bwPx / 2, 0, bwPx, height);
    ctx.strokeStyle = "#6ee7b7";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(tunedX, 0);
    ctx.lineTo(tunedX, height);
    ctx.stroke();
  }

  ctx.strokeStyle = "#ffd166";
  ctx.beginPath();
  ctx.moveTo(cursorX, 0);
  ctx.lineTo(cursorX, height);
  ctx.stroke();
  ctx.fillStyle = "#ffd166";
  ctx.font = "15px system-ui";
  ctx.fillText(formatFrequency(clampedCursor), Math.min(width - 96, cursorX + 8), 24);
}
