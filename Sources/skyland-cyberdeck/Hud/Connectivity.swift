import AppKit
import CoreWLAN
import Foundation
import IOBluetooth

// Connection tiles: what can be read reliably, nothing simulated. A tile that
// cannot be read says so; a click opens the matching System Settings pane, and the
// Wi-Fi tile can also switch the radio (confirmed by reading it back).

enum TileState: Equatable {
    case on, off, unavailable
}

struct Tile: Equatable {
    var state: TileState
    var detail: String
}

/// Network names of `networksetup -listpreferredwirelessnetworks` (one per tab-indented line).
func parsePreferredNetworks(_ output: String) -> [String] {
    output.split(separator: "\n").filter { $0.hasPrefix("\t") }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

struct BluetoothDevice: Identifiable, Equatable {
    let id: String // address
    let name: String
    let connected: Bool
}

enum Connectivity {
    static func wifi() -> Tile {
        guard let interface = CWWiFiClient.shared().interface() else { return Tile(state: .unavailable, detail: "NO WI-FI") }
        guard interface.powerOn() else { return Tile(state: .off, detail: "OFF") }
        guard interface.wlanChannel() != nil || interface.rssiValue() != 0 else { return Tile(state: .on, detail: "NOT CONNECTED") }
        // the network name needs the Location permission (macOS 14+): often nil here
        let name = interface.ssid() ?? "CONNECTED"
        let rssi = interface.rssiValue()
        let bars = rssi >= -55 ? "▂▄▆█" : rssi >= -67 ? "▂▄▆" : rssi >= -75 ? "▂▄" : "▂"
        return Tile(state: .on, detail: "\(name) \(bars)")
    }

    /// Switch the Wi-Fi radio; the tile shows what the system reports afterwards.
    static func setWifi(_ on: Bool) {
        try? CWWiFiClient.shared().interface()?.setPower(on)
    }

    static func bluetooth() -> Tile {
        guard let controller = IOBluetoothHostController.default(), controller.addressAsString() != nil else {
            return Tile(state: .unavailable, detail: "NO BLUETOOTH")
        }
        guard controller.powerState == kBluetoothHCIPowerStateON else { return Tile(state: .off, detail: "OFF") }
        let connected = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isConnected() }
        return Tile(state: .on, detail: connected.isEmpty ? "ON" : connected.compactMap(\.name).joined(separator: ", "))
    }

    /// sharingd's setting; it can lag behind Control Center by a few seconds.
    static func airdrop() -> Tile {
        switch UserDefaults(suiteName: "com.apple.sharingd")?.string(forKey: "DiscoverableMode") {
            case "Everyone": Tile(state: .on, detail: "EVERYONE")
            case "Contacts Only": Tile(state: .on, detail: "CONTACTS ONLY")
            case "Off": Tile(state: .off, detail: "RECEIVING OFF")
            default: Tile(state: .unavailable, detail: "UNKNOWN")
        }
    }

    /// Wi-Fi device ("en0").
    static var wifiDevice: String? { CWWiFiClient.shared().interface()?.interfaceName }

    /// Networks this Mac joined before (names readable without the Location permission).
    static func knownNetworks() -> [String] {
        guard let device = wifiDevice, let output = run("/usr/sbin/networksetup", ["-listpreferredwirelessnetworks", device]) else { return [] }
        return parsePreferredNetworks(output)
    }

    /// Join a known network (password from the keychain). Blocking: call off the main thread.
    static func join(_ network: String) -> Bool {
        guard let device = wifiDevice, let output = run("/usr/sbin/networksetup", ["-setairportnetwork", device, network]) else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty // it prints only errors
    }

    static func pairedDevices() -> [BluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap { device in
            guard let address = device.addressString else { return nil }
            return BluetoothDevice(id: address, name: device.name ?? address, connected: device.isConnected())
        }
    }

    /// Connect or disconnect a paired device. Blocking: call off the main thread.
    static func toggle(_ device: BluetoothDevice) {
        guard let target = IOBluetoothDevice(addressString: device.id) else { return }
        if device.connected { target.closeConnection() } else { target.openConnection() }
    }

    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// System Settings panes for the tiles.
    static func openSettings(_ pane: String) {
        let ids = [
            "wifi": "com.apple.wifi-settings-extension",
            "bluetooth": "com.apple.BluetoothSettings",
            "vpn": "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension",
            "airdrop": "com.apple.AirDrop-Handoff-Settings.extension",
            "focus": "com.apple.Focus-Settings.extension",
            "battery": "com.apple.Battery-Settings.extension",
            "sound": "com.apple.Sound-Settings.extension",
            "displays": "com.apple.Displays-Settings.extension",
        ]
        if let id = ids[pane], let url = URL(string: "x-apple.systempreferences:\(id)") { NSWorkspace.shared.open(url) }
    }
}
