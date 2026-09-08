#include "pitch_core.hpp"
#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <utility>

namespace pitch {
namespace {
double median(std::vector<double> values) {
    auto middle = values.begin() + values.size() / 2;
    std::nth_element(values.begin(), middle, values.end());
    return *middle;
}
}

Analysis analyze(const std::vector<float>& samples, double sr) {
    if (!std::isfinite(sr) || sr < 8000 || sr > 192000)
        throw std::invalid_argument("Sample rate must be between 8 and 192 kHz");
    for (auto sample : samples)
        if (!std::isfinite(sample)) throw std::invalid_argument("Non-finite audio sample");
    Analysis result;
    result.duration = samples.size() / sr;
    constexpr std::size_t samplesPerPeak = 32;
    result.waveformStep = samplesPerPeak / sr;
    result.waveform.reserve((samples.size() + samplesPerPeak - 1) / samplesPerPeak);
    for (std::size_t i = 0; i < samples.size(); i += samplesPerPeak) {
        auto range = std::minmax_element(samples.begin() + i,
            samples.begin() + std::min(samples.size(), i + samplesPerPeak));
        result.waveform.push_back({*range.first, *range.second});
    }
    // A constant comparison window avoids favoring large lags. Frames are
    // centered in source time; edge frames use only actual samples, no padding.
    const auto maxLag = static_cast<std::size_t>(std::ceil(sr / 65.0));
    const auto minLag = static_cast<std::size_t>(std::floor(sr / 1100.0));
    const auto window = maxLag;
    const auto frameSize = window + maxLag + 1;
    const auto hop = static_cast<std::size_t>(std::round(sr * 0.01));
    if (samples.size() < frameSize) return result;
    std::vector<double> cmnd(maxLag + 1);
    for (std::size_t offset = 0; offset + frameSize <= samples.size(); offset += hop) {
        Frame frame;
        frame.time = (offset + frameSize * 0.5) / sr;
        double mean = 0, variance = 0;
        for (std::size_t j = 0; j < frameSize; ++j) mean += samples[offset + j];
        mean /= frameSize;
        for (std::size_t j = 0; j < frameSize; ++j) {
            double v = samples[offset + j] - mean;
            variance += v * v;
        }
        // DC does not count as a voiced signal. -60 dB RMS gate.
        if (variance / frameSize < 1e-6) { result.frames.push_back(frame); continue; }
        double accumulated = 0;
        cmnd[0] = 1;
        for (std::size_t lag = 1; lag <= maxLag; ++lag) {
            double difference = 0;
            for (std::size_t j = 0; j < window; ++j) {
                double d = samples[offset + j] - samples[offset + j + lag];
                difference += d * d;
            }
            accumulated += difference;
            cmnd[lag] = accumulated > 0 ? difference * lag / accumulated : 1;
        }
        // First sufficiently periodic trough, followed to its local minimum.
        for (std::size_t lag = std::max<std::size_t>(2, minLag); lag < maxLag; ++lag) {
            if (cmnd[lag] >= 0.15) continue;
            while (lag + 1 < maxLag && cmnd[lag + 1] < cmnd[lag]) ++lag;
            double denominator = cmnd[lag - 1] - 2 * cmnd[lag] + cmnd[lag + 1];
            double adjustment = std::abs(denominator) > 1e-12
                ? 0.5 * (cmnd[lag - 1] - cmnd[lag + 1]) / denominator : 0;
            const double hz = sr / (lag + std::clamp(adjustment, -0.5, 0.5));
            if (hz >= 65 && hz <= 1100) {
                frame.midi = 69 + 12 * std::log2(hz / 440);
                frame.confidence = std::clamp(1 - cmnd[lag], 0.0, 1.0);
                frame.voiced = true;
            }
            break;
        }
        result.frames.push_back(frame);
    }
    // Segment voiced runs with a persistent pitch change, not rounded MIDI
    // values (rounding splits vibrato near semitone boundaries).
    const double hopSeconds = hop / sr;
    std::size_t start = 0;
    while (start < result.frames.size()) {
        if (!result.frames[start].voiced) { ++start; continue; }
        std::vector<double> pitches{result.frames[start].midi};
        std::size_t end = start + 1;
        for (; end < result.frames.size() && result.frames[end].voiced; ++end) {
            // Fixed-size onset anchor avoids quadratic cost on sustained notes.
            double center = median(std::vector<double>(pitches.begin(), pitches.begin() + std::min<std::size_t>(9, pitches.size())));
            bool persistent = end + 2 < result.frames.size();
            double direction = result.frames[end].midi - center;
            for (std::size_t k = end; persistent && k < end + 3; ++k) {
                double delta = result.frames[k].midi - center;
                persistent = result.frames[k].voiced && std::abs(delta) > 0.8 && delta * direction > 0;
            }
            if (persistent) break;
            pitches.push_back(result.frames[end].midi);
        }
        double beginTime = std::max(0.0, result.frames[start].time - hopSeconds * 0.5);
        double endTime = std::min(result.duration, result.frames[end - 1].time + hopSeconds * 0.5);
        if (endTime - beginTime >= 0.06)
            result.notes.push_back({result.notes.size(), beginTime, endTime, median(pitches), 0});
        start = end;
    }
    return result;
}

Document::Document(Analysis analysis) : data_(std::move(analysis)) {}
bool Document::transpose(std::size_t id, double semitones) {
    if (!std::isfinite(semitones) || std::abs(semitones) > 24) return false;
    auto found = std::find_if(data_.notes.begin(), data_.notes.end(),
                              [id](const Note& n) { return n.id == id; });
    if (found == data_.notes.end() || found->semitones == semitones) return false;
    undo_.push_back({static_cast<std::size_t>(found - data_.notes.begin()), found->semitones, semitones});
    found->semitones = semitones;
    redo_.clear();
    return true;
}
bool Document::undo() {
    if (undo_.empty()) return false;
    auto edit = undo_.back(); undo_.pop_back();
    data_.notes[edit.index].semitones = edit.before;
    redo_.push_back(edit); return true;
}
bool Document::redo() {
    if (redo_.empty()) return false;
    auto edit = redo_.back(); redo_.pop_back();
    data_.notes[edit.index].semitones = edit.after;
    undo_.push_back(edit); return true;
}
}
