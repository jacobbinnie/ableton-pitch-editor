#pragma once
#include <cstddef>
#include <vector>

namespace pitch {
struct Frame {
    double time = 0, midi = 0, confidence = 0;
    bool voiced = false;
};
struct Note {
    std::size_t id = 0;
    double start = 0, end = 0, originalMidi = 0, semitones = 0;
};
struct WavePeak { float minimum = 0, maximum = 0; };
struct Analysis {
    double duration = 0;
    double waveformStep = 0; // Seconds per min/max bin, measured from source zero.
    std::vector<WavePeak> waveform;
    std::vector<Frame> frames;
    std::vector<Note> notes;
};
// Offline worker only: mono normalized PCM, 8–192 kHz. Never call on audio/UI thread.
Analysis analyze(const std::vector<float>& samples, double sampleRate);

// Owns edit history independently of the host; original detection is immutable.
class Document {
public:
    explicit Document(Analysis analysis);
    const Analysis& analysis() const { return data_; }
    bool transpose(std::size_t id, double semitones);
    bool undo();
    bool redo();
private:
    struct Edit { std::size_t index; double before, after; };
    Analysis data_;
    std::vector<Edit> undo_, redo_;
};
}
