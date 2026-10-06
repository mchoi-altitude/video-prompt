import AVFoundation
import Foundation

/// Writes the asset's audio as 16 kHz mono 16-bit WAV (what whisper.cpp expects).
/// Returns false when the asset has no audio track.
public func exportMonoWAV16k(_ asset: AVAsset, to url: URL) async throws -> Bool {
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard !tracks.isEmpty else { return false }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false])
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? MediaError.writeFailed("audio read") }
    var pcm = Data()
    while let sample = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        let len = CMBlockBufferGetDataLength(block)
        var chunk = Data(count: len)
        _ = chunk.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: len, destination: $0.baseAddress!) }
        pcm.append(chunk)
    }
    if reader.status == .failed { throw reader.error ?? MediaError.writeFailed("audio read") }

    var wav = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
    wav.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); wav.append(contentsOf: Array("WAVE".utf8))
    wav.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
    wav.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); wav.append(pcm)
    try wav.write(to: url, options: .atomic)
    return true
}
