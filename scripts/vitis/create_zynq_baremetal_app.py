import os
import shutil
from pathlib import Path
import vitis

root = Path(os.getcwd())
workspace = root / "build" / "vitis_ws"
xsa_file = root / "build" / "arty_z7_20_cnn" / "arty_z7_20_cnn.xsa"

platform_name = "arty_z7_20_cnn_platform"
app_name = "cnn_baremetal"
domain_name = "standalone_domain"

print("Workspace:", workspace)
print("XSA:", xsa_file)

if not xsa_file.exists():
    raise FileNotFoundError(f"Missing XSA: {xsa_file}")

client = vitis.create_client()
client.set_workspace(path=str(workspace))

platform = client.create_platform_component(
    name=platform_name,
    hw_design=str(xsa_file),
    os="standalone",
    cpu="ps7_cortexa9_0",
    domain_name=domain_name,
)

platform.build()

xpfm = workspace / platform_name / "export" / platform_name / f"{platform_name}.xpfm"
print("XPFM:", xpfm)

app = client.create_app_component(
    name=app_name,
    platform=str(xpfm),
    domain=domain_name,
    template="hello_world",
)

app_src_dir = workspace / app_name / "src"
src_main = root / "software" / "zynq_baremetal" / "main.c"
dst_main = app_src_dir / "main.c"
dst_hello = app_src_dir / "helloworld.c"
user_config = app_src_dir / "UserConfig.cmake"

if not src_main.exists():
    raise FileNotFoundError(f"Missing source file: {src_main}")

shutil.copyfile(src_main, dst_main)

# Vitis hello_world template uses UserConfig.cmake to choose app sources.
# Replace helloworld.c with our real main.c.
if user_config.exists():
    text = user_config.read_text()
    text = text.replace('"helloworld.c"', '"main.c"')
    user_config.write_text(text)
else:
    raise FileNotFoundError(f"Missing Vitis source config: {user_config}")

# Remove generated hello source after metadata is patched.
if dst_hello.exists():
    dst_hello.unlink()

# Remove leftover Hello World template helper if present.
hello_cmake = app_src_dir / "Hello_worldExample.cmake"
cmake_file = app_src_dir / "CMakeLists.txt"

if cmake_file.exists():
    text = cmake_file.read_text()
    text = text.replace("include(${CMAKE_CURRENT_SOURCE_DIR}/Hello_worldExample.cmake)\n", "")
    cmake_file.write_text(text)

if hello_cmake.exists():
    hello_cmake.unlink()

app.build()

elf = workspace / app_name / "build" / f"{app_name}.elf"

print("")
print("Vitis bare-metal app build done.")
print("ELF:")
print(elf)
print("")
