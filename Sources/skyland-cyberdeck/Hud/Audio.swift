import AudioToolbox
import CoreAudio
import Foundation

// Output volume, mute and device through CoreAudio: what the HUD shows is read back
// from the system, and the slider writes to the real device.

struct AudioDevice: Equatable, Identifiable {
    let id: AudioObjectID
    let name: String
}

enum Audio {
    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static var defaultOutput: AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var where_ = address(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static func setDefaultOutput(_ device: AudioObjectID) -> Bool {
        var id = device
        var where_ = address(kAudioHardwarePropertyDefaultOutputDevice)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id) == noErr
    }

    /// Devices with output channels.
    static func outputDevices() -> [AudioDevice] {
        var where_ = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasOutput).compactMap { id in name(of: id).map { AudioDevice(id: id, name: $0) } }
    }

    private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var where_ = address(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &where_, 0, nil, &size) == noErr, size > 0 else { return false }
        let list = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { list.deallocate() }
        guard AudioObjectGetPropertyData(device, &where_, 0, nil, &size, list) == noErr else { return false }
        let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    static func name(of device: AudioObjectID) -> String? {
        var where_ = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    /// 0...1, nil when the device has no volume control (some HDMI / USB outputs).
    static func volume(of device: AudioObjectID) -> Float? {
        var where_ = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &where_) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func setVolume(_ value: Float, of device: AudioObjectID) -> Bool {
        var where_ = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        var volume = Float32(min(1, max(0, value)))
        return AudioObjectSetPropertyData(device, &where_, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume) == noErr
    }

    static func muted(_ device: AudioObjectID) -> Bool? {
        var where_ = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &where_) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &value) == noErr ? value != 0 : nil
    }

    static func setMuted(_ muted: Bool, _ device: AudioObjectID) -> Bool {
        var where_ = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &where_, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
