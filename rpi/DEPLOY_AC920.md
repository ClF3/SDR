# Raspberry Pi AC920 Deployment

This is the Milestone 1 deployment path for a direct Ethernet link:

- Raspberry Pi: `192.168.10.1/24`
- AC920 PS: `192.168.10.2/24`
- TCP control: `9000`
- UDP IQ: `9001`
- UDP PSD: `9002` reserved, disabled for now
- UDP status: `9003`

## Raspberry Pi Network

On Raspberry Pi OS with NetworkManager:

```bash
sudo nmcli con add type ethernet ifname eth0 con-name ac920-static \
  ipv4.method manual ipv4.addresses 192.168.10.1/24 ipv4.never-default yes \
  ipv6.method disabled
sudo nmcli con up ac920-static
```

If the image uses `dhcpcd`, add this to `/etc/dhcpcd.conf` instead:

```text
interface eth0
static ip_address=192.168.10.1/24
```

Then reboot or restart networking.

## Backend And Frontend

From the repo root on the Raspberry Pi:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r rpi/backend/requirements.txt
cd rpi/frontend
npm ci
npm run build
cd ../..
```

Run manually first:

```bash
PYTHONPATH=$PWD:$PWD/rpi/backend \
  .venv/bin/python -m sdr_backend --config rpi/backend/config/ac920_hardware.yaml
```

Open `http://192.168.10.1:8080/` from a browser on the same network. The backend
serves the built frontend from `rpi/frontend/dist`.

## systemd

Install and enable the hardware service:

```bash
sudo cp rpi/service/sdr_backend_ac920.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sdr_backend_ac920.service
sudo journalctl -u sdr_backend_ac920.service -f
```

## Board Probe

After the FPGA bitstream and PS app are booted on AC920:

```bash
ping 192.168.10.2
nc -vz 192.168.10.2 9000
python3 tools/network_probe.py 192.168.10.2 --skip-psd --destination-ip 192.168.10.1
```

Expected Milestone 1 result:

- `hello` and `ping` pass over TCP
- status JSON arrives on UDP `9003`
- IQ packets arrive on UDP `9001`
- `--skip-psd` is required until the FPGA/PS PSD path is implemented

## Vivado/Vitis Reminder

Programming only a `.bit` over Vivado configures PL but does not start the PS
network service. For Ethernet bring-up, boot AC920 from SD with `BOOT.BIN`
containing FSBL/PMUFW, bitstream, and the Vitis lwIP bridge ELF.
