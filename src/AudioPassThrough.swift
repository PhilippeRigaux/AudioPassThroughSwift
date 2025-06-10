
import Foundation
import CoreAudio
import AudioUnit

// Toggle debug logging
let DEBUG = false // set to false to disable debug messages

// Utility pour lister les devices
func listAudioDevices(input: Bool) {
    var size: UInt32 = 0
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size) == noErr
    else { return }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &devices) == noErr
    else { return }
    for dev in devices {
        var nameUnmanaged: Unmanaged<CFString>?
        var propSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(
                dev, &nameAddr, 0, nil, &propSize, &nameUnmanaged) == noErr,
           let name = nameUnmanaged?.takeRetainedValue() {
            // Vérifier flux input/output
            var streamSize: UInt32 = 0
            var strAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: input
                  ? kAudioDevicePropertyScopeInput
                  : kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(dev, &strAddr),
               AudioObjectGetPropertyDataSize(
                 dev, &strAddr, 0, nil, &streamSize) == noErr,
               streamSize > 0 {
                print(" - \(name)")
            }
        }
    }
}

/// Liste uniquement les Aggregate Devices
func listAggregateDevices() {
    var size: UInt32 = 0
    var addressAll = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &addressAll, 0, nil, &size) == noErr else { return }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &addressAll, 0, nil, &size, &devices) == noErr else { return }

    print("Available Aggregate Devices:")
    for dev in devices {
        // Check for aggregate device by active subdevice list property
        var aggAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyActiveSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(dev, &aggAddress) {
            continue
        }
        var nameUnmanaged: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(dev, &nameAddr, 0, nil, &nameSize, &nameUnmanaged) == noErr,
           let name = nameUnmanaged?.takeRetainedValue() {
            print(" - \(name)")
        }
    }
}

// Cherche un périphérique par nom et sens
func getDeviceID(byName name: String, input: Bool) -> AudioDeviceID? {
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
    for dev in devices {
        var nameUnmanaged: Unmanaged<CFString>?
        var propSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(
                dev, &nameAddr, 0, nil, &propSize, &nameUnmanaged) == noErr,
           let devName = nameUnmanaged?.takeRetainedValue() as String?,
           devName == name {
            // Check direction
            var streamSize: UInt32 = 0
            var strAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: input
                  ? kAudioDevicePropertyScopeInput
                  : kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(dev, &strAddr),
               AudioObjectGetPropertyDataSize(
                 dev, &strAddr, 0, nil, &streamSize) == noErr,
               streamSize > 0 {
                return dev
            }
        }
    }
    return nil
}

func displayHelp() {
    print("""
Usage: AudioPassThrough <aggregateDeviceName> <srcChannels> <dstChannels>
Options:
  -h              Display this help and list only aggregate audio devices.

""")
    listAggregateDevices()
}

// --- REFACTOR SINGLE HAL OUTPUT UNIT ---
class AudioPassThroughCoreAudio {
    let deviceID: AudioDeviceID
    let srcChannels: [Int]
    let dstChannels: [Int]
    var audioUnit: AudioUnit?
    var callbackCount = 0

    init(deviceID: AudioDeviceID, srcChannels: [Int], dstChannels: [Int]) {
        self.deviceID = deviceID
        self.srcChannels = srcChannels
        self.dstChannels = dstChannels
    }

    func start() {
        // 1) Trouve le HALOutput component
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            print("Unable to find HALOutput component")
            exit(1)
        }
        // 2) Crée et instancie l'AudioUnit
        var unitPtr: AudioUnit?
        guard AudioComponentInstanceNew(comp, &unitPtr) == noErr,
              let unit = unitPtr else {
            print("Unable to instantiate HALOutput unit")
            exit(1)
        }
        audioUnit = unit

        // 3) Active IO : entrée bus 1, sortie bus 0
        var enable: UInt32 = 1
        guard AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input, 1,
                &enable,
                UInt32(MemoryLayout<UInt32>.size)) == noErr else {
            print("Cannot enable input on HALOutput")
            exit(1)
        }
        guard AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output, 0,
                &enable,
                UInt32(MemoryLayout<UInt32>.size)) == noErr else {
            print("Cannot enable output on HALOutput")
            exit(1)
        }

        // 4) Assigne l'aggregate device en scope GLOBAL
        var dev = deviceID
        guard AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0,
                &dev,
                UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
            print("Cannot set aggregate device")
            exit(1)
        }

        // 5) Récupère le format matériel (scope OUTPUT, bus 0)
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioUnitGetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output, 0,
                &asbd,
                &asbdSize) == noErr else {
            print("Cannot read hardware stream format")
            exit(1)
        }
        if DEBUG {
            print("[DEBUG] Hardware format: rate=\(asbd.mSampleRate), ch=\(asbd.mChannelsPerFrame)")
        }

        // 6) Applique ce format au bus 1 (scope OUTPUT) et bus 0 (scope INPUT)
        guard AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output, 1,
                &asbd,
                asbdSize) == noErr else {
            print("Cannot set format on input bus")
            exit(1)
        }
        guard AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input, 0,
                &asbd,
                asbdSize) == noErr else {
            print("Cannot set format on output bus")
            exit(1)
        }

        // 7) Installe le callback sur bus 0 INPUT
        let ref = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var cb = AURenderCallbackStruct(
            inputProc: { inRefCon, ioFlags, inTime, inBus, inFrames, ioData in
                let inst = Unmanaged<AudioPassThroughCoreAudio>
                           .fromOpaque(inRefCon).takeUnretainedValue()
                guard let au = inst.audioUnit, let io = ioData else {
                    return -1
                }
                var flags = AudioUnitRenderActionFlags()
                let status = AudioUnitRender(au,
                                             &flags,
                                             inTime,
                                             1,
                                             inFrames,
                                             io)
                if DEBUG && status != noErr {
                    print("[DEBUG] Render error: \(status)")
                }
                // Route source channels to multiple destination channels (duplication allowed)
                let buffers = UnsafeMutableAudioBufferListPointer(io)
                let srcCount = inst.srcChannels.count
                // Map each destination channel to corresponding source channel in round-robin
                for (i, dst) in inst.dstChannels.enumerated() {
                    let dstIdx = dst - 1
                    let srcIdx = inst.srcChannels[i % srcCount] - 1
                    if srcIdx < buffers.count && dstIdx < buffers.count {
                        if let srcPtr = buffers[srcIdx].mData, let dstPtr = buffers[dstIdx].mData {
                            memcpy(dstPtr, srcPtr, Int(buffers[srcIdx].mDataByteSize))
                        }
                    }
                }
                // Optionally zero original source channels
                for src in inst.srcChannels {
                    let idx = src - 1
                    if idx < buffers.count, let ptr = buffers[idx].mData {
                        memset(ptr, 0, Int(buffers[idx].mDataByteSize))
                    }
                }
                inst.callbackCount += 1
                if DEBUG && inst.callbackCount % 200 == 0 {
                    print("[DEBUG] Callback #\(inst.callbackCount), frames=\(inFrames), status=\(status)")
                }
                return status
            },
            inputProcRefCon: ref
        )
        guard AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_SetRenderCallback,
                kAudioUnitScope_Input, 0,
                &cb,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr else {
            print("Cannot install render callback")
            exit(1)
        }

        // 8) Initialise et démarre l’unité
        guard AudioUnitInitialize(unit) == noErr else {
            print("Cannot initialize HALOutput")
            exit(1)
        }
        guard AudioOutputUnitStart(unit) == noErr else {
            print("Cannot start HALOutput")
            exit(1)
        }

        print("Audio pass-through ON for device ID \(deviceID)")
    }
}

// --- Main ---
let args = CommandLine.arguments
if args.count == 2 && args[1] == "-h" {
    displayHelp()
    exit(0)
}
guard args.count == 4 else {
    print("Usage: AudioPassThrough <aggregateDeviceName> <srcChannels> <dstChannels>")
    exit(1)
}
let deviceName = args[1]
let srcStr = args[2]
let dstStr = args[3]
// Build integer arrays from strings of digits
let srcChannels = Array(srcStr).compactMap { Int(String($0)) }
let dstChannels = Array(dstStr).compactMap { Int(String($0)) }
guard srcChannels.count > 0, dstChannels.count > 0 else {
    print("Error: srcChannels and dstChannels must each contain at least one channel")
    exit(1)
}
guard let devID = getDeviceID(byName: deviceName, input: true) else {
    print("Device not found: \(deviceName)")
    exit(1)
}
let pass = AudioPassThroughCoreAudio(deviceID: devID, srcChannels: srcChannels, dstChannels: dstChannels)
pass.start()
RunLoop.main.run()