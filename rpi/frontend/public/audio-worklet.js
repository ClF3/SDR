class PcmPlayerProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.queue = [];
    this.offset = 0;
    this.port.onmessage = (event) => {
      const data = event.data;
      if (data instanceof ArrayBuffer) {
        this.queue.push(new Int16Array(data));
        if (this.queue.length > 64) {
          this.queue.splice(0, this.queue.length - 64);
        }
      }
    };
  }

  process(_inputs, outputs) {
    const output = outputs[0][0];
    let idx = 0;
    while (idx < output.length) {
      if (this.queue.length === 0) {
        output[idx++] = 0;
        continue;
      }
      const frame = this.queue[0];
      output[idx++] = frame[this.offset++] / 32768.0;
      if (this.offset >= frame.length) {
        this.queue.shift();
        this.offset = 0;
      }
    }
    return true;
  }
}

registerProcessor("pcm-player", PcmPlayerProcessor);

