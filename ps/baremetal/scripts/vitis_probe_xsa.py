import inspect
import os

import vitis

REPO = "C:/Users/86135/Desktop/SDR"
XSA = REPO + "/fpga/build/ac920_vendor_sdr/ac920_sdr.xsa"
WORKSPACE = REPO + "/fpga/build/ac920_vendor_sdr/vitis_probe_xsa_ws"

client = vitis.create_client(workspace=WORKSPACE)
print("workspace:", client.get_workspace())
print("xsa exists:", os.path.exists(XSA), XSA)

print("processor/os list:")
try:
    print(client.get_processor_os_list(xsa=XSA))
except Exception as exc:
    print("get_processor_os_list failed:", repr(exc))

for template_type in ["EMBD_APP", "ACCL_APP"]:
    print("templates", template_type)
    try:
        templates = client.get_templates(type=template_type)
        for template in templates:
            print(" ", template)
    except Exception as exc:
        print(" failed:", repr(exc))

vitis.dispose()
