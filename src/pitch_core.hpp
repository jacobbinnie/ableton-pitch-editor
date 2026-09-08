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
    double start = 0, end = 0, originalMidi = 0, semitones = 0, gainDb = 0, vibrato = 1, driftStart = 0, driftEnd = 0, formant = 0; // Drift endpoints in cents; formant shift in semitones.
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

// Owns edit history independently of the host; detected contours remain immutable while regions are editable.
class Document {
public:
    explicit Document(Analysis analysis);
    const Analysis& analysis() const { return data_; }
    bool transpose(std::size_t id, double semitones);
    bool setFormant(std::size_t id, double semitones);
    bool setDrift(std::size_t id, double startCents, double endCents);
    bool setVibrato(std::size_t id, double amount);
    bool setGain(std::size_t id, double db);
    bool split(std::size_t id, double seconds);
    bool canJoinNext(std::size_t id) const;
    bool joinNext(std::size_t id);
    bool remove(std::size_t id);
    bool resize(std::size_t id, double start, double end);
    bool undo();
    bool redo();
private:
    struct Edit { std::vector<Note> before, after; };
    void commit(std::vector<Note> notes);
    double center(double start, double end, double fallback) const;
    std::size_t nextId_ = 0;
    Analysis data_;
    std::vector<Edit> undo_, redo_;
};
}
