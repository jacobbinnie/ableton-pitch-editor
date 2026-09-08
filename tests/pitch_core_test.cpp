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
        std::vector<float> slide(22050);
        double slidePhase=0;
        for(std::size_t i=0;i<slide.size();++i){
            slidePhase+=2*M_PI*220*std::exp2((2.0*i/slide.size())/12)/22050;
            slide[i]=(float)(.25*std::sin(slidePhase));
        }
        auto sliding=pitch::analyze(slide,22050);
        require(sliding.notes.size()==1,"continuous slide fragmented");
        require(sliding.frames.back().midi-sliding.frames.front().midi>1.8,"slide contour flattened");
        pitch::Document d(a);
        require(d.transpose(0, 3), "edit accepted");
        require(d.analysis().notes[0].originalMidi == a.notes[0].originalMidi, "original pitch changed");
        require(d.analysis().notes[0].start == a.notes[0].start && d.analysis().notes[0].end == a.notes[0].end, "edit changed timing");
        require(d.undo() && d.analysis().notes[0].semitones == 0, "undo");
        require(d.redo() && d.analysis().notes[0].semitones == 3, "redo");
        require(d.undo() && d.transpose(1, -2) && !d.redo(), "branch clears redo");
        require(d.transpose(0, .37) && d.analysis().notes[0].semitones == .37, "fractional pitch retained");
        require(d.undo() && d.redo() && d.analysis().notes[0].semitones == .37, "fractional pitch undo/redo");
        require(!d.transpose(999, 2) && !d.transpose(0, 25) && !d.transpose(0, NAN), "invalid edit accepted");
        pitch::Analysis editable;
        editable.duration=1;editable.notes={{5,0,1,60,.37}};
        editable.frames={{.1,60,1,true},{.2,60,1,true},{.7,62,1,true},{.8,62,1,true}};
        pitch::Document regions(editable);
        require(!regions.split(999,.5)&&!regions.split(5,NAN)&&!regions.split(5,.01), "invalid split accepted");
        require(regions.split(5,.5), "split failed");
        auto rightId=regions.analysis().notes[1].id;
        require(regions.analysis().notes.size()==2&&rightId!=5, "split ids");
        require(regions.analysis().notes[0].end==.5&&regions.analysis().notes[1].start==.5, "split continuity");
        require(regions.analysis().notes[0].originalMidi==60&&regions.analysis().notes[1].originalMidi==62, "split centers");
        require(regions.analysis().notes[1].semitones==.37, "split loses offset");
        require(regions.transpose(rightId,1)&&!regions.canJoinNext(5), "join silently replaces pitch edit");
        require(regions.undo()&&regions.canJoinNext(5)&&regions.joinNext(5), "join failed");
        require(regions.analysis().notes.size()==1&&regions.analysis().notes[0].end==1, "joined bounds");
        require(regions.undo()&&regions.analysis().notes[1].id==rightId, "join undo lost ids");
        require(regions.redo()&&regions.undo()&&regions.undo()&&regions.analysis().notes.size()==1, "mixed structural history");
        require(regions.split(5,.4)&&regions.analysis().notes[1].id>rightId&&!regions.redo(), "branch reused id/history");
        pitch::Analysis gaps;gaps.notes={{0,0,.3,60,0},{1,.4,.6,60,0}};
        require(!pitch::Document(gaps).joinNext(0), "join crosses unvoiced gap");
        gaps.duration=1;pitch::Document bounds(gaps);
        require(!bounds.resize(0,-.1,.3)&&!bounds.resize(0,0,.5)&&!bounds.resize(0,0,.01)&&!bounds.resize(0,NAN,.3),"invalid boundary edit accepted");
        require(bounds.resize(0,0,.4)&&bounds.analysis().notes[0].end==.4,"expand into gap");
        require(!bounds.resize(1,.3,.7),"resize overlaps neighbor");
        require(bounds.remove(0)&&bounds.analysis().notes.size()==1,"remove region");
        require(bounds.resize(1,0,.8)&&bounds.analysis().notes[0].start==0,"expand into removed region");
        require(bounds.undo()&&bounds.undo()&&bounds.analysis().notes.size()==2&&bounds.analysis().notes[0].end==.4,"remove/resize undo history");
        require(bounds.remove(0)&&bounds.remove(1)&&bounds.analysis().notes.empty()&&!bounds.remove(99),"remove all regions");
        require(bounds.undo()&&bounds.analysis().notes.size()==1,"remove last undo");
        bool rejected = false;
        try { pitch::analyze({std::numeric_limits<float>::quiet_NaN()}, 44100); }
        catch (const std::invalid_argument&) { rejected = true; }
        require(rejected, "non-finite input accepted");
        std::cout << "PASS: waveform peaks/timing/tail, pitch accuracy, harmonics, rates, DC/noise, vibrato, silence, legato, timing, undo/redo, invalid input\n";
    } catch (const std::exception& e) {
        std::cerr << "FAIL: " << e.what() << '\n'; return 1;
    }
}
