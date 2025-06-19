import Foundation
import CoreAudio

let kstacked: CFString = "stacked" as CFString

func getDeviceUID(byName name: String) -> CFString? {
    var size: UInt32 = 0
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size) == noErr else { return nil }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size, &devices) == noErr else { return nil }
    for dev in devices {
        var nameCF: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(dev, &nameAddr, 0, nil, &nameSize, &nameCF) != noErr {
            continue
        }
        if let displayName = nameCF?.takeRetainedValue() as String?, displayName == name {
            var uidCF: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(dev, &uidAddr, 0, nil, &uidSize, &uidCF) == noErr,
               let uid = uidCF?.takeRetainedValue() {
                return uid
            }
        }
    }
    return nil
}

func createAggregateDevice(name: String, inputName: String, outputName: String) {
    guard let inputUID = getDeviceUID(byName: inputName) else {
        print("Input device not found: \(inputName)")
        exit(1)
    }
    guard let outputUID = getDeviceUID(byName: outputName) else {
        print("Output device not found: \(outputName)")
        exit(1)
    }
    let aggName: CFString = name as CFString
    let aggUID: CFString = "com.mycompany.aggregate.\(UUID().uuidString)" as CFString
    let subDeviceList: [CFDictionary] = [
        [kAudioSubDeviceUIDKey as String: inputUID,
         kAudioSubDeviceDriftCompensationKey as String: false as CFBoolean] as CFDictionary,
        [kAudioSubDeviceUIDKey as String: outputUID,
         kAudioSubDeviceDriftCompensationKey as String: true as CFBoolean] as CFDictionary
    ]
    let config = [
        kAudioAggregateDeviceNameKey as String: aggName,
        kAudioAggregateDeviceUIDKey as String: aggUID,
        kAudioAggregateDeviceSubDeviceListKey as String: subDeviceList as CFArray
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
}

func createMultiOutputDevice(name: String, deviceNames: [String]) {
    guard deviceNames.count >= 1 else {
        print("At least one output device is required")
        exit(1)
    }
    var subDeviceList = [[String: Any]]()
    for (index, devName) in deviceNames.enumerated() {
        guard let uid = getDeviceUID(byName: devName) else {
            print("❌ Could not find device UID for output device named ‘\(devName)’")
            exit(1)
        }
        let drift = (index == 0) ? 0 : 1
        let entry: [String: Any] = [
            kAudioSubDeviceUIDKey as String: uid,
            kAudioSubDeviceDriftCompensationKey as String: drift
        ]
        subDeviceList.append(entry)
    }
    let multiName = name as CFString
    let multiUID = UUID().uuidString as CFString
    let description: [String: Any] = [
        kAudioAggregateDeviceNameKey as String: multiName,
        kAudioAggregateDeviceUIDKey as String: multiUID,
        kAudioAggregateDeviceSubDeviceListKey as String: subDeviceList,
        kstacked as String: true
    ]
    let config = description as CFDictionary
    var newDeviceID = AudioDeviceID(0)
    let status = AudioHardwareCreateAggregateDevice(config, &newDeviceID)
    if status == noErr {
        print("✅ Multi-output device ‘\(multiName)’ created with AudioDeviceID = \(newDeviceID)")
    } else {
        print("❌ Failed to create device (error code: \(status))")
    }
}

let args = CommandLine.arguments
if args.count < 2 {
    print("Usage: createVirtDev -a <aggName> <inputDevice> <outputDevice> | -m <multiName> <OutputDevice1> [OutputDevice2 ...]")
    exit(1)
}
let mode = args[1]
if mode == "-a" {
    guard args.count == 5 else {
        print("Usage: createVirtDev -a <aggName> <inputDevice> <outputDevice>")
        exit(1)
    }
    createAggregateDevice(name: args[2], inputName: args[3], outputName: args[4])
} else if mode == "-m" {
    guard args.count >= 4 else {
        print("Usage: createVirtDev -m <multiName> <OutputDevice1> [OutputDevice2 ...]")
        exit(1)
    }
    let deviceNames = Array(args[3...])
    createMultiOutputDevice(name: args[2], deviceNames: deviceNames)
} else {
    print("Invalid option. Use -a for aggregate or -m for multi-output device")
    exit(1)
}
