"""Monitor USB presence and publish a StatusNotifierItem; never open input devices."""

import argparse
import asyncio
import logging
import socket

from dbus_next import Message, MessageType, PropertyAccess
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, dbus_property, method, signal
from PIL import Image, ImageDraw
import pyudev

ITEM_ID = "shared-input-indicator"
ITEM_PATH = "/StatusNotifierItem"
WATCHER = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"
DEVICES = {
    ("1532", "0084"),  # Razer DeathAdder V2
    ("24f0", "0140"),  # Das Keyboard
}


def is_connected(context):
    # Match USB devices, not their multiple HID interfaces. Other keyboards
    # (including security keys) and renumbered event nodes are irrelevant.
    present = set()
    for device in context.list_devices(subsystem="usb", DEVTYPE="usb_device"):
        try:
            present.add((device.attributes.asstring("idVendor").lower(),
                         device.attributes.asstring("idProduct").lower()))
        except (KeyError, OSError):
            # A device can vanish while an enumeration is in progress.
            continue
    return DEVICES.issubset(present)


def state_name(connected):
    return "connected" if connected else "disconnected"


def icon_pixmaps(state):
    """Use the entire tray icon for status, with a slash as a second visual cue."""
    pixmaps = []
    for size in (22, 32, 64):
        scale = 4
        image = Image.new("RGBA", (64 * scale, 64 * scale))
        draw = ImageDraw.Draw(image)
        def line(points, fill, width=3):
            draw.line([(x * scale, y * scale) for x, y in points], fill=fill,
                      width=width * scale, joint="curve")
        color = "#66e3a4" if state == "connected" else "#ff6b6b"
        ink = "#202428"
        draw.rounded_rectangle((2*scale, 7*scale, 62*scale, 57*scale),
                               radius=7*scale, fill=color)
        for y in (20, 30):
            for x in (12, 24, 36, 48):
                line([(x, y), (x+4, y)], ink, 5)
        line([(17, 44), (47, 44)], ink, 5)
        if state == "disconnected":
            line([(10, 53), (54, 11)], color, 13)
            line([(10, 53), (54, 11)], ink, 7)
        rgba = image.resize((size, size), Image.Resampling.LANCZOS).tobytes()
        # The protocol requires network-order ARGB, not RGBA or premultiplied pixels.
        argb = bytearray(len(rgba))
        argb[0::4], argb[1::4], argb[2::4], argb[3::4] = (
            rgba[3::4], rgba[0::4], rgba[1::4], rgba[2::4])
        pixmaps.append([size, size, bytes(argb)])
    return pixmaps


class InputIndicator(ServiceInterface):
    def __init__(self, connected, hostname=None):
        super().__init__("org.kde.StatusNotifierItem")
        self.connected = connected
        self.hostname = hostname or socket.gethostname()
        self.icons = {state: icon_pixmaps(state) for state in
                      ("connected", "disconnected")}

    def update(self, connected):
        if connected == self.connected:
            return
        self.connected = connected
        self.emit_properties_changed({"IconPixmap": self.IconPixmap, "ToolTip": self.ToolTip,
                                      "Title": self.Title})
        self.NewIcon()
        self.NewToolTip()
        self.NewTitle()

    @dbus_property(access=PropertyAccess.READ)
    def Category(self) -> 's':
        return "Hardware"

    @dbus_property(access=PropertyAccess.READ)
    def Id(self) -> 's':
        return ITEM_ID

    @dbus_property(access=PropertyAccess.READ)
    def Title(self) -> 's':
        summary = {"connected": "Input connected", "disconnected": "Input disconnected"}[state_name(self.connected)]
        return f"{self.hostname}: {summary}"

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> 's':
        # Passive would hide the very state the user needs to see. Neither
        # state requests attention or makes sound.
        return "Active"

    @dbus_property(access=PropertyAccess.READ)
    def IconName(self) -> 's':
        return ""

    @dbus_property(access=PropertyAccess.READ)
    def IconPixmap(self) -> 'a(iiay)':
        return self.icons[state_name(self.connected)]

    @dbus_property(access=PropertyAccess.READ)
    def ToolTip(self) -> '(sa(iiay)ss)':
        detail = "Keyboard and mouse are " + state_name(self.connected) + " on this computer."
        return ["", self.IconPixmap, self.Title, detail]

    @dbus_property(access=PropertyAccess.READ)
    def ItemIsMenu(self) -> 'b':
        return False

    @dbus_property(access=PropertyAccess.READ)
    def WindowId(self) -> 'u':
        return 0

    @dbus_property(access=PropertyAccess.READ)
    def Menu(self) -> 'o':
        return "/NO_DBUSMENU"

    @method()
    def Activate(self, x: 'i', y: 'i'):
        pass

    @method()
    def SecondaryActivate(self, x: 'i', y: 'i'):
        pass

    @method()
    def ContextMenu(self, x: 'i', y: 'i'):
        pass

    @method()
    def Scroll(self, delta: 'i', orientation: 's'):
        pass

    @signal()
    def NewIcon(self):
        pass

    @signal()
    def NewToolTip(self):
        pass

    @signal()
    def NewTitle(self):
        pass


class WatcherRegistration:
    """Register on startup and again when Plasma's tray watcher restarts."""
    def __init__(self, bus):
        self.bus = bus
        self.pending = None

    async def register(self):
        reply = await self.bus.call(Message(destination=WATCHER, path=WATCHER_PATH,
                                            interface=WATCHER, member="RegisterStatusNotifierItem",
                                            signature="s", body=[ITEM_PATH]))
        if reply.message_type == MessageType.ERROR:
            # Normal when launched before the tray; NameOwnerChanged retries.
            logging.info("Tray registration deferred: %s", reply.error_name)

    def changed(self, message):
        if (message.message_type == MessageType.SIGNAL
                and message.sender == "org.freedesktop.DBus"
                and message.interface == "org.freedesktop.DBus"
                and message.member == "NameOwnerChanged"
                and message.body[0] == WATCHER and message.body[2]):
            self.pending = asyncio.create_task(self.register())

    async def start(self):
        self.bus.add_message_handler(self.changed)
        reply = await self.bus.call(Message(destination="org.freedesktop.DBus",
                                            path="/org/freedesktop/DBus",
                                            interface="org.freedesktop.DBus", member="AddMatch",
                                            signature="s", body=[
            "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',"
            "member='NameOwnerChanged',arg0='org.kde.StatusNotifierWatcher'"
        ]))
        if reply.message_type == MessageType.ERROR:
            raise RuntimeError(f"Cannot watch tray restarts: {reply.body}")
        await self.register()


async def run():
    context = pyudev.Context()
    monitor = pyudev.Monitor.from_netlink(context)
    monitor.filter_by(subsystem="usb", device_type="usb_device")
    # Subscribe before enumerating so a switch during startup cannot be missed.
    monitor.start()
    item = InputIndicator(is_connected(context))
    bus = await MessageBus().connect()
    bus.export(ITEM_PATH, item)
    registration = WatcherRegistration(bus)
    loop = asyncio.get_running_loop()
    def device_event():
        while monitor.poll(timeout=0) is not None:
            pass
        item.update(is_connected(context))

    loop.add_reader(monitor.fileno(), device_event)
    await registration.start()
    await bus.wait_for_disconnect()
    raise RuntimeError("Session bus disconnected")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Print current presence and exit")
    args = parser.parse_args()
    if args.check:
        print(state_name(is_connected(pyudev.Context())))
        return
    logging.basicConfig(level=logging.INFO)
    asyncio.run(run())


if __name__ == "__main__":
    main()
