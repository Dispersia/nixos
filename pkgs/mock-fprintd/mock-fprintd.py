#!/usr/bin/env python3
"""Mock fprintd D-Bus service.

Implements enough of the ``net.reactivated.Fprint`` system-bus API for clients
(notably ``pam_fprintd``) to authenticate successfully, but instead of talking
to real hardware it always reports a matching fingerprint.

This is a testing aid only: any biometric check backed by this daemon succeeds
unconditionally. Never run it on a host where that matters.

The API surface below is derived from fprintd's
``src/net.reactivated.Fprint.{Manager,Device}.xml``.
"""

import signal
import sys

from gi.repository import GLib, Gio

try:
    from gi.repository import GLibUnix
except ImportError:  # pragma: no cover - older PyGObject
    GLibUnix = None

BUS_NAME = "net.reactivated.Fprint"
MANAGER_PATH = "/net/reactivated/Fprint/Manager"
DEVICE_PATH = "/net/reactivated/Fprint/Device/0"
MANAGER_IFACE = "net.reactivated.Fprint.Manager"
DEVICE_IFACE = "net.reactivated.Fprint.Device"

# The finger we advertise as enrolled; "any" verification always matches it.
FINGER = "right-index-finger"
ENROLL_STAGES = 5

MANAGER_XML = """
<node>
  <interface name="net.reactivated.Fprint.Manager">
    <method name="GetDevices">
      <arg type="ao" name="devices" direction="out"/>
    </method>
    <method name="GetDefaultDevice">
      <arg type="o" name="device" direction="out"/>
    </method>
  </interface>
</node>
"""

DEVICE_XML = """
<node>
  <interface name="net.reactivated.Fprint.Device">
    <method name="ListEnrolledFingers">
      <arg type="s" name="username" direction="in"/>
      <arg type="as" name="enrolled_fingers" direction="out"/>
    </method>
    <method name="DeleteEnrolledFingers">
      <arg type="s" name="username" direction="in"/>
    </method>
    <method name="DeleteEnrolledFingers2"/>
    <method name="DeleteEnrolledFinger">
      <arg type="s" name="finger_name" direction="in"/>
    </method>
    <method name="Claim">
      <arg type="s" name="username" direction="in"/>
    </method>
    <method name="Release"/>
    <method name="VerifyStart">
      <arg type="s" name="finger_name" direction="in"/>
    </method>
    <method name="VerifyStop"/>
    <method name="EnrollStart">
      <arg type="s" name="finger_name" direction="in"/>
    </method>
    <method name="EnrollStop"/>
    <method name="GetProperties">
      <arg type="a{sv}" name="properties" direction="out"/>
    </method>
    <signal name="VerifyFingerSelected">
      <arg type="s" name="finger_name"/>
    </signal>
    <signal name="VerifyStatus">
      <arg type="s" name="result"/>
      <arg type="b" name="done"/>
    </signal>
    <signal name="EnrollStatus">
      <arg type="s" name="result"/>
      <arg type="b" name="done"/>
    </signal>
    <property name="name" type="s" access="read"/>
    <property name="num-enroll-stages" type="i" access="read"/>
    <property name="scan-type" type="s" access="read"/>
    <property name="finger-present" type="b" access="read"/>
    <property name="finger-needed" type="b" access="read"/>
  </interface>
</node>
"""


def log(message):
    print(f"mock-fprintd: {message}", flush=True)


class MockFprintd:
    def __init__(self):
        self.connection = None
        self.claimed_user = None
        self.enroll_step = 0
        self.loop = GLib.MainLoop()

    # -- D-Bus setup -------------------------------------------------------

    def bus_acquired(self, connection, _name):
        self.connection = connection
        for xml, path, call_handler, get_property in (
            (MANAGER_XML, MANAGER_PATH, self.on_manager_call, None),
            (DEVICE_XML, DEVICE_PATH, self.on_device_call, self.on_get_property),
        ):
            interface = Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0]
            connection.register_object(path, interface, call_handler, get_property, None)
        log(f"registered {DEVICE_PATH}")

    def name_acquired(self, _connection, name):
        log(f"acquired {name}")

    def name_lost(self, _connection, name):
        log(f"lost bus name {name}, exiting")
        self.loop.quit()

    # -- Manager interface -------------------------------------------------

    def on_manager_call(
        self, _connection, _sender, _path, _iface, method, _params, invocation
    ):
        log(f"manager call: {method}")
        if method == "GetDevices":
            invocation.return_value(GLib.Variant("(ao)", ([DEVICE_PATH],)))
        elif method == "GetDefaultDevice":
            invocation.return_value(GLib.Variant("(o)", (DEVICE_PATH,)))
        else:
            invocation.return_error_literal(
                Gio.DBusError, Gio.DBusError.UNKNOWN_METHOD, method
            )
        return None

    # -- Device interface --------------------------------------------------

    def on_device_call(
        self, _connection, _sender, _path, _iface, method, params, invocation
    ):
        log(f"device call: {method} {params.unpack()}")
        if method == "ListEnrolledFingers":
            # pam_fprintd skips the device entirely unless at least one finger is
            # advertised as enrolled, so this must stay non-empty.
            invocation.return_value(GLib.Variant("(as)", ([FINGER],)))
        elif method == "Claim":
            self.claimed_user = params.unpack()[0] or None
            invocation.return_value(None)
        elif method == "Release":
            self.claimed_user = None
            invocation.return_value(None)
        elif method == "VerifyStart":
            # Reply first: clients only accept VerifyStatus after VerifyStart
            # has completed, so the signals are emitted from an idle callback.
            invocation.return_value(None)
            GLib.idle_add(self.emit_verify_match)
        elif method == "VerifyStop":
            invocation.return_value(None)
        elif method == "EnrollStart":
            invocation.return_value(None)
            self.enroll_step = 0
            GLib.idle_add(self.emit_enroll_progress)
        elif method == "EnrollStop":
            invocation.return_value(None)
        elif method in (
            "DeleteEnrolledFingers",
            "DeleteEnrolledFingers2",
            "DeleteEnrolledFinger",
        ):
            invocation.return_value(None)
        elif method == "GetProperties":
            invocation.return_value(GLib.Variant("(a{sv})", (self.properties(),)))
        else:
            invocation.return_error_literal(
                Gio.DBusError, Gio.DBusError.UNKNOWN_METHOD, method
            )
        return None

    def on_get_property(self, _connection, _sender, _path, _iface, name):
        return self.properties().get(name)

    def properties(self):
        return {
            "name": GLib.Variant("s", "Mock fingerprint reader (always matches)"),
            "num-enroll-stages": GLib.Variant("i", ENROLL_STAGES),
            "scan-type": GLib.Variant("s", "press"),
            "finger-present": GLib.Variant("b", False),
            "finger-needed": GLib.Variant("b", False),
        }

    # -- Signals -----------------------------------------------------------

    def emit(self, signal_name, payload):
        self.connection.emit_signal(
            None, DEVICE_PATH, DEVICE_IFACE, signal_name, payload
        )

    def emit_verify_match(self):
        log("verify result: verify-match")
        self.emit("VerifyFingerSelected", GLib.Variant("(s)", (FINGER,)))
        self.emit("VerifyStatus", GLib.Variant("(sb)", ("verify-match", True)))
        return GLib.SOURCE_REMOVE

    def emit_enroll_progress(self):
        self.enroll_step += 1
        if self.enroll_step < ENROLL_STAGES:
            self.emit(
                "EnrollStatus", GLib.Variant("(sb)", ("enroll-stage-passed", False))
            )
            GLib.timeout_add(100, self.emit_enroll_progress)
        else:
            self.emit("EnrollStatus", GLib.Variant("(sb)", ("enroll-completed", True)))
        return GLib.SOURCE_REMOVE


def main():
    mock = MockFprintd()

    signal_add = GLibUnix.signal_add if GLibUnix else GLib.unix_signal_add
    stop = lambda *_: (mock.loop.quit(), GLib.SOURCE_REMOVE)[1]
    signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop)
    signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop)

    owner_id = Gio.bus_own_name(
        Gio.BusType.SYSTEM,
        BUS_NAME,
        Gio.BusNameOwnerFlags.NONE,
        mock.bus_acquired,
        mock.name_acquired,
        mock.name_lost,
    )

    try:
        mock.loop.run()
    finally:
        Gio.bus_unown_name(owner_id)

    return 0


if __name__ == "__main__":
    sys.exit(main())
