import inspect

import vitis

print("vitis module:", vitis)
print("vitis attrs:")
for name in dir(vitis):
    if not name.startswith("_"):
        attr = getattr(vitis, name)
        print(" ", name, type(attr))
        if callable(attr):
            try:
                print("    sig:", inspect.signature(attr))
            except Exception as exc:
                print("    sig: <unavailable>", exc)

print("creating client...")
client = vitis.create_client(workspace="C:/Users/86135/Desktop/SDR/fpga/build/ac920_vendor_sdr/vitis_probe_ws")
print("client:", client)
print("client attrs:")
for name in dir(client):
    if not name.startswith("_"):
        attr = getattr(client, name)
        print(" ", name, type(attr))
        if callable(attr):
            try:
                print("    sig:", inspect.signature(attr))
            except Exception as exc:
                print("    sig: <unavailable>", exc)
vitis.dispose()
