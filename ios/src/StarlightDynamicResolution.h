#pragma once

#include <cstdint>

class StarlightDynamicResolution
{
public:
  void SetLimits(float minimum, float maximum);
  void SetTargetFrameRate(std::uint32_t frame_rate);
  void SubmitGpuTime(double milliseconds);
  float GetScale() const;

private:
  float m_minimum = 0.5f;
  float m_maximum = 1.0f;
  float m_scale = 1.0f;
  double m_smoothed_gpu_ms = 0.0;
  std::uint32_t m_target_frame_rate = 60;
  std::uint32_t m_cooldown = 0;
};
