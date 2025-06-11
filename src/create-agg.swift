import Foundation
import CoreAudio


// Function to get device UID by display name
func getDeviceUID(byName name: String) -> CFString? {
    var size: UInt32 = 0
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size) == noErr
    else { return nil }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size, &devices) == noErr
    else { return nil }
    for device in devices {
        // Get display name
        var nameCF: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(device, &nameAddr, 0, nil, &nameSize, &nameCF) != noErr { continue }
        guard let displayName = nameCF?.takeRetainedValue() as String?, displayName == name else { continue }
        // Get device UID
        var uidCF: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(device, &uidAddr, 0, nil, &uidSize, &uidCF) == noErr,
           let uid = uidCF?.takeRetainedValue() {
            return uid
        }
    }
    return nil
}

let args = CommandLine.arguments
guard args.count == 4 else {
    print("Usage: create-agg <aggDeviceName> <inputDeviceName> <outputDeviceName>")
    exit(1)
}
let aggNameStr = args[1]
let inputName = args[2]
let outputName = args[3]

guard let inputDeviceUID = getDeviceUID(byName: inputName) else {
    print("Input device not found: \(inputName)")
    exit(1)
}
guard let outputDeviceUID = getDeviceUID(byName: outputName) else {
    print("Output device not found: \(outputName)")
    exit(1)
}

// Nom et UID unique de l’aggregate device
let aggName: CFString = aggNameStr as CFString
let aggUID: CFString = "com.mycompany.aggregate.\(UUID().uuidString)" as CFString

// Build sub-device list for aggregate device
let subDeviceList: [CFDictionary] = [
    [
        kAudioSubDeviceUIDKey as String: inputDeviceUID,
        kAudioSubDeviceDriftCompensationKey as String: false as CFBoolean
    ] as CFDictionary,
    [
        kAudioSubDeviceUIDKey as String: outputDeviceUID,
        kAudioSubDeviceDriftCompensationKey as String: true as CFBoolean
    ] as CFDictionary
]

// Configuration dictionary for creating aggregate device
let config = [
    kAudioAggregateDeviceNameKey as String:           aggName,
    kAudioAggregateDeviceUIDKey as String:            aggUID,
    kAudioAggregateDeviceSubDeviceListKey as String:  subDeviceList as CFArray
] as CFDictionary

var newDeviceID = AudioDeviceID(0)
let status = AudioHardwareCreateAggregateDevice(config, &newDeviceID)

if status == noErr {
    print("✅ Aggregate device ‘\(aggName)’ créé avec AudioDeviceID = \(newDeviceID)")
    print("   UID interne = \(aggUID)")
} else {
    print("❌ Échec de la création (code \(status))")
    exit(1)
}