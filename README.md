# SDR

Monorepo for a 0.5 MHz to 108 MHz direct-sampling SDR system.

The repository is organized around the hardware/software boundary:

- `common/`: shared protocol definitions, schemas, and test vectors
- `docs/`: system design, protocol notes, bring-up plans, and RF notes
- `fpga/`: AC920 PL RTL, testbenches, constraints, and Vivado scripts
- `ps/`: AC920 PS-side firmware or Linux application code
- `rpi/`: Raspberry Pi backend service, web frontend, and systemd unit files
- `simulator/`: fake AC920 data/control sources for Raspberry Pi development
- `tools/`: developer utilities for capture, packet inspection, and analysis
- `tests/`: protocol and integration test assets

The first implementation target is a single receive stream:

- ACFL3432/CM3432 ADC at 250 MSPS
- FPGA DDC and decimation
- UDP SC16 IQ stream
- TCP control plane
- Raspberry Pi demodulation and WebSDR UI

## First Software Loop

Run a local development loop with the fake AC920:

```sh
python -m fake_ac920 --scenario wfm_tone --bind 127.0.0.1
python -m sdr_backend --config rpi/backend/config/dev.yaml
```

Then start the browser UI from `rpi/frontend`:

```sh
npm install
npm run dev
```
