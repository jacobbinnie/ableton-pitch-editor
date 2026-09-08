#include "pitch_core.hpp"
#include <cmath>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>

static void require(bool ok, const char* message) {
    if (!ok) throw std::runtime_error(message);
}
static std::vector<float> tone(double hz, double sr, double seconds, bool harmonics = false, bool vibrato = false) {
    std::vector<float> audio(static_cast<std::size_t>(sr * seconds));
    double phase = 0;
    for (std::size_t i = 0; i < audio.size(); ++i) {
        double f = hz * std::pow(2.0, (vibrato ? 0.3 * std::sin(2 * M_PI * 5 * i / sr) : 0) / 12);
        phase += 2 * M_PI * f / sr;
        audio[i] = 0.25 * std::sin(phase) + (harmonics ? 0.4 * std::sin(2 * phase) + 0.15 * std::sin(3 * phase) : 0);
    }
    return audio;
}
int main() {
    try {
        for (double sr : {22050., 44100., 48000.}) {
            for (double hz : {82.4069, 220., 440., 880.}) {
                auto a = pitch::analyze(tone(hz, sr, 0.25, true), sr);
                require(a.notes.size() == 1, "harmonic tone should be one note");
                require(std::abs(a.notes[0].originalMidi - (69 + 12 * std::log2(hz / 440))) < 0.12, "pitch accuracy / octave error");
            }
        }
        require(pitch::analyze({}, 44100).waveform.empty(), "empty waveform");
        std::vector<float> impulses(65, 0);
        impulses[0] = .75f; impulses[31] = -.5f; impulses[32] = 1; impulses[64] = -.25f;
        auto wave = pitch::analyze(impulses, 44100);
        require(wave.waveform.size() == 3, "waveform tail bin missing");
        require(wave.waveformStep == 32.0 / 44100, "waveform source timing");
        require(wave.waveform[0].minimum == -.5f && wave.waveform[0].maximum == .75f, "waveform loses impulses");
        require(wave.waveform[1].minimum == 0 && wave.waveform[1].maximum == 1, "waveform bin boundary");
        require(wave.waveform[2].minimum == -.25f && wave.waveform[2].maximum == -.25f, "waveform tail padded");
        auto silence = pitch::analyze(std::vector<float>(64, 0), 48000);
        require(silence.waveform.size() == 2 && silence.waveform[1].minimum == 0 && silence.waveform[1].maximum == 0, "silent waveform");
        require(pitch::analyze({}, 44100).notes.empty(), "empty input");
        require(pitch::analyze(std::vector<float>(44100, 0.2f), 44100).notes.empty(), "DC must not create notes");
        std::mt19937 random(42);
        std::uniform_real_distribution<float> noise(-0.3f, 0.3f);
        std::vector<float> unvoiced(22050);
        for (auto& x : unvoiced) x = noise(random);
        require(pitch::analyze(unvoiced, 22050).notes.empty(), "noise must not create notes");
        auto vibrato = pitch::analyze(tone(440, 22050, 1, false, true), 22050);
        require(vibrato.notes.size() == 1, "vibrato fragmented note");
        auto sequence = tone(220, 22050, 0.3);
        sequence.insert(sequence.end(), 4410, 0);
        auto high = tone(330, 22050, 0.3);
        sequence.insert(sequence.end(), high.begin(), high.end());
        auto a = pitch::analyze(sequence, 22050);
        require(a.notes.size() == 2, "two tones separated by silence");
        require(a.notes[0].end < 0.33 && a.notes[1].start > 0.47, "source note timing");
        auto legato = tone(220, 22050, 0.3);
        auto adjacent = tone(246.9417, 22050, 0.3);
        legato.insert(legato.end(), adjacent.begin(), adjacent.end());
        require(pitch::analyze(legato, 22050).notes.size() == 2, "legato pitch transition");
        pitch::Document d(a);
        require(d.transpose(0, 3), "edit accepted");
        require(d.analysis().notes[0].originalMidi == a.notes[0].originalMidi, "original pitch changed");
        require(d.analysis().notes[0].start == a.notes[0].start && d.analysis().notes[0].end == a.notes[0].end, "edit changed timing");
        require(d.undo() && d.analysis().notes[0].semitones == 0, "undo");
        require(d.redo() && d.analysis().notes[0].semitones == 3, "redo");
        require(d.undo() && d.transpose(1, -2) && !d.redo(), "branch clears redo");
        require(!d.transpose(999, 2) && !d.transpose(0, 25) && !d.transpose(0, NAN), "invalid edit accepted");
        bool rejected = false;
        try { pitch::analyze({std::numeric_limits<float>::quiet_NaN()}, 44100); }
        catch (const std::invalid_argument&) { rejected = true; }
        require(rejected, "non-finite input accepted");
        std::cout << "PASS: waveform peaks/timing/tail, pitch accuracy, harmonics, rates, DC/noise, vibrato, silence, legato, timing, undo/redo, invalid input\n";
    } catch (const std::exception& e) {
        std::cerr << "FAIL: " << e.what() << '\n'; return 1;
    }
}
