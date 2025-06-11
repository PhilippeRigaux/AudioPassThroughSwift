import Foundation

import CoreAudio

// Constant to indicate a stacked (multi-output) device
let kstacked: CFString = "stacked" as CFString

func getDeviceUID(byName name: String) -> CFString? {
    // 1) Récupérer la liste des AudioDeviceID
    var dataSize: UInt32 = 0
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &dataSize) == noErr else {
        return nil
    }

    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &dataSize, &devices) == noErr else {
        return nil
    }

    // 2) Parcourir et comparer les noms
    for dev in devices {
        // Lire le nom d'affichage
        var nameBuf: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(
            dev, &nameAddr, 0, nil, &nameSize, &nameBuf) != noErr {
            continue
        }
        let displayName = nameBuf!.takeRetainedValue() as String
        guard displayName == name else { continue }

        // Lire l'UID du périphérique
        var uidBuf: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(
            dev, &uidAddr, 0, nil, &uidSize, &uidBuf) == noErr {
            return uidBuf!.takeRetainedValue()
        }
    }
    return nil
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: create-multi.swift <multiDeviceName> <OutputDevice1> [OutputDevice2] [...]")
    exit(1)
}

let multiName = args[1] as CFString
let multiUID = UUID().uuidString as CFString
let outputDeviceNames = Array(args[2...])

// Determine primary device (first in list) and build subDeviceList with appropriate drift compensation
var subDeviceList = [[String: Any]]()
var primaryDeviceUID: CFString? = nil

for (index, deviceName) in outputDeviceNames.enumerated() {
    guard let uid = getDeviceUID(byName: deviceName) else {
        print("❌ Could not find device UID for output device named ‘\(deviceName)’")
        exit(1)
    }
    if index == 0 {
        primaryDeviceUID = uid
    }
    let driftComp = (index == 0) ? 0 : 1
    let entry: [String: Any] = [
        kAudioSubDeviceUIDKey as String: uid,
        kAudioSubDeviceDriftCompensationKey as String: driftComp
    ]
    subDeviceList.append(entry)
}

let description: [String: Any] = [
    kAudioAggregateDeviceNameKey as String:      multiName,
    kAudioAggregateDeviceUIDKey as String:       multiUID,
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
