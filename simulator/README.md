# Simulator

Local simulators for Raspberry Pi development without the AC920/FPGA hardware
online.

Run the fake AC920:

```sh
python -m fake_ac920 --scenario wfm_tone --bind 127.0.0.1
```

Supported scenarios:

- `tone`
- `am_tone`
- `ssb_tone`
- `nfm_tone`
- `wfm_tone`
- `noise`

