import Foundation
import CoreMIDI
import os.log

/// Translates SMC-Mixer MIDI (CC + Note On) into HUI for Pro Tools and routes
/// Pro Tools feedback (ping, switches, meters, fader levels) back to the hardware.
final class HUIProtocolEngine: ObservableObject, @unchecked Sendable {

    private let presetManager: PresetManager
    private var virtualOutputPort: MIDIEndpointRef = 0
    private var currentHUIZone: UInt8 = 0
    private var lastKnobValues: [UInt8: UInt8] = [:]

    private let logger = Logger(subsystem: "com.samuelbacaro.TURN", category: "hui")

    init(presetManager: PresetManager) {
        self.presetManager = presetManager
    }

    func setVirtualOutput(port: MIDIEndpointRef) {
        virtualOutputPort = port
    }

    // MARK: - Hardware -> Pro Tools

    func translateAndSendToProTools(hardwareData: Data) {
        guard hardwareData.count >= 3 else { return }

        let status = hardwareData[0]
        let controller = hardwareData[1]
        let value = hardwareData[2]

        switch status & 0xF0 {
        case 0xB0:
            translateCC(controller, value)
        case 0x90 where value > 0:
            translateNote(controller, value)
        default:
            break
        }
    }

    private func translateCC(_ controller: UInt8, _ value: UInt8) {
        guard let mapping = presetManager.mapping(for: controller) else {
            logger.debug("Unmapped CC \(controller, privacy: .public) (value \(value, privacy: .public)).")
            return
        }

        switch mapping.huiCommand {
        case let command where command.hasPrefix("FADER_"):
            sendFaderMessage(command: command, value: value)
        case let command where command.hasPrefix("PAN_"):
            sendPanMessage(command: command, controller: controller, value: value)
        default:
            sendSwitchMessages(command: mapping.huiCommand, value: value)
        }
    }

    private func translateNote(_ note: UInt8, _ velocity: UInt8) {
        // The .smc hardware preset sends channel buttons as Note 40-47.
        // They resolve through the same table via their equivalent CC ids.
        guard let mapping = presetManager.mapping(for: note) else {
            logger.debug("Unmapped Note \(note, privacy: .public) (velocity \(velocity, privacy: .public)).")
            return
        }

        sendSwitchMessages(command: mapping.huiCommand, value: velocity)
    }

    private func sendFaderMessage(command: String, value: UInt8) {
        guard let channel = channelNumber(from: command, prefix: "FADER_") else { return }
        let index = UInt8(channel - 1)
        sendToVirtualPort(bytes: [0xB0, index, value])
        sendToVirtualPort(bytes: [0xB0, index &+ 0x20, 0x00])
    }

    private func sendPanMessage(command: String, controller: UInt8, value: UInt8) {
        guard let channel = channelNumber(from: command, prefix: "PAN_") else { return }

        let lastValue = lastKnobValues[controller] ?? 64
        let delta = Int(value) - Int(lastValue)
        lastKnobValues[controller] = value

        guard delta != 0 else { return }

        let isRight = delta > 0
        let magnitude = min(UInt8(abs(delta)), 0x0F)
        let huiValue = isRight ? magnitude : (magnitude | 0x40)
        sendToVirtualPort(bytes: [0xB0, 0x40 + UInt8(channel - 1), huiValue])
    }

    private func sendSwitchMessages(command: String, value: UInt8) {
        let isPressed = value > 64

        if let (zone, port) = huiSwitch(for: command) {
            sendToVirtualPort(bytes: buildHuiSwitch(zone: zone, port: port, state: isPressed))
        }
    }

    /// HUI switch table: channel zones 0-7, transport zone 0x0E, bank zone 0x10.
    private func huiSwitch(for command: String) -> (zone: UInt8, port: UInt8)? {
        let channelSwitches: [(prefix: String, port: UInt8)] = [
            ("REC_", 0x00),
            ("MUTE_", 0x02),
            ("SOLO_", 0x03),
            ("SELECT_", 0x04),
        ]

        for (prefix, port) in channelSwitches {
            if let channel = channelNumber(from: command, prefix: prefix) {
                return (UInt8(channel - 1), port)
            }
        }

        switch command {
        case "PLAY": return (0x0E, 0x00)
        case "STOP": return (0x0E, 0x01)
        case "RECORD": return (0x0E, 0x02)
        case "REWIND": return (0x0E, 0x03)
        case "FAST_FORWARD": return (0x0E, 0x04)
        case "CHANNEL_LEFT": return (0x10, 0x00)
        case "CHANNEL_RIGHT": return (0x10, 0x01)
        default: return nil
        }
    }

    private func channelNumber(from command: String, prefix: String) -> Int? {
        guard command.hasPrefix(prefix) else { return nil }
        let suffix = command.dropFirst(prefix.count)
        guard let channel = Int(suffix), (1...8).contains(channel) else { return nil }
        return channel
    }

    private func buildHuiSwitch(zone: UInt8, port: UInt8, state: Bool) -> [UInt8] {
        [
            0xB0, 0x0F, zone,
            0xB0, 0x2F, port | (state ? 0x40 : 0x00),
        ]
    }

    // MARK: - Pro Tools -> Hardware

    func receiveFromProTools(packetList: UnsafePointer<MIDIPacketList>) {
        var packetPointer = UnsafeRawPointer(packetList)
            .advanced(by: MemoryLayout.offset(of: \MIDIPacketList.packet)!)
            .assumingMemoryBound(to: MIDIPacket.self)

        for _ in 0..<packetList.pointee.numPackets {
            let packet = packetPointer.pointee
            let length = Int(packet.length)
            let bytes = withUnsafeBytes(of: packet.data) {
                Array($0.bindMemory(to: UInt8.self).prefix(length))
            }

            if bytes.count >= 3 {
                routeProToolsMessage(status: bytes[0], data1: bytes[1], data2: bytes[2])
            }

            packetPointer = UnsafePointer(MIDIPacketNext(packetPointer))
        }
    }

    private func routeProToolsMessage(status: UInt8, data1: UInt8, data2: UInt8) {
        switch (status, data1) {
        case (0x90, 0x00) where data2 == 0x00:
            sendToVirtualPort(bytes: [0x90, 0x00, 0x7F])

        case (0xB0, 0x0C):
            currentHUIZone = data2

        case (0xB0, 0x2C):
            let port = data2 & 0x0F
            let isOn = (data2 & 0x40) != 0
            handleSwitchFeedback(zone: currentHUIZone, port: port, isOn: isOn)

        case (0xA0, _):
            handleMeterFeedback(channel: data1, value: data2)

        case (0xB0, 0x00...0x07):
            handleFaderFeedback(channel: data1, value: data2)

        default:
            break
        }
    }

    private func handleSwitchFeedback(zone: UInt8, port: UInt8, isOn: Bool) {
        let command: String?

        if zone <= 7 {
            let channel = zone + 1
            switch port {
            case 0x00: command = "REC_\(channel)"
            case 0x02: command = "MUTE_\(channel)"
            case 0x03: command = "SOLO_\(channel)"
            case 0x04: command = "SELECT_\(channel)"
            default: command = nil
            }
        } else if zone == 0x0E {
            switch port {
            case 0x00: command = "PLAY"
            case 0x01: command = "STOP"
            case 0x02: command = "RECORD"
            case 0x03: command = "REWIND"
            case 0x04: command = "FAST_FORWARD"
            default: command = nil
            }
        } else {
            command = nil
        }

        guard let command,
              let mapping = presetManager.currentMappings.first(where: { $0.huiCommand == command }) else { return }

        // The SMC-Mixer firmware only lights button LEDs in response to fixed
        // firmware notes (rows starting at 24, 16, 8, 0), never via CC.
        if let ledNote = firmwareLedNote(for: command) {
            sendToHardwareNote(note: ledNote, isOn: isOn)
        } else {
            sendToHardware(cc: mapping.hardwareCC, value: isOn ? 0x7F : 0x00)
        }
    }

    /// SMC-Mixer LED notes per physical row. Each channel group has 4 buttons;
    /// rows are hard-coded in firmware: select row starts at 24, solo 16,
    /// mute 8, record 0. Falls back to CC only for unknown commands.
    private func firmwareLedNote(for command: String) -> UInt8? {
        if let channel = channelNumber(from: command, prefix: "MUTE_") {
            return UInt8(24 + channel - 1)
        }
        if let channel = channelNumber(from: command, prefix: "SOLO_") {
            return UInt8(16 + channel - 1)
        }
        if let channel = channelNumber(from: command, prefix: "REC_") {
            return UInt8(8 + channel - 1)
        }
        if let channel = channelNumber(from: command, prefix: "SELECT_") {
            return UInt8(0 + channel - 1)
        }
        return nil
    }

    private func handleMeterFeedback(channel: UInt8, value: UInt8) {
        guard channel <= 7,
              let mapping = presetManager.currentMappings.first(where: { $0.huiCommand == "PAN_\(channel + 1)" }) else { return }

        let scaled = min(UInt8(Float(value) * 10.5), 127)
        sendToHardware(cc: mapping.hardwareCC, value: scaled)
    }

    private func handleFaderFeedback(channel: UInt8, value: UInt8) {
        guard let mapping = presetManager.currentMappings.first(where: { $0.huiCommand == "FADER_\(channel + 1)" }) else { return }
        sendToHardware(cc: mapping.hardwareCC, value: value)
    }

    // MARK: - Transport

    private func sendToVirtualPort(bytes: [UInt8]) {
        guard virtualOutputPort != 0 else { return }

        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        let listSize = MemoryLayout.size(ofValue: packetList)

        var buffer = bytes
        packet = MIDIPacketListAdd(&packetList, listSize, packet, mach_absolute_time(), bytes.count, &buffer)

        MIDIReceived(virtualOutputPort, &packetList)
    }

    private func sendToHardware(cc: UInt8, value: UInt8) {
        NotificationCenter.default.post(
            name: Notification.Name("SendToHardware"),
            object: nil,
            userInfo: ["cc": cc, "value": value]
        )
    }

    private func sendToHardwareNote(note: UInt8, isOn: Bool) {
        NotificationCenter.default.post(
            name: Notification.Name("SendToHardware"),
            object: nil,
            userInfo: ["note": note, "isOn": isOn]
        )
    }
}
