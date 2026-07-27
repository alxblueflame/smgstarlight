#include "StarlightDynamicResolution.h"

#include <algorithm>

void StarlightDynamicResolution::SetLimits(float minimum, float maximum)
{
  m_minimum = std::clamp(minimum, 0.25f, 1.0f);
  m_maximum = std::clamp(maximum, m_minimum, 1.0f);
  m_scale = std::clamp(m_scale, m_minimum, m_maximum);
}

void StarlightDynamicResolution::SetTargetFrameRate(std::uint32_t frame_rate)
{
  m_target_frame_rate = std::clamp(frame_rate, 30u, 240u);
}

void StarlightDynamicResolution::SubmitGpuTime(double milliseconds)
{
  m_smoothed_gpu_ms =
      m_smoothed_gpu_ms == 0.0 ? milliseconds : m_smoothed_gpu_ms * 0.9 + milliseconds * 0.1;
  if (m_cooldown > 0)
  {
    --m_cooldown;
    return;
  }

  const double budget = 1000.0 / static_cast<double>(m_target_frame_rate);
  if (m_smoothed_gpu_ms > budget * 0.95 && m_scale > m_minimum)
  {
    m_scale = std::max(m_minimum, m_scale - 0.05f);
    m_cooldown = 12;
  }
  else if (m_smoothed_gpu_ms < budget * 0.72 && m_scale < m_maximum)
  {
    m_scale = std::min(m_maximum, m_scale + 0.025f);
    m_cooldown = 30;
  }
}

float StarlightDynamicResolution::GetScale() const
{
  return m_scale;
}
