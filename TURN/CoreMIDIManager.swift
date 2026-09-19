import Foundation
import CoreMIDI
import Combine
import os.log

/// Owns the Core MIDI stack: two virtual HUI endpoints bridged to Pro Tools
/// and an input/output pair bound to any connected SMC-Mixer hardware.
final class CoreMIDIManager: ObservableObject, @unchecked Sendable {
    @Published var isHardwareConnected = false
    @Published var isVirtualPortActive = false

    private var midiClient: MIDIClientRef = 0
    private var virtualInputPort: MIDIEndpointRef = 0
    private var virtualOutputPort: MIDIEndpointRef = 0
    private var hardwareInputPort: MIDIPortRef = 0
    private var hardwareOutputPort: MIDIPortRef = 0

    private let huiEngine: HUIProtocolEngine
    private let logger = Logger(subsystem: "com.samuelbacaro.TURN", category: "midi")

    private var connectedSources: Set<MIDIEndpointRef> = []
    private var hardwareDestinations: Set<MIDIEndpointRef> = []

    private static let sendToHardwareNotification = Notification.Name("SendToHardware")

    init(huiEngine: HUIProtocolEngine) {
        self.huiEngine = huiEngine
        setupMIDI()

        NotificationCenter.default.addObserver(
            forName: Self.sendToHardwareNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }

            if let cc = notification.userInfo?["cc"] as? UInt8,
               let value = notification.userInfo?["value"] as? UInt8 {
                self.sendToHardware(bytes: [0xB0, cc, value])
            } else if let note = notification.userInfo?["note"] as? UInt8,
                      let isOn = notification.userInfo?["isOn"] as? Bool {
                // SMC-Mixer button LEDs respond to fixed firmware notes,
                // not to the CCs assigned in MidiSuite.
                let status: UInt8 = isOn ? 0x90 : 0x80
                self.sendToHardware(bytes: [status, note, isOn ? 0x7F : 0x00])
            }
        }
    }

    private func setupMIDI() {
        var status = MIDIClientCreateWithBlock("TURNClient" as CFString, &midiClient) { [weak self] notification in
            self?.handleMIDINotification(notification.pointee)
        }

        guard status == noErr else {
            logger.error("Failed to create MIDI client (status \(status, privacy: .public)).")
            return
        }

        status = MIDIDestinationCreateWithBlock(
            midiClient,
            "Avid Virtual HUI In" as CFString,
            &virtualInputPort
        ) { [weak self] packetList, _ in
            self?.huiEngine.receiveFromProTools(packetList: packetList)
        }

        guard status == noErr else {
            logger.error("Failed to create virtual input port (status \(status, privacy: .public)).")
            return
        }

        status = MIDISourceCreate(midiClient, "Avid Virtual HUI Out" as CFString, &virtualOutputPort)

        guard status == noErr else {
            logger.error("Failed to create virtual output port (status \(status, privacy: .public)).")
            return
        }

        huiEngine.setVirtualOutput(port: virtualOutputPort)
        DispatchQueue.main.async {
            self.isVirtualPortActive = true
        }

        MIDIInputPortCreateWithBlock(
            midiClient,
            "Hardware Input Port" as CFString,
            &hardwareInputPort
        ) { [weak self] packetList, _ in
            self?.handleHardwareInput(packetList: packetList)
        }

        MIDIOutputPortCreate(midiClient, "Hardware Output Port" as CFString, &hardwareOutputPort)

        connectToHardware()
    }

    private func connectToHardware() {
        var foundHardware = false

        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard !connectedSources.contains(source) else {
                foundHardware = true
                continue
            }

            guard let name = midiName(of: source),
                  !name.contains("Avid Virtual HUI"),
                  isSMCMixer(name) else { continue }

            if MIDIPortConnectSource(hardwareInputPort, source, nil) == noErr {
                connectedSources.insert(source)
                foundHardware = true
                logger.info("Connected to hardware source: \(name, privacy: .public)")
            }
        }

        for index in 0..<MIDIGetNumberOfDestinations() {
            let destination = MIDIGetDestination(index)
            guard !hardwareDestinations.contains(destination) else { continue }

            guard let name = midiName(of: destination),
                  !name.contains("Avid Virtual HUI"),
                  isSMCMixer(name) else { continue }

            hardwareDestinations.insert(destination)
            logger.info("Registered hardware destination: \(name, privacy: .public)")
        }

        DispatchQueue.main.async {
            self.isHardwareConnected = foundHardware
        }
    }

    private func isSMCMixer(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("smc") || lowered.contains("m-vave")
    }

    private func midiName(of object: MIDIObjectRef) -> String? {
        var nameRef: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, kMIDIPropertyName, &nameRef) == noErr else { return nil }
        return nameRef?.takeRetainedValue() as String?
    }

    private func sendToHardware(bytes: [UInt8]) {
        guard hardwareOutputPort != 0 else { return }

        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        let listSize = MemoryLayout.size(ofValue: packetList)

        var buffer = bytes
        packet = MIDIPacketListAdd(&packetList, listSize, packet, 0, bytes.count, &buffer)

        for destination in hardwareDestinations {
            MIDISend(hardwareOutputPort, destination, &packetList)
        }
    }

    private func handleHardwareInput(packetList: UnsafePointer<MIDIPacketList>) {
        var packetPointer = UnsafeRawPointer(packetList)
            .advanced(by: MemoryLayout.offset(of: \MIDIPacketList.packet)!)
            .assumingMemoryBound(to: MIDIPacket.self)

        for _ in 0..<packetList.pointee.numPackets {
            let packet = packetPointer.pointee
            let length = Int(packet.length)
            let bytes = withUnsafeBytes(of: packet.data) {
                Array($0.bindMemory(to: UInt8.self).prefix(length))
            }

            huiEngine.translateAndSendToProTools(hardwareData: Data(bytes))

            packetPointer = UnsafePointer(MIDIPacketNext(packetPointer))
        }
    }

    private func handleMIDINotification(_ notification: MIDINotification) {
        guard notification.messageID == .msgSetupChanged else { return }
        DispatchQueue.main.async {
            self.connectToHardware()
        }
    }
}
