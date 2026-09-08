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
            // A slow continuous slide can move far from its onset without a new
            // note attack. Require local pitch-change evidence as well as the
            // persistent anchor departure; do not flatten the detected contour.
            const auto recent = end > start + 3 ? end - 3 : start;
            persistent = persistent && std::abs(result.frames[end].midi - result.frames[recent].midi) > 0.5;
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

Document::Document(Analysis analysis) : data_(std::move(analysis)) {
    for(const auto& n:data_.notes)nextId_=std::max(nextId_,n.id+1);
}
void Document::commit(std::vector<Note> notes) {
    undo_.push_back({data_.notes,notes});data_.notes=std::move(notes);redo_.clear();
}
double Document::center(double start,double end,double fallback) const {
    std::vector<double> pitches;
    for(const auto& f:data_.frames)if(f.voiced&&f.time>=start&&f.time<end)pitches.push_back(f.midi);
    return pitches.empty()?fallback:median(std::move(pitches));
}
bool Document::transpose(std::size_t id, double semitones) {
    if (!std::isfinite(semitones) || std::abs(semitones) > 24) return false;
    auto found = std::find_if(data_.notes.begin(), data_.notes.end(),
                              [id](const Note& n) { return n.id == id; });
    if (found == data_.notes.end() || found->semitones == semitones) return false;
    auto notes=data_.notes;notes[found-data_.notes.begin()].semitones=semitones;commit(std::move(notes));
    return true;
}
bool Document::setFormant(std::size_t id,double semitones) {
    if(!std::isfinite(semitones)||std::abs(semitones)>6)return false;
    auto notes=data_.notes;
    auto found=std::find_if(notes.begin(),notes.end(),[id](const Note& n){return n.id==id;});
    if(found==notes.end()||found->formant==semitones)return false;
    found->formant=semitones;commit(std::move(notes));return true;
}
bool Document::setDrift(std::size_t id,double startCents,double endCents) {
    if(!std::isfinite(startCents)||!std::isfinite(endCents)||std::abs(startCents)>200||std::abs(endCents)>200)return false;
    auto notes=data_.notes;
    auto found=std::find_if(notes.begin(),notes.end(),[id](const Note& n){return n.id==id;});
    if(found==notes.end()||(found->driftStart==startCents&&found->driftEnd==endCents))return false;
    found->driftStart=startCents;found->driftEnd=endCents;commit(std::move(notes));return true;
}
bool Document::setVibrato(std::size_t id,double amount) {
    if(!std::isfinite(amount)||amount<0||amount>1)return false;
    auto notes=data_.notes;
    auto found=std::find_if(notes.begin(),notes.end(),[id](const Note& n){return n.id==id;});
    if(found==notes.end()||found->vibrato==amount)return false;
    found->vibrato=amount;commit(std::move(notes));return true;
}
bool Document::setGain(std::size_t id,double db) {
    if(!std::isfinite(db)||db < -24||db > 12)return false;
    auto notes=data_.notes;
    auto found=std::find_if(notes.begin(),notes.end(),[id](const Note& n){return n.id==id;});
    if(found==notes.end()||found->gainDb==db)return false;
    found->gainDb=db;commit(std::move(notes));return true;
}
bool Document::split(std::size_t id,double seconds) {
    if(!std::isfinite(seconds))return false;
    auto found=std::find_if(data_.notes.begin(),data_.notes.end(),[id](const Note& n){return n.id==id;});
    // Avoid unusable slivers, but permit manual notes below the detector's 60 ms gate.
    if(found==data_.notes.end()||found->driftStart!=0||found->driftEnd!=0||seconds-found->start<.02||found->end-seconds<.02)return false;
    auto notes=data_.notes;auto index=found-data_.notes.begin();Note right=*found;
    right.id=nextId_++;right.start=seconds;right.originalMidi=center(seconds,right.end,right.originalMidi);
    notes[index].end=seconds;notes[index].originalMidi=center(notes[index].start,seconds,notes[index].originalMidi);
    notes.insert(notes.begin()+index+1,right);commit(std::move(notes));return true;
}
bool Document::canJoinNext(std::size_t id) const {
    auto found=std::find_if(data_.notes.begin(),data_.notes.end(),[id](const Note& n){return n.id==id;});
    if(found==data_.notes.end()||found+1==data_.notes.end())return false;
    const auto& next=*(found+1);
    // Joining is a segmentation correction, not an implicit rewrite of another
    // note's pitch edit or processing of an intervening breath/silent region.
    return std::abs(next.start-found->end)<1e-6&&std::abs(next.semitones-found->semitones)<1e-9&&std::abs(next.gainDb-found->gainDb)<1e-9&&next.formant==found->formant&&next.vibrato==found->vibrato&&found->driftStart==0&&found->driftEnd==0&&next.driftStart==0&&next.driftEnd==0;
}
bool Document::joinNext(std::size_t id) {
    if(!canJoinNext(id))return false;
    auto notes=data_.notes;auto found=std::find_if(notes.begin(),notes.end(),[id](const Note& n){return n.id==id;});
    found->end=(found+1)->end;found->originalMidi=center(found->start,found->end,found->originalMidi);
    notes.erase(found+1);commit(std::move(notes));return true;
}
bool Document::remove(std::size_t id) {
    auto notes=data_.notes;auto found=std::find_if(notes.begin(),notes.end(),[id](const Note& n){return n.id==id;});
    if(found==notes.end())return false;
    notes.erase(found);commit(std::move(notes));return true;
}
bool Document::resize(std::size_t id,double start,double end) {
    if(!std::isfinite(start)||!std::isfinite(end)||start<0||end>data_.duration||end-start<.02)return false;
    auto found=std::find_if(data_.notes.begin(),data_.notes.end(),[id](const Note& n){return n.id==id;});
    if(found==data_.notes.end()||(found->start==start&&found->end==end))return false;
    if(found!=data_.notes.begin()&&start<(found-1)->end)return false;
    if(found+1!=data_.notes.end()&&end>(found+1)->start)return false;
    auto notes=data_.notes;auto index=found-data_.notes.begin();notes[index].start=start;notes[index].end=end;
    commit(std::move(notes));return true;
}
bool Document::undo() {
    if (undo_.empty()) return false;
    auto edit = undo_.back(); undo_.pop_back();
    data_.notes = edit.before;
    redo_.push_back(edit); return true;
}
bool Document::redo() {
    if (redo_.empty()) return false;
    auto edit = redo_.back(); redo_.pop_back();
    data_.notes = edit.after;
    undo_.push_back(edit); return true;
}
}
