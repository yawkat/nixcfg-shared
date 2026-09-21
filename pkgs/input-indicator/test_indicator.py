import asyncio
import unittest

from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method

from indicator import (InputIndicator, ITEM_ID, ITEM_PATH, WATCHER, WATCHER_PATH,
                       WatcherRegistration, is_connected, state_name)


class Attributes:
    def __init__(self, vendor, product):
        self.values = {"idVendor": vendor, "idProduct": product}

    def asstring(self, name):
        value = self.values[name]
        if isinstance(value, Exception):
            raise value
        return value


class Device:
    def __init__(self, vendor, product):
        self.attributes = Attributes(vendor, product)


class Context:
    def __init__(self, devices):
        self.devices = devices

    def list_devices(self, *, subsystem, DEVTYPE):
        assert (subsystem, DEVTYPE) == ("usb", "usb_device")
        return self.devices


class PresenceTests(unittest.TestCase):
    def test_specific_devices_ignore_unrelated_keyboard(self):
        context = Context([Device("1050", "0407"), Device("1532", "0084")])
        self.assertFalse(is_connected(context))
        self.assertEqual(state_name(is_connected(context)), "disconnected")
        context.devices.append(Device("24F0", "0140"))
        self.assertEqual(state_name(is_connected(context)), "connected")
        context.devices = []
        self.assertFalse(is_connected(context))

    def test_unplug_during_enumeration(self):
        context = Context([Device(OSError("removed"), "0084"), Device("24f0", "0140")])
        self.assertFalse(is_connected(context))

    def test_icons_have_distinct_states_and_valid_pixels(self):
        item = InputIndicator(True, "test-machine")
        connected = item.IconPixmap
        for width, height, pixels in connected:
            self.assertEqual(len(pixels), width * height * 4)
            self.assertTrue(any(pixels[0::4]))
        item.update(False)
        self.assertNotEqual(connected, item.IconPixmap)
        self.assertEqual(item.Status, "Active")
        self.assertIn("disconnected", item.Title)
        self.assertIn("disconnected", item.ToolTip[3])
        self.assertEqual(item.Id, ITEM_ID)


class FakeWatcher(ServiceInterface):
    def __init__(self):
        super().__init__(WATCHER)
        self.registrations = asyncio.Queue()

    @method()
    def RegisterStatusNotifierItem(self, item: 's'):
        self.registrations.put_nowait(item)


class TrayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.publisher = await MessageBus().connect()
        self.host = await MessageBus().connect()
        self.item = InputIndicator(False, "test-machine")
        self.publisher.export(ITEM_PATH, self.item)
        self.watcher = FakeWatcher()
        self.host.export(WATCHER_PATH, self.watcher)

    async def asyncTearDown(self):
        self.publisher.disconnect()
        self.host.disconnect()
        await self.publisher.wait_for_disconnect()
        await self.host.wait_for_disconnect()

    async def registered(self):
        self.assertEqual(await asyncio.wait_for(self.watcher.registrations.get(), 2), ITEM_PATH)

    async def test_tray_startup_and_restart(self):
        registration = WatcherRegistration(self.publisher)
        # The indicator starts before Plasma and must register when it appears.
        await registration.start()
        await self.host.request_name(WATCHER)
        await self.registered()
        await self.host.release_name(WATCHER)
        await self.host.request_name(WATCHER)
        await self.registered()

    async def test_running_tray_and_property_updates(self):
        await self.host.request_name(WATCHER)
        registration = WatcherRegistration(self.publisher)
        await registration.start()
        await self.registered()
        introspection = await self.host.introspect(self.publisher.unique_name, ITEM_PATH)
        proxy = self.host.get_proxy_object(self.publisher.unique_name, ITEM_PATH, introspection)
        item = proxy.get_interface("org.kde.StatusNotifierItem")
        props = proxy.get_interface("org.freedesktop.DBus.Properties")
        self.assertEqual(await item.get_status(), "Active")
        self.assertIn("disconnected", await item.get_title())
        changed = asyncio.Event()
        item.on_new_icon(changed.set)
        self.item.update(True)
        await asyncio.wait_for(changed.wait(), 2)
        self.assertIn("connected", await item.get_title())
        values = await props.call_get_all("org.kde.StatusNotifierItem")
        self.assertEqual(values["Id"].value, ITEM_ID)
        self.assertTrue(values["IconPixmap"].value)
        self.assertEqual(values["ToolTip"].value[2], "test-machine: Input connected")
        changed.clear()
        self.item.update(True)
        # Unchanged device enumeration should not generate redundant tray updates.
        await asyncio.sleep(0.02)
        self.assertFalse(changed.is_set())


if __name__ == "__main__":
    unittest.main()
