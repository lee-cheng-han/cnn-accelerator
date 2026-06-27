import vitis

client = vitis.create_client()
client.set_workspace(path="build/vitis_ws")

app = client.get_component(name="cnn_baremetal")
app.build()

print("Rebuilt cnn_baremetal")
