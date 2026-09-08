#pragma once
#include <cstddef>
#include <vector>

namespace pitch {
struct AudioAsset {
    double sampleRate = 0;
    std::vector<std::vector<float>> channels;
    std::size_t frames() const { return channels.empty() ? 0 : channels.front().size(); }
};
struct RegionEdit {
    std::size_t begin = 0, end = 0;
    double semitones = 0;
};
struct RenderPlan {
    std::vector<RegionEdit> regions;
    double transitionSeconds = .02;
    bool preserveFormants = true;
};
struct RenderResult {
    AudioAsset audio;
    std::size_t startPad = 0, startDelay = 0;
    double peak = 0;
    bool bypassed = false;
};
// Offline worker API. No calls from audio callbacks or UI drawing.
class Renderer {
public:
    virtual ~Renderer() = default;
    virtual RenderResult render(const AudioAsset&, const RenderPlan&) const = 0;
};
class RubberBandRenderer final : public Renderer {
public:
    RenderResult render(const AudioAsset&, const RenderPlan&) const override;
};
double semitonesAt(const RenderPlan&, double sourceFrame, double sampleRate);
}
