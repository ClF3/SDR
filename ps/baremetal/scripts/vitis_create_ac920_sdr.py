import os
import shutil
import sys
import traceback

import vitis


def fail_hard(exc_type, exc, tb):
    traceback.print_exception(exc_type, exc, tb)
    try:
        vitis.dispose()
    except Exception:
        pass
    sys.exit(1)


sys.excepthook = fail_hard

REPO = os.environ.get("SDR_REPO_DIR", "C:/Users/86135/Desktop/SDR").replace("\\", "/")
XSA = os.environ.get(
    "AC920_XSA",
    REPO + "/fpga/build/ac920_vendor_sdr/ac920_sdr.xsa",
).replace("\\", "/")
WORKSPACE = os.environ.get(
    "AC920_VITIS_WORKSPACE",
    REPO + "/fpga/build/ac920_vendor_sdr/vitis_sdr",
).replace("\\", "/")
SDT_REPO = os.environ.get(
    "VITIS_SDT_REPO",
    "E:/vivadoref/Vivado/2024.2/data/embeddedsw",
).replace("\\", "/")

PLATFORM_NAME = "ac920_sdr_platform"
DOMAIN_NAME = "standalone_domain"
APP_NAME = "ac920_sdr_bridge"
CPU = "psu_cortexa53_0"

if not os.path.isfile(XSA):
    raise SystemExit("XSA does not exist: " + XSA)

if os.path.isdir(WORKSPACE):
    shutil.rmtree(WORKSPACE)

client = vitis.create_client(workspace=WORKSPACE)

print("AC920 Vitis: workspace", WORKSPACE)
print("AC920 Vitis: XSA", XSA)
print("AC920 Vitis: SDT repo", SDT_REPO)

advanced_options = client.create_advanced_options_dict(sdt_repo=SDT_REPO)

platform = client.create_platform_component(
    name=PLATFORM_NAME,
    hw_design=XSA,
    os="standalone",
    cpu=CPU,
    domain_name=DOMAIN_NAME,
    generate_dtb=False,
    advanced_options=advanced_options,
)
platform.report()
platform.list_domains()
standalone_domain = platform.get_domain(DOMAIN_NAME)
print("AC920 Vitis: enabling lwip220 in", DOMAIN_NAME)
standalone_domain.set_lib("lwip220")
platform_status = platform.build()
print("AC920 Vitis: platform build status", platform_status)

platform_export = WORKSPACE + "/" + PLATFORM_NAME + "/export/" + PLATFORM_NAME
if os.path.isdir(platform_export):
    client.add_platform_repos(platform_export)
    client.rescan_platform_repos(platform_export)

platform_xpfm = client.find_platform_in_repos(PLATFORM_NAME)
print("AC920 Vitis: platform xpfm", platform_xpfm)
if not platform_xpfm or not os.path.isfile(platform_xpfm):
    for root, _dirs, files in os.walk(WORKSPACE):
        for name in files:
            if name.endswith(".xpfm"):
                platform_xpfm = os.path.join(root, name).replace("\\", "/")
                print("AC920 Vitis: found platform xpfm by scan", platform_xpfm)
                break
        if platform_xpfm and os.path.isfile(platform_xpfm):
            break

if not platform_xpfm or not os.path.isfile(platform_xpfm):
    buildstatus = WORKSPACE + "/" + PLATFORM_NAME + "/export/.buildstatus"
    if os.path.isfile(buildstatus):
        with open(buildstatus, "r", encoding="utf-8", errors="replace") as f:
            print("AC920 Vitis: platform export status")
            print(f.read())
    raise SystemExit("Platform export did not produce an .xpfm file.")

app = client.create_app_component(
    name=APP_NAME,
    platform=platform_xpfm,
    domain=DOMAIN_NAME,
    template="empty_application",
)
app.report()

bridge_src = REPO + "/ps/baremetal/src"
vendor_src = REPO + "/fpga/build/ac920_vendor_sdr/vitis_classic/app_acfl3432/src"

app.import_files(
    from_loc=bridge_src,
    files=[
        "ac920_sdr_main.c",
        "sdr_control.c",
        "sdr_control.h",
        "sdr_hw.h",
        "sdr_hw_ac920.c",
        "sdr_hw_ac920.h",
        "sdr_regs.h",
    ],
    dest_dir_in_cmp="src",
)
app.import_files(
    from_loc=vendor_src,
    files=[
        "platform.c",
        "platform.h",
        "platform_config.h",
        "platform_zynqmp.c",
        "platform_zynq.c",
        "platform_mb.c",
        "iic_phyreset.c",
        "sfp.c",
        "si5324.c",
        "lscript.ld",
    ],
    dest_dir_in_cmp="src",
)

app.build()

print("AC920 Vitis: app component built")
vitis.dispose()
