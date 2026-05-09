# Raspberry Pi Backend

FastAPI backend for the Raspberry Pi WebSDR service.

## Development

Install the Python dependencies in a virtual environment:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e ".[dev]"
```

Run the fake AC920:

```sh
python -m fake_ac920 --scenario wfm_tone --bind 127.0.0.1
```

Run the backend:

```sh
python -m sdr_backend --config rpi/backend/config/dev.yaml
```

The backend listens on `http://127.0.0.1:8080` by default.

